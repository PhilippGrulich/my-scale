import Foundation
import HealthKit
import MyOpenScaleCore

/// Writes the four HealthKit-native body metrics for an owner-user weigh-in
/// (plan §5). No body-composition correlation type exists, so the samples are
/// saved as one batch. Partial readings (no impedance ⇒ NaN fat/lean) write
/// only the finite metrics.
final class HealthKitSink {

    enum AuthState: Equatable {
        case unknown
        case unavailable          // HealthKit not present (e.g. iPad)
        case notRequested
        case requested            // asked; HealthKit hides actual share status
        case failed(String)
    }

    private let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Metadata key carrying the scale impedance on this app's samples.
    static let impedanceKey = "MyOpenScaleImpedanceOhms"

    // The four metrics we write (plan: bodyMass, bodyFatPercentage,
    // leanBodyMass, bodyMassIndex).
    private var shareTypes: Set<HKSampleType> {
        Set([
            HKQuantityType.quantityType(forIdentifier: .bodyMass),
            HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage),
            HKQuantityType.quantityType(forIdentifier: .leanBodyMass),
            HKQuantityType.quantityType(forIdentifier: .bodyMassIndex),
        ].compactMap { $0 })
    }

    /// Read types: characteristics for composition math (DOB / sex), height to
    /// prefill the profile during onboarding, plus the body metrics so the
    /// dashboard shows the user's full history — including entries other apps,
    /// other scales or the Health app itself wrote. HealthKit never reveals whether a read was
    /// granted, so the app treats these as best-effort.
    private var readTypes: Set<HKObjectType> {
        Set(([
            HKObjectType.characteristicType(forIdentifier: .dateOfBirth),
            HKObjectType.characteristicType(forIdentifier: .biologicalSex),
        ] as [HKObjectType?] + [
            HKObjectType.quantityType(forIdentifier: .height),
            HKObjectType.quantityType(forIdentifier: .bodyMass),
            HKObjectType.quantityType(forIdentifier: .bodyFatPercentage),
            HKObjectType.quantityType(forIdentifier: .leanBodyMass),
            HKObjectType.quantityType(forIdentifier: .bodyMassIndex),
            // Activity context for the History feed.
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .stepCount),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed),
        ]).compactMap { $0 })
    }

    /// Basic identity details we can pre-fill from Apple Health during onboarding.
    /// Apple Health has no name field, so name is always entered by the user.
    /// Every field is optional: a missing/denied read, or a non-binary/unset sex,
    /// leaves the value nil for the user to fill in.
    struct HealthPrefill: Equatable {
        var dateOfBirth: Date?
        var sex: BiologicalSex?
        var heightCm: Double?
    }

    /// Best-effort read of DOB, biological sex, and most-recent height to seed the
    /// profile. Characteristics are synchronous; height needs a sample query, so
    /// the whole result is delivered once the height query returns. Completion on
    /// the main queue. A denied read surfaces as nil (HealthKit hides read grants).
    func readUserCharacteristics(_ completion: @escaping (HealthPrefill) -> Void) {
        guard Self.isAvailable else {
            DispatchQueue.main.async { completion(HealthPrefill()) }
            return
        }

        var prefill = HealthPrefill()

        // DOB (characteristic).
        if let components = try? store.dateOfBirthComponents() {
            prefill.dateOfBirth = Calendar(identifier: .gregorian).date(from: components)
        }
        // Biological sex (characteristic) → core binary enum; .other/.notSet ⇒ nil.
        if let hkSex = try? store.biologicalSex().biologicalSex {
            switch hkSex {
            case .male: prefill.sex = .male
            case .female: prefill.sex = .female
            default: prefill.sex = nil   // .other / .notSet / future cases
            }
        }

        // Height (quantity) → most recent sample.
        guard let heightType = HKQuantityType.quantityType(forIdentifier: .height) else {
            DispatchQueue.main.async { completion(prefill) }
            return
        }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(sampleType: heightType,
                                  predicate: nil,
                                  limit: 1,
                                  sortDescriptors: [sort]) { _, samples, _ in
            if let sample = (samples as? [HKQuantitySample])?.first {
                prefill.heightCm = sample.quantity.doubleValue(for: .meterUnit(with: .centi))
            }
            DispatchQueue.main.async { completion(prefill) }
        }
        store.execute(query)
    }

    /// Request authorization. Completion is delivered on the main queue.
    func requestAuthorization(_ completion: @escaping (AuthState) -> Void) {
        guard Self.isAvailable else {
            DispatchQueue.main.async { completion(.unavailable) }
            return
        }
        store.requestAuthorization(toShare: shareTypes, read: readTypes) { success, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failed(error.localizedDescription))
                } else {
                    completion(success ? .requested : .failed(String(localized: "Authorization not granted")))
                }
            }
        }
    }

    /// Write a finalized, attributed reading. Completion on the main queue.
    func write(composition: BodyComposition,
               capturedAt: Date,
               impedanceOhms: Int,
               profile: UserProfile,
               appBuild: String,
               completion: @escaping (Result<Void, Error>) -> Void) {
        guard Self.isAvailable else {
            DispatchQueue.main.async {
                completion(.failure(SinkError.unavailable))
            }
            return
        }

        let metadata: [String: Any] = [
            HKMetadataKeyWasUserEntered: false,
            Self.impedanceKey: impedanceOhms,
            "MochiAppBuild": appBuild,
            "MochiUserID": profile.id.uuidString,
        ]
        save(composition, at: capturedAt, metadata: metadata, completion: completion)
    }

    /// Write a weigh-in the user typed in (no scale). Flagged as user-entered so
    /// Apple Health shows it as a manual entry. Completion on the main queue.
    func writeManual(composition: BodyComposition,
                     at date: Date,
                     completion: @escaping (Result<Void, Error>) -> Void) {
        guard Self.isAvailable else {
            DispatchQueue.main.async { completion(.failure(SinkError.unavailable)) }
            return
        }
        save(composition, at: date, metadata: [HKMetadataKeyWasUserEntered: true], completion: completion)
    }

    private func save(_ composition: BodyComposition,
                      at capturedAt: Date,
                      metadata: [String: Any],
                      completion: @escaping (Result<Void, Error>) -> Void) {
        var samples: [HKQuantitySample] = []

        if let t = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            samples.append(HKQuantitySample(
                type: t,
                quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: composition.bodyMassKg),
                start: capturedAt, end: capturedAt, metadata: metadata))
        }
        if let t = HKQuantityType.quantityType(forIdentifier: .bodyMassIndex) {
            samples.append(HKQuantitySample(
                type: t,
                quantity: HKQuantity(unit: .count(), doubleValue: composition.bmi),
                start: capturedAt, end: capturedAt, metadata: metadata))
        }
        // Fat% / lean are NaN for partial (no-impedance) readings — skip those.
        if composition.bodyFatPercent.isFinite,
           let t = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) {
            samples.append(HKQuantitySample(
                type: t,
                quantity: HKQuantity(unit: .percent(), doubleValue: composition.bodyFatPercent / 100.0),
                start: capturedAt, end: capturedAt, metadata: metadata))
        }
        if composition.leanMassKg.isFinite,
           let t = HKQuantityType.quantityType(forIdentifier: .leanBodyMass) {
            samples.append(HKQuantitySample(
                type: t,
                quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: composition.leanMassKg),
                start: capturedAt, end: capturedAt, metadata: metadata))
        }

        guard !samples.isEmpty else {
            DispatchQueue.main.async { completion(.failure(SinkError.noSamples)) }
            return
        }

        store.save(samples) { success, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                } else if success {
                    completion(.success(()))
                } else {
                    completion(.failure(SinkError.saveFailed))
                }
            }
        }
    }

    /// Write the user's height to Apple Health so it syncs to other devices
    /// (notably the Apple Watch, which reads it back to compute body composition
    /// during a standalone weigh-in). Best-effort: silently no-ops if HealthKit is
    /// unavailable or the height type can't be resolved, and a denied share just
    /// fails the save. Completion (optional) on the main queue.
    func writeHeight(cm: Double, completion: ((Result<Void, Error>) -> Void)? = nil) {
        guard Self.isAvailable, cm > 0,
              let type = HKQuantityType.quantityType(forIdentifier: .height) else {
            DispatchQueue.main.async { completion?(.failure(SinkError.unavailable)) }
            return
        }
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: .meterUnit(with: .centi), doubleValue: cm),
            start: Date(), end: Date(),
            metadata: [HKMetadataKeyWasUserEntered: true])
        store.save(sample) { success, error in
            DispatchQueue.main.async {
                if let error = error { completion?(.failure(error)) }
                else if success { completion?(.success(())) }
                else { completion?(.failure(SinkError.saveFailed)) }
            }
        }
    }

    /// Read the user's full weight history from Apple Health for the chart.
    /// Returns samples ascending by date, in kg. Completion on the main queue.
    ///
    /// Note: HealthKit never reveals whether a *read* was authorized — a denied
    /// read returns an empty array, not an error. Callers must treat empty as
    /// "no data" rather than failure.
    func readWeightHistory(_ completion: @escaping (Result<[WeightSample], Error>) -> Void) {
        guard Self.isAvailable, let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            DispatchQueue.main.async { completion(.failure(SinkError.unavailable)) }
            return
        }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let query = HKSampleQuery(sampleType: type,
                                  predicate: nil,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [sort]) { _, samples, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            let kg = HKUnit.gramUnit(with: .kilo)
            let ownBundle = HKSource.default().bundleIdentifier
            let result: [WeightSample] = (samples as? [HKQuantitySample] ?? []).map {
                let source = $0.sourceRevision.source
                let impedance = ($0.metadata?[Self.impedanceKey] as? NSNumber)?.intValue
                return WeightSample(id: $0.uuid,
                                    date: $0.startDate,
                                    weightKg: $0.quantity.doubleValue(for: kg),
                                    isFromThisApp: source.bundleIdentifier == ownBundle,
                                    sourceName: source.name,
                                    impedanceOhms: impedance.flatMap { $0 > 0 ? $0 : nil })
            }
            DispatchQueue.main.async { completion(.success(result)) }
        }
        store.execute(query)
    }

    /// A body metric chartable from Apple Health history.
    enum MetricKind: String, Identifiable, CaseIterable {
        case bodyFat, lean, bmi
        var id: String { rawValue }
        var title: String {
            switch self { case .bodyFat: return String(localized: "Body Fat"); case .lean: return String(localized: "Lean Mass"); case .bmi: return String(localized: "BMI") }
        }
        var unitLabel: String {
            switch self { case .bodyFat: return "%"; case .lean: return "kg"; case .bmi: return "" }
        }
        fileprivate var hkIdentifier: HKQuantityTypeIdentifier {
            switch self { case .bodyFat: return .bodyFatPercentage; case .lean: return .leanBodyMass; case .bmi: return .bodyMassIndex }
        }
        fileprivate var hkUnit: HKUnit {
            switch self {
            case .bodyFat: return .percent()
            case .lean: return .gramUnit(with: .kilo)
            case .bmi: return .count()
            }
        }
        /// Multiply the raw HealthKit value to get the displayed value (fraction → %).
        fileprivate var displayScale: Double { self == .bodyFat ? 100 : 1 }
    }

    /// One point on a metric's timeline, already scaled to display units.
    struct MetricSample: Identifiable, Equatable {
        let id: UUID
        let date: Date
        let value: Double
    }

    /// Read a metric's full history from Apple Health, ascending by date, scaled
    /// to display units. Empty on denied read (HealthKit hides read grants).
    func readQuantityHistory(_ kind: MetricKind, completion: @escaping ([MetricSample]) -> Void) {
        guard Self.isAvailable, let type = HKQuantityType.quantityType(forIdentifier: kind.hkIdentifier) else {
            DispatchQueue.main.async { completion([]) }
            return
        }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let query = HKSampleQuery(sampleType: type, predicate: nil,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
            let unit = kind.hkUnit, scale = kind.displayScale
            let result = (samples as? [HKQuantitySample] ?? []).map {
                MetricSample(id: $0.uuid, date: $0.startDate, value: $0.quantity.doubleValue(for: unit) * scale)
            }
            DispatchQueue.main.async { completion(result) }
        }
        store.execute(query)
    }

    /// Most recent value of a metric from any source (nil if none / denied).
    func readLatest(_ kind: MetricKind, completion: @escaping (MetricSample?) -> Void) {
        guard Self.isAvailable, let type = HKQuantityType.quantityType(forIdentifier: kind.hkIdentifier) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
            let latest = (samples as? [HKQuantitySample])?.first.map {
                MetricSample(id: $0.uuid, date: $0.startDate,
                             value: $0.quantity.doubleValue(for: kind.hkUnit) * kind.displayScale)
            }
            DispatchQueue.main.async { completion(latest) }
        }
        store.execute(query)
    }

    private var observers: [HKObserverQuery] = []

    /// Call `onChange` (main queue) whenever any app adds or deletes weight or
    /// body-composition samples, e.g. a manual entry in the Health app, so the
    /// dashboard refreshes while it's open. Idempotent.
    func observeBodyChanges(_ onChange: @escaping () -> Void) {
        guard Self.isAvailable, observers.isEmpty else { return }
        let ids: [HKQuantityTypeIdentifier] = [.bodyMass, .bodyFatPercentage, .leanBodyMass, .bodyMassIndex]
        for id in ids {
            guard let type = HKQuantityType.quantityType(forIdentifier: id) else { continue }
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, error in
                if error == nil { DispatchQueue.main.async { onChange() } }
                completionHandler()
            }
            observers.append(query)
            store.execute(query)
        }
    }

    /// Delete a weigh-in: removes the body samples THIS app wrote at `date`
    /// (weight, BMI, body fat, lean mass) from Apple Health. Only our own source
    /// is touched, so manual Health entries / other apps are left alone.
    /// Completion on the main queue.
    func deleteMeasurement(at date: Date, completion: @escaping (Result<Void, Error>) -> Void) {
        guard Self.isAvailable else {
            DispatchQueue.main.async { completion(.failure(SinkError.unavailable)) }
            return
        }
        let types = [
            HKQuantityType.quantityType(forIdentifier: .bodyMass),
            HKQuantityType.quantityType(forIdentifier: .bodyMassIndex),
            HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage),
            HKQuantityType.quantityType(forIdentifier: .leanBodyMass),
        ].compactMap { $0 }

        // Samples are saved with start == end == capturedAt; match a tight window
        // around it, restricted to this app's source.
        let window = HKQuery.predicateForSamples(withStart: date.addingTimeInterval(-1),
                                                 end: date.addingTimeInterval(1),
                                                 options: [])
        let mine = HKQuery.predicateForObjects(from: .default())
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [window, mine])

        let group = DispatchGroup()
        let lock = NSLock()
        var firstError: Error?

        for type in types {
            group.enter()
            store.deleteObjects(of: type, predicate: predicate) { _, _, error in
                // HealthKit reports "no objects deleted" as an error; ignore it so
                // a partial weigh-in (e.g. no fat sample) doesn't fail the delete.
                if let error = error as NSError?,
                   !(error.domain == HKError.errorDomain && error.code == HKError.Code.errorNoData.rawValue) {
                    lock.lock(); if firstError == nil { firstError = error }; lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if let firstError { completion(.failure(firstError)) }
            else { completion(.success(())) }
        }
    }

    /// Correct a weigh-in this app wrote. HealthKit samples are immutable, so
    /// this collects the app's own samples at `oldDate` (weight, BMI, body fat,
    /// lean mass), saves a corrected set at `newDate`, and only then deletes
    /// exactly those old objects — a failed save leaves the original intact.
    /// Body fat keeps its percentage; lean mass and BMI follow the new weight.
    /// Completion on the main queue.
    func replaceMeasurement(at oldDate: Date,
                            newWeightKg: Double,
                            newDate: Date,
                            heightCm: Double,
                            completion: @escaping (Result<Void, Error>) -> Void) {
        guard Self.isAvailable else {
            DispatchQueue.main.async { completion(.failure(SinkError.unavailable)) }
            return
        }
        let ids: [HKQuantityTypeIdentifier] = [.bodyMass, .bodyMassIndex, .bodyFatPercentage, .leanBodyMass]
        let window = HKQuery.predicateForSamples(withStart: oldDate.addingTimeInterval(-1),
                                                 end: oldDate.addingTimeInterval(1), options: [])
        let mine = HKQuery.predicateForObjects(from: .default())
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [window, mine])

        let group = DispatchGroup()
        let lock = NSLock()
        var old: [HKSample] = []
        var bodyFatPercent: Double?
        var impedance: Any?
        for id in ids {
            guard let type = HKQuantityType.quantityType(forIdentifier: id) else { continue }
            group.enter()
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let found = samples ?? []
                lock.lock()
                old.append(contentsOf: found)
                if id == .bodyFatPercentage, let s = found.first as? HKQuantitySample {
                    bodyFatPercent = s.quantity.doubleValue(for: .percent()) * 100
                }
                if id == .bodyMass, let s = found.first {
                    impedance = s.metadata?[Self.impedanceKey]
                }
                lock.unlock()
                group.leave()
            }
            store.execute(query)
        }
        group.notify(queue: .main) { [self] in
            guard !old.isEmpty else { completion(.failure(SinkError.noSamples)); return }
            let composition = BodyCompositionCalculator.manual(weightKg: newWeightKg,
                                                               bodyFatPercent: bodyFatPercent,
                                                               heightCm: heightCm)
            // Keep the impedance so the other body-composition estimates
            // survive a corrected weight.
            var metadata: [String: Any] = [HKMetadataKeyWasUserEntered: true]
            if let impedance { metadata[Self.impedanceKey] = impedance }
            save(composition, at: newDate, metadata: metadata) { [self] result in
                guard case .success = result else { completion(result); return }
                store.delete(old) { _, error in
                    DispatchQueue.main.async {
                        if let error { completion(.failure(error)) } else { completion(.success(())) }
                    }
                }
            }
        }
    }

    // MARK: - Activity (History feed)

    /// A workout from any app (Apple Watch, Strava, …).
    struct WorkoutEntry: Identifiable, Equatable {
        let id: UUID
        let start: Date
        let end: Date
        let activityType: HKWorkoutActivityType
        let activeKcal: Double?
        let sourceName: String
        var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    /// Per-day totals; nil = no data that day.
    struct DailyTotals: Equatable {
        var steps: Double?
        var activeKcal: Double?
        var eatenKcal: Double?
    }

    /// Workouts since `start`, newest first. Empty when denied/unavailable.
    func readWorkouts(since start: Date, completion: @escaping ([WorkoutEntry]) -> Void) {
        guard Self.isAvailable else { DispatchQueue.main.async { completion([]) }; return }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
            let energy = HKQuantityType(.activeEnergyBurned)
            let result = (samples as? [HKWorkout] ?? []).map { w in
                WorkoutEntry(id: w.uuid, start: w.startDate, end: w.endDate,
                             activityType: w.workoutActivityType,
                             activeKcal: w.statistics(for: energy)?.sumQuantity()?.doubleValue(for: .kilocalorie()),
                             sourceName: w.sourceRevision.source.name)
            }
            DispatchQueue.main.async { completion(result) }
        }
        store.execute(query)
    }

    /// Daily sums of steps, active energy and eaten energy since `start`,
    /// keyed by the start of each local day.
    func readDailyTotals(since start: Date, completion: @escaping ([Date: DailyTotals]) -> Void) {
        guard Self.isAvailable else { DispatchQueue.main.async { completion([:]) }; return }
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: start)
        let kinds: [(HKQuantityTypeIdentifier, HKUnit, WritableKeyPath<DailyTotals, Double?>)] = [
            (.stepCount, .count(), \.steps),
            (.activeEnergyBurned, .kilocalorie(), \.activeKcal),
            (.dietaryEnergyConsumed, .kilocalorie(), \.eatenKcal),
        ]
        let group = DispatchGroup()
        let lock = NSLock()
        var totals: [Date: DailyTotals] = [:]
        for (id, unit, keyPath) in kinds {
            group.enter()
            let query = HKStatisticsCollectionQuery(
                quantityType: HKQuantityType(id),
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: anchor, end: nil, options: []),
                options: .cumulativeSum, anchorDate: anchor, intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, collection, _ in
                collection?.enumerateStatistics(from: anchor, to: Date()) { stats, _ in
                    guard let sum = stats.sumQuantity()?.doubleValue(for: unit), sum > 0 else { return }
                    let day = calendar.startOfDay(for: stats.startDate)
                    lock.lock()
                    totals[day, default: DailyTotals()][keyPath: keyPath] = sum
                    lock.unlock()
                }
                group.leave()
            }
            store.execute(query)
        }
        group.notify(queue: .main) { completion(totals) }
    }

    /// Ask for the activity read types (only new types prompt; already
    /// answered ones return immediately). Completion on the main queue.
    func requestActivityAuthorization(_ completion: @escaping () -> Void) {
        guard Self.isAvailable else { DispatchQueue.main.async(execute: completion); return }
        store.requestAuthorization(toShare: shareTypes, read: readTypes) { _, _ in
            DispatchQueue.main.async(execute: completion)
        }
    }

    /// HealthKit's own texts ("Not authorized") are terse and not always
    /// localized; for a denied share, say where to turn it on.
    static func userMessage(for error: Error) -> String {
        if let hk = error as? HKError,
           hk.code == .errorAuthorizationDenied || hk.code == .errorAuthorizationNotDetermined {
            return String(localized: "Mochi may not save to Apple Health. Allow it in the Health app under Profile › Apps › Mochi.")
        }
        return error.localizedDescription
    }

    enum SinkError: LocalizedError {
        case unavailable, noSamples, saveFailed
        var errorDescription: String? {
            switch self {
            case .unavailable: return String(localized: "HealthKit is unavailable on this device.")
            case .noSamples: return String(localized: "No valid samples to write.")
            case .saveFailed: return String(localized: "HealthKit save failed.")
            }
        }
    }
}
