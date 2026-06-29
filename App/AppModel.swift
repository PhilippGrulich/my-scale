import Foundation
import SwiftUI
import MiScaleCore

/// One finalized weigh-in as shown in the UI, with its attribution + sink status.
struct LoggedReading: Identifiable, Equatable {
    let id = UUID()
    var capturedAt: Date
    var weightKg: Double
    var impedanceOhms: Int
    var resolution: String
    var composition: BodyComposition?
    var healthKitStatus: SinkStatus
    var note: String?

    enum SinkStatus: Equatable {
        case skipped(String)
        case pending
        case written
        case failed(String)

        var label: String {
            switch self {
            case .skipped(let why): return "Skipped (\(why))"
            case .pending: return "Saving to Health…"
            case .written: return "Saved to Apple Health"
            case .failed(let why): return "Sync failed: \(why)"
            }
        }
    }
}

/// Lifecycle of a weigh-in as the UI experiences it. Derived from the raw frame
/// stream (the finalizer only enters `.measuring` after stabilization, so it
/// can't represent the step-on ramp — see plan).
enum MeasurementPhase: Equatable {
    case idle
    case measuring(liveWeightKg: Double)    // stepping on / stabilizing, no impedance yet
    case finalizing(liveWeightKg: Double)   // stable + impedance present, settling
    case result(LoggedReading)              // committed reading + sync status

    var isActive: Bool { self != .idle }
}

/// App-layer orchestrator (plan §1 AppCoordinator / MeasurementPipeline).
/// Wires the BLE scanner to the pure core (parse → finalize already done in the
/// scanner) → resolve → compute → HealthKit, and publishes view state.
@MainActor
final class AppModel: ObservableObject {

    // Published view state.
    @Published var bleStatus: BLEStatus = .unknown
    @Published var healthAuth: HealthKitSink.AuthState = .notRequested
    @Published var profile: StoredProfile
    @Published private(set) var recentFrames: [ObservedFrame] = []
    @Published private(set) var readings: [LoggedReading] = []
    @Published private(set) var measurementPhase: MeasurementPhase = .idle
    /// When the current in-progress weigh-in began (drives the overlay's
    /// progress + the "save current weight" escape hatch). Nil when idle.
    @Published private(set) var liveStartedAt: Date?
    @Published private(set) var weightHistory: [WeightSample] = []
    @Published private(set) var lastSyncError: String?

    private let scanner: BLEScanner
    private let healthKit = HealthKitSink()

    private let maxFrames = 40
    private let maxReadings = 20
    /// Ignore sub-threshold weights so an empty scale doesn't trigger the overlay.
    private let minLiveWeightKg = 5.0

    private var idleTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var simulateTask: Task<Void, Never>?

    private var appBuild: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(v) (\(b))"
    }

    init() {
        self.profile = ProfileStore.load()
        self.scanner = BLEScanner()
        if !HealthKitSink.isAvailable { self.healthAuth = .unavailable }

        scanner.onStatusChange = { [weak self] status in
            Task { @MainActor in self?.bleStatus = status }
        }
        scanner.onFrame = { [weak self] frame in
            Task { @MainActor in self?.appendFrame(frame) }
        }
        scanner.onReading = { [weak self] reading, _ in
            Task { @MainActor in self?.handle(reading) }
        }
    }

    // MARK: - Derived view state

    var currentWeightKg: Double? {
        weightHistory.last?.weightKg ?? readings.first?.weightKg
    }

    var trendDeltaKg: Double? {
        WeightHistory.trendDeltaKg(weightHistory)
    }

    var latestComposition: BodyComposition? {
        readings.first?.composition
    }

    // MARK: - Lifecycle

    func requestHealthAuthorization() {
        healthKit.requestAuthorization { [weak self] state in
            self?.healthAuth = state
            if state == .requested { self?.loadWeightHistory() }
        }
    }

    /// Refresh weight history from Apple Health. Keeps the last good data on a
    /// transient failure; empty results are "no data", not an error.
    func loadWeightHistory() {
        healthKit.readWeightHistory { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let samples):
                self.weightHistory = samples
                self.lastSyncError = nil
            case .failure(let error):
                self.lastSyncError = error.localizedDescription
            }
        }
    }

    /// Called by the view when the app returns to the foreground.
    func onForeground() {
        loadWeightHistory()
    }

    func saveProfile(_ updated: StoredProfile) {
        profile = updated
        ProfileStore.save(updated)
    }

    /// Manually dismiss the weigh-in overlay.
    func dismissOverlay() {
        dismissTask?.cancel()
        idleTask?.cancel()
        simulateTask?.cancel()
        liveStartedAt = nil
        measurementPhase = .idle
    }

    /// Finalize the current live (possibly not-yet-stable) weight on demand —
    /// the escape hatch when the scale never sends an impedance/stable frame.
    /// No impedance ⇒ partial composition (weight + BMI only).
    func acceptCurrentLiveWeight() {
        let live: Double
        switch measurementPhase {
        case .measuring(let w), .finalizing(let w): live = w
        default: return
        }
        idleTask?.cancel()
        simulateTask?.cancel()
        handle(FinalizedReading(weightKg: live, impedanceOhms: 0,
                                capturedAt: Date(), deviceTimestamp: nil))
    }

    /// Inject a synthetic weigh-in so the full resolve→compute→HealthKit path
    /// (and the live overlay animation) can be exercised without the scale.
    func simulateWeighIn(weightKg: Double = 80.0, impedanceOhms: Int = 500, animated: Bool = true) {
        guard animated else {
            handle(FinalizedReading(weightKg: weightKg, impedanceOhms: impedanceOhms,
                                    capturedAt: Date(), deviceTimestamp: nil))
            return
        }
        simulateTask?.cancel()
        liveStartedAt = Date()
        simulateTask = Task { [weak self] in
            guard let self else { return }
            let steps = 12
            for i in 1...steps {
                if Task.isCancelled { return }
                let w = max(self.minLiveWeightKg, weightKg * Double(i) / Double(steps))
                self.measurementPhase = .measuring(liveWeightKg: w)
                try? await Task.sleep(nanoseconds: 110_000_000)
            }
            if Task.isCancelled { return }
            self.measurementPhase = .finalizing(liveWeightKg: weightKg)
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            self.handle(FinalizedReading(weightKg: weightKg, impedanceOhms: impedanceOhms,
                                         capturedAt: Date(), deviceTimestamp: nil))
        }
    }

    // MARK: - Live frame → phase

    private func appendFrame(_ frame: ObservedFrame) {
        recentFrames.insert(frame, at: 0)
        if recentFrames.count > maxFrames { recentFrames.removeLast(recentFrames.count - maxFrames) }
        updatePhase(from: frame.parsed)
    }

    private func updatePhase(from adv: ParsedAdvertisement) {
        // Never disturb a result that's being shown / auto-dismissed (the stable
        // burst keeps arriving during the finalizer's cooldown).
        if case .result = measurementPhase { return }
        guard !adv.isWeightRemoved, adv.weightKg >= minLiveWeightKg else { return }

        if liveStartedAt == nil { liveStartedAt = Date() }
        measurementPhase = (adv.isStabilized && adv.hasImpedance)
            ? .finalizing(liveWeightKg: adv.weightKg)
            : .measuring(liveWeightKg: adv.weightKg)
        armIdleTimer()
    }

    /// Clear a half-finished weigh-in (user stepped on then off) if frames stop.
    private func armIdleTimer() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self, !Task.isCancelled else { return }
            switch self.measurementPhase {
            case .measuring, .finalizing:
                self.liveStartedAt = nil
                self.measurementPhase = .idle
            default: break
            }
        }
    }

    // MARK: - Pipeline

    private func handle(_ reading: FinalizedReading) {
        let coreProfile = profile.coreProfile
        let resolution = UserResolver.resolve(weightKg: reading.weightKg, among: [coreProfile])

        var logged = LoggedReading(
            capturedAt: reading.capturedAt,
            weightKg: reading.weightKg,
            impedanceOhms: reading.impedanceOhms,
            resolution: describe(resolution),
            composition: nil,
            healthKitStatus: .skipped("not attributed")
        )

        guard case .matched(let user) = resolution else {
            logged.note = "Held for manual confirmation (Unassigned queue)."
            finish(with: logged)
            return
        }

        // Compute composition (full if impedance present, else partial).
        let bodyProfile = BodyProfile(from: user, at: reading.capturedAt)
        let composition: BodyComposition
        if (1...3000).contains(reading.impedanceOhms) {
            composition = BodyCompositionCalculator.compute(
                weightKg: reading.weightKg,
                impedanceOhms: Double(reading.impedanceOhms),
                profile: bodyProfile)
        } else {
            composition = BodyCompositionCalculator.partial(
                weightKg: reading.weightKg, profile: bodyProfile)
            logged.note = "No impedance — weight + BMI only."
        }
        logged.composition = composition

        guard user.isHealthKitOwner else {
            logged.healthKitStatus = .skipped("not the Health owner")
            finish(with: logged)
            return
        }

        logged.healthKitStatus = .pending
        finish(with: logged)
        let readingID = logged.id

        healthKit.write(composition: composition,
                        capturedAt: reading.capturedAt,
                        impedanceOhms: reading.impedanceOhms,
                        profile: user,
                        appBuild: appBuild) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.updateStatus(readingID, .written)
                self.loadWeightHistory()   // reflect the just-written sample in the chart
            case .failure(let error):
                self.updateStatus(readingID, .failed(error.localizedDescription))
            }
        }
    }

    /// Record a finalized reading, surface it as the overlay result, and arm the
    /// auto-dismiss back to idle.
    private func finish(with logged: LoggedReading) {
        push(logged)
        liveStartedAt = nil
        measurementPhase = .result(logged)
        armDismiss(for: logged.id)
    }

    private func armDismiss(for id: UUID) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard let self, !Task.isCancelled else { return }
            if case .result(let r) = self.measurementPhase, r.id == id {
                self.measurementPhase = .idle
            }
        }
    }

    private func push(_ reading: LoggedReading) {
        readings.insert(reading, at: 0)
        if readings.count > maxReadings { readings.removeLast(readings.count - maxReadings) }
    }

    private func updateStatus(_ id: UUID, _ status: LoggedReading.SinkStatus) {
        guard let idx = readings.firstIndex(where: { $0.id == id }) else { return }
        readings[idx].healthKitStatus = status
        // Keep the overlay's sync badge in sync if it's still showing this reading.
        if case .result(let r) = measurementPhase, r.id == id {
            measurementPhase = .result(readings[idx])
        }
    }

    private func describe(_ resolution: UserResolution) -> String {
        switch resolution {
        case .matched(let u): return "Matched \(u.name)"
        case .ambiguous(let users): return "Ambiguous (\(users.count) users)"
        case .noMatch: return "No match"
        }
    }
}
