import Foundation
import Combine
import MiScaleCore

/// App orchestrator: owns persisted state and wires
/// scan → parse → finalize → resolve → compute → store → sinks.
@MainActor
final class AppModel: ObservableObject {

    @Published var profiles: [StoredProfile]
    @Published var measurements: [StoredMeasurement]
    @Published var haConfig: HAConfig
    @Published var healthKitAuthorized = false

    let scanner = BLEScanner()
    private let store: PersistenceStore
    private let healthKit = HealthKitSink()
    private let ha = HASink()

    init(store: PersistenceStore = PersistenceStore()) {
        self.store = store
        let state = store.load()
        profiles = state.profiles
        measurements = state.measurements
        haConfig = state.ha

        scanner.onReading = { [weak self] reading, data in
            // CoreBluetooth callbacks land on the main queue; hop onto the main
            // actor so the compiler is satisfied and state mutation is safe.
            Task { @MainActor in self?.handle(reading, rawData: data) }
        }
    }

    func start() { scanner.start() }

    // MARK: - Pipeline

    private func handle(_ reading: FinalizedReading, rawData: Data) {
        let resolution = UserResolver.resolve(weightKg: reading.weightKg, among: profiles.map(\.core))

        var record = StoredMeasurement(
            capturedAt: reading.capturedAt,
            deviceTimestamp: reading.deviceTimestamp,
            weightKg: reading.weightKg,
            impedanceOhms: reading.impedanceOhms,
            assignedUserID: nil,
            resolution: .noMatch,
            composition: nil,
            rawServiceDataHex: rawData.hexString
        )

        switch resolution {
        case let .matched(user):
            record.resolution = .matched
            record.assignedUserID = user.id
            record.composition = composition(weightKg: reading.weightKg,
                                             impedanceOhms: reading.impedanceOhms,
                                             user: user, at: reading.capturedAt)
        case .ambiguous:
            record.resolution = .ambiguous
        case .noMatch:
            record.resolution = .noMatch
        }

        measurements.insert(record, at: 0)
        persist()

        if record.resolution == .matched, let profile = profile(for: record.assignedUserID) {
            deliverSinks(measurementID: record.id, profile: profile)
        }
    }

    /// Manually attribute an unassigned reading, then compute and deliver it.
    func assign(measurementID: UUID, to profile: StoredProfile) {
        guard let idx = measurements.firstIndex(where: { $0.id == measurementID }) else { return }
        measurements[idx].assignedUserID = profile.id
        measurements[idx].resolution = .manual
        measurements[idx].composition = composition(weightKg: measurements[idx].weightKg,
                                                    impedanceOhms: measurements[idx].impedanceOhms,
                                                    user: profile.core, at: measurements[idx].capturedAt)
        persist()
        deliverSinks(measurementID: measurementID, profile: profile)
    }

    // MARK: - Sinks

    private func deliverSinks(measurementID: UUID, profile: StoredProfile) {
        guard let record = measurement(measurementID), let composition = record.composition else { return }

        // HealthKit — owner only (single-profile device).
        if profile.isHealthKitOwner {
            Task {
                do {
                    try await healthKit.write(composition, at: record.capturedAt,
                                              impedanceOhms: record.impedanceOhms)
                    update(measurementID) { $0.healthKitState = .written }
                } catch {
                    update(measurementID) { $0.healthKitState = .failed }
                }
            }
        } else {
            update(measurementID) { $0.healthKitState = .skipped }
        }

        // Home Assistant — optional, isolated from the HealthKit path.
        let payload = HASink.Payload(
            user: profile.name,
            capturedAt: record.capturedAt,
            weightKg: composition.bodyMassKg,
            bodyFatPercent: composition.bodyFatPercent.isNaN ? nil : composition.bodyFatPercent,
            leanMassKg: composition.leanMassKg.isNaN ? nil : composition.leanMassKg,
            bmi: composition.bmi,
            impedanceOhms: record.impedanceOhms
        )
        let config = haConfig
        Task {
            let ok = await ha.post(payload, config: config)
            update(measurementID) { $0.haState = ok ? .written : (config.enabled ? .failed : .skipped) }
        }
    }

    func requestHealthKitAuthorization() {
        Task {
            do {
                try await healthKit.requestAuthorization()
                healthKitAuthorized = true
            } catch {
                healthKitAuthorized = false
            }
        }
    }

    // MARK: - Profile editing

    func upsert(_ profile: StoredProfile) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }
        // Enforce a single HealthKit owner.
        if profile.isHealthKitOwner {
            for i in profiles.indices where profiles[i].id != profile.id {
                profiles[i].isHealthKitOwner = false
            }
        }
        persist()
    }

    func deleteProfiles(at offsets: IndexSet) {
        profiles.remove(atOffsets: offsets)
        persist()
    }

    func updateHAConfig(_ config: HAConfig) {
        haConfig = config
        persist()
    }

    var rangeWarnings: [RangeWarning] { UserResolver.rangeWarnings(profiles.map(\.core)) }

    // MARK: - Helpers

    private func composition(weightKg: Double, impedanceOhms: Int,
                             user: UserProfile, at date: Date) -> BodyComposition {
        let bodyProfile = BodyProfile(from: user, at: date)
        if impedanceOhms > 0 {
            return BodyCompositionCalculator.compute(weightKg: weightKg,
                                                     impedanceOhms: Double(impedanceOhms),
                                                     profile: bodyProfile)
        }
        return BodyCompositionCalculator.partial(weightKg: weightKg, profile: bodyProfile)
    }

    func profile(for id: UUID?) -> StoredProfile? {
        guard let id else { return nil }
        return profiles.first { $0.id == id }
    }

    private func measurement(_ id: UUID) -> StoredMeasurement? {
        measurements.first { $0.id == id }
    }

    private func update(_ id: UUID, _ transform: (inout StoredMeasurement) -> Void) {
        guard let idx = measurements.firstIndex(where: { $0.id == id }) else { return }
        transform(&measurements[idx])
        persist()
    }

    private func persist() {
        store.save(PersistedState(profiles: profiles, measurements: measurements, ha: haConfig))
    }
}
