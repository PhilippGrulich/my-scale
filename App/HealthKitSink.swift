import Foundation
import HealthKit
import MiScaleCore

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

    /// Read types: characteristics for composition math (DOB / sex) plus bodyMass
    /// so we can chart the user's full weight history. HealthKit never reveals
    /// whether a read was granted, so the app treats these as best-effort.
    private var readTypes: Set<HKObjectType> {
        Set(([
            HKObjectType.characteristicType(forIdentifier: .dateOfBirth),
            HKObjectType.characteristicType(forIdentifier: .biologicalSex),
        ] as [HKObjectType?] + [
            HKObjectType.quantityType(forIdentifier: .bodyMass),
        ]).compactMap { $0 })
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
                    completion(success ? .requested : .failed("Authorization not granted"))
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
            "MiScaleImpedanceOhms": impedanceOhms,
            "MiScaleAppBuild": appBuild,
            "MiScaleUserID": profile.id.uuidString,
        ]

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
            let result: [WeightSample] = (samples as? [HKQuantitySample] ?? []).map {
                WeightSample(id: $0.uuid,
                             date: $0.startDate,
                             weightKg: $0.quantity.doubleValue(for: kg))
            }
            DispatchQueue.main.async { completion(.success(result)) }
        }
        store.execute(query)
    }

    enum SinkError: LocalizedError {
        case unavailable, noSamples, saveFailed
        var errorDescription: String? {
            switch self {
            case .unavailable: return "HealthKit is unavailable on this device."
            case .noSamples: return "No valid samples to write."
            case .saveFailed: return "HealthKit save failed."
            }
        }
    }
}
