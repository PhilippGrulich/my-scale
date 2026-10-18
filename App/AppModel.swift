import Foundation
import SwiftUI
import UIKit
import WidgetKit
import MyOpenScaleCore

/// One finalized weigh-in as shown in the UI, with its attribution + sink status.
struct LoggedReading: Identifiable, Equatable, Codable {
    var id = UUID()
    var capturedAt: Date
    var weightKg: Double
    var impedanceOhms: Int
    var resolution: String
    var composition: BodyComposition?
    var healthKitStatus: SinkStatus
    var note: String?
    /// Held weigh-in awaiting a "Was this you?" decision (ambiguous attribution).
    var needsConfirmation: Bool = false

    enum SinkStatus: Equatable, Codable {
        case skipped(String)
        case pending
        case written
        case failed(String)

        var label: String {
            switch self {
            case .skipped(let why): return String(localized: "Skipped (\(why))")
            case .pending: return String(localized: "Saving to Health…")
            case .written: return String(localized: "Saved to Apple Health")
            case .failed(let why): return String(localized: "Sync failed: \(why)")
            }
        }
    }
}

/// Lifecycle of a weigh-in as the UI experiences it. Derived from the raw frame
/// stream (the finalizer only enters `.measuring` after stabilization, so it
/// can't represent the step-on ramp — see plan).
enum MeasurementPhase: Equatable {
    case idle
    case waiting                            // armed by the user, no adverts yet — "step on the scale"
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
    /// Set when something outside the UI (Control Center, Siri, Shortcuts) asks
    /// for a new measurement; `RootTabView` opens the Add Measurement sheet and
    /// clears it.
    @Published var addMeasurementRequested = false
    /// Newest body-fat / lean / BMI value in Apple Health from any source (this
    /// app, another scale's app, a manual Health entry).
    @Published private(set) var latestMetrics: [HealthKitSink.MetricKind: HealthKitSink.MetricSample] = [:]
    private var healthReloadTask: Task<Void, Never>?
    @Published private(set) var lastSyncError: String?
    /// Live scale detected during onboarding pairing: which peripheral + its
    /// current weight. Nil until a real weigh-in frame arrives while scanning.
    @Published private(set) var scaleCandidate: ScaleCandidate?

    /// A scale seen live during onboarding, ready to be paired.
    struct ScaleCandidate: Equatable {
        let peripheralID: UUID
        let weightKg: Double
        let lastSeen: Date
    }

    private let scanner: BLEScanner
    private let healthKit = HealthKitSink()
    private let notifications = NotificationManager()

    /// The remembered scale (peripheral.identifier). When set, only readings from
    /// this peripheral are accepted; others are ignored entirely.
    @Published private(set) var pairedScaleID: UUID?
    /// Learned weight+impedance signatures: who is the owner vs. known others.
    /// Drives "is this me?" attribution (replaces weight-range matching).
    private var attribution = AttributionModel()
    /// True while the onboarding scale step is scanning, so `appendFrame` will
    /// surface a `scaleCandidate`.
    private var pairingScanActive = false
    /// True when the user explicitly tapped "Start new measurement". Keeps the
    /// overlay armed (returning to `.waiting`, not `.idle`) if frames pause, so a
    /// deliberate weigh-in isn't dismissed before the user steps on.
    private var manualMeasurementActive = false
    /// True after a weigh-in finalizes while the user is presumably still on the
    /// scale. Suppresses the live overlay re-arming until they step off, so one
    /// continuous stand produces exactly one measurement. Cleared by a
    /// weight-removed frame.
    private var awaitingStepOff = false

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
        self.pairedScaleID = PairedScaleStore.load()?.peripheralID
        self.attribution = AttributionStore.load()
        self.readings = Array(ReadingsStore.load().prefix(maxReadings))
        self.scanner = BLEScanner()
        if !HealthKitSink.isAvailable { self.healthAuth = .unavailable }

        notifications.configure()
        notifications.onConfirm = { [weak self] id in
            Task { @MainActor in self?.confirmReading(id) }
        }
        notifications.onReject = { [weak self] id in
            Task { @MainActor in self?.rejectReading(id) }
        }

        scanner.onStatusChange = { [weak self] status in
            Task { @MainActor in self?.bleStatus = status }
        }
        scanner.onFrame = { [weak self] frame in
            Task { @MainActor in self?.appendFrame(frame) }
        }
        scanner.onReading = { [weak self] reading, peripheralID in
            Task { @MainActor in self?.handle(reading, from: peripheralID) }
        }
    }

    // MARK: - Derived view state

    /// Most recent reading attributed to the owner (ignores other people's and
    /// not-yet-confirmed weigh-ins), so the dashboard only ever shows your data.
    var lastOwnReading: LoggedReading? {
        readings.first { $0.resolution == "You" && !$0.needsConfirmation }
    }

    var currentWeightKg: Double? {
        weightHistory.last?.weightKg ?? lastOwnReading?.weightKg
    }

    var trendDeltaKg: Double? {
        WeightHistory.trendDeltaKg(weightHistory)
    }

    var latestComposition: BodyComposition? {
        lastOwnReading?.composition
    }

    /// Dashboard card value: the newest Apple Health value, falling back to the
    /// last scale reading (e.g. before Health access is granted). NaN = none.
    func latestValue(_ kind: HealthKitSink.MetricKind) -> Double? {
        if let v = latestMetrics[kind]?.value { return v }
        guard let c = latestComposition else { return nil }
        switch kind {
        case .bodyFat: return c.bodyFatPercent
        case .lean: return c.leanMassKg
        case .bmi: return c.bmi
        }
    }

    // MARK: - Lifecycle

    func requestHealthAuthorization() {
        healthKit.requestAuthorization { [weak self] state in
            self?.healthAuth = state
            if state == .requested { self?.loadWeightHistory() }
        }
    }

    /// Ask for notification permission (so background weigh-ins can alert). Called
    /// once the dashboard is showing, i.e. after onboarding.
    func requestNotificationAuthorization() {
        notifications.requestAuthorization()
    }

    // MARK: - Onboarding

    /// Request Health authorization, then (if granted) read the user's basic
    /// details to pre-fill the profile. Always calls `completion` so the flow
    /// proceeds even when Health is denied/unavailable — the user just confirms
    /// defaults on the next step.
    func startOnboardingHealthPrefill(_ completion: @escaping () -> Void) {
        healthKit.requestAuthorization { [weak self] state in
            guard let self else { completion(); return }
            self.healthAuth = state
            guard state == .requested else { completion(); return }
            self.loadWeightHistory()
            self.healthKit.readUserCharacteristics { [weak self] prefill in
                self?.applyHealthPrefill(prefill)
                completion()
            }
        }
    }

    private func applyHealthPrefill(_ prefill: HealthKitSink.HealthPrefill) {
        saveProfile(profile.applying(prefill: prefill))
    }

    var hasPairedScale: Bool { pairedScaleID != nil }

    /// Begin scanning for a scale to pair (onboarding, or the Add Measurement
    /// sheet's pairing mode).
    func beginPairingScan() {
        pairingScanActive = true
        scaleCandidate = nil
        scanner.start()
    }

    /// Stop surfacing scale candidates once the pairing step is done.
    func endPairingScan() {
        pairingScanActive = false
        scaleCandidate = nil
    }

    /// Remember this peripheral as the user's scale. From now on only readings
    /// from it are accepted.
    func pairScale(_ id: UUID) {
        let scale = PairedScale(peripheralID: id,
                                pairedAt: Date(),
                                lastSeenWeightKg: scaleCandidate?.weightKg)
        PairedScaleStore.save(scale)
        pairedScaleID = id
    }

    /// Forget the paired scale (developer / re-pair).
    func unpairScale() {
        PairedScaleStore.clear()
        pairedScaleID = nil
    }

    /// Read a body metric's history from Apple Health (for the metric detail chart).
    func readMetricHistory(_ kind: HealthKitSink.MetricKind,
                           completion: @escaping ([HealthKitSink.MetricSample]) -> Void) {
        healthKit.readQuantityHistory(kind, completion: completion)
    }

    /// Refresh weight history from Apple Health. Keeps the last good data on a
    /// transient failure; empty results are "no data", not an error.
    func loadWeightHistory() {
        #if DEBUG
        // `-demoWeightHistory YES` on launch: synthetic ±0.5 kg daily noise on a
        // slow downward drift, to eyeball the chart in the simulator (no Health data).
        if UserDefaults.standard.bool(forKey: "demoWeightHistory") {
            var rng = SystemRandomNumberGenerator()
            weightHistory = (0..<200).reversed().compactMap { day -> WeightSample? in
                guard day % 9 != 4 else { return nil }   // skip a few days
                let kg = 82 - Double(200 - day) * 0.008 + Double.random(in: -0.5...0.5, using: &rng)
                return WeightSample(id: UUID(), date: Date().addingTimeInterval(-Double(day) * 86_400 - 3600),
                                    weightKg: (kg * 10).rounded() / 10)
            }
            return
        }
        #endif
        healthKit.observeBodyChanges { [weak self] in self?.scheduleHealthReload() }
        loadLatestMetrics()
        healthKit.readWeightHistory { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let samples):
                self.weightHistory = samples
                self.lastSyncError = nil
                self.updateWidgetSnapshot()
            case .failure(let error):
                self.lastSyncError = error.localizedDescription
            }
        }
    }

    /// Publish the latest weight to the widget snapshot (read by the Home/Lock
    /// Screen widget) and ask any installed widgets to refresh.
    private func updateWidgetSnapshot() {
        guard let weightKg = currentWeightKg else { return }
        // Last ~40 points (90 days) for the large widget's chart.
        let recent = WeightHistory.filter(weightHistory, lastDays: 90, now: Date()).suffix(40)
        let points = recent.map { WidgetPoint(date: $0.date, weightKg: $0.weightKg) }
        WidgetSnapshotStore.write(WidgetSnapshot(weightKg: weightKg,
                                                 date: weightHistory.last?.date ?? Date(),
                                                 trendDeltaKg: trendDeltaKg,
                                                 goalKg: profile.goalWeightKg,
                                                 points: Array(points)))
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Called by the view when the app returns to the foreground.
    func onForeground() {
        loadWeightHistory()
    }

    func saveProfile(_ updated: StoredProfile) {
        profile = updated
        ProfileStore.save(updated)
    }

    /// Persist a profile the user explicitly confirmed (onboarding "Continue" or
    /// the profile editor's "Save") and mirror the height to Apple Health, so a
    /// standalone Apple Watch weigh-in can read it back and compute body
    /// composition without the phone. Not used for the silent Health *prefill*
    /// path (which must not write a default height back).
    func saveConfirmedProfile(_ updated: StoredProfile) {
        saveProfile(updated)
        healthKit.writeHeight(cm: updated.heightCm)
    }

    // MARK: - Attribution ("is this me?")

    private func attributionLabel(_ a: Attribution) -> String {
        switch a {
        case .me: return "You"
        case .other: return "Another person — skipped"
        case .uncertain: return "Needs review"
        }
    }

    private func learnMe(weightKg: Double, impedanceOhms: Int) {
        attribution = AttributionClassifier.learnMe(attribution, weightKg: weightKg, impedanceOhms: impedanceOhms)
        AttributionStore.save(attribution)
    }

    private func learnOther(weightKg: Double, impedanceOhms: Int) {
        attribution = AttributionClassifier.learnOther(attribution, weightKg: weightKg, impedanceOhms: impedanceOhms)
        AttributionStore.save(attribution)
    }

    /// Held weigh-ins awaiting a "Was this you?" decision (shown on the dashboard).
    var pendingConfirmations: [LoggedReading] {
        readings.filter { $0.needsConfirmation }
    }

    /// User confirms a held reading is theirs: learn it, write it to Health.
    func confirmReading(_ id: UUID) {
        guard let idx = readings.firstIndex(where: { $0.id == id }), readings[idx].needsConfirmation else { return }
        readings[idx].needsConfirmation = false
        readings[idx].resolution = "You"
        readings[idx].healthKitStatus = .pending
        let reading = readings[idx]
        persistReadings()
        learnMe(weightKg: reading.weightKg, impedanceOhms: reading.impedanceOhms)
        writeReadingToHealth(reading)
    }

    /// User rejects a held reading: learn it as "another person" so similar
    /// future weigh-ins are skipped silently, and discard it.
    func rejectReading(_ id: UUID) {
        guard let idx = readings.firstIndex(where: { $0.id == id }) else { return }
        let reading = readings[idx]
        learnOther(weightKg: reading.weightKg, impedanceOhms: reading.impedanceOhms)
        readings.remove(at: idx)
        persistReadings()
    }

    /// Forget all learned signatures (developer / re-train).
    func resetAttribution() {
        attribution = AttributionModel()
        AttributionStore.clear()
    }

    /// Delete a stored weigh-in from Apple Health (the samples this app wrote at
    /// that time) and from the in-app history. Refreshes the chart on success.
    /// Several observer callbacks arrive per change (one per metric type, and
    /// for our own writes too); coalesce them into one reload.
    private func scheduleHealthReload() {
        healthReloadTask?.cancel()
        healthReloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.loadWeightHistory()
        }
    }

    private func loadLatestMetrics() {
        for kind in HealthKitSink.MetricKind.allCases {
            healthKit.readLatest(kind) { [weak self] sample in
                self?.latestMetrics[kind] = sample
            }
        }
    }

    /// Save a weigh-in typed in by the user (no scale available, or catching up
    /// on a missed day). BMI comes from the profile height; lean mass only when
    /// a body-fat % was entered. Completion on the main queue.
    func addManualMeasurement(weightKg: Double, bodyFatPercent: Double?, date: Date,
                              completion: @escaping (Result<Void, Error>) -> Void) {
        let composition = BodyCompositionCalculator.manual(weightKg: weightKg,
                                                           bodyFatPercent: bodyFatPercent,
                                                           heightCm: profile.heightCm)
        // First Health use (user skipped "Connect" in onboarding): ask now.
        guard healthAuth != .notRequested else {
            healthKit.requestAuthorization { [weak self] state in
                self?.healthAuth = state
                self?.addManualMeasurement(weightKg: weightKg, bodyFatPercent: bodyFatPercent,
                                           date: date, completion: completion)
            }
            return
        }
        healthKit.writeManual(composition: composition, at: date) { [weak self] result in
            switch result {
            case .success:
                self?.lastSyncError = nil
                self?.loadWeightHistory()
            case .failure(let error):
                self?.lastSyncError = error.localizedDescription
            }
            completion(result)
        }
    }

    /// Correct the weight (and/or time) of a weigh-in this app saved. Entries
    /// from other apps can't be changed — HealthKit only lets us delete our own.
    func editMeasurement(_ sample: WeightSample, weightKg: Double, date: Date,
                         completion: @escaping (Result<Void, Error>) -> Void) {
        guard sample.isFromThisApp else { return }
        healthKit.replaceMeasurement(at: sample.date, newWeightKg: weightKg, newDate: date,
                                     heightCm: profile.heightCm) { [weak self] result in
            guard let self else { return }
            if case .success = result {
                // The local log's copy (if any) now disagrees with Health; drop it
                // like a delete does — Health is the source of truth.
                self.readings.removeAll { abs($0.capturedAt.timeIntervalSince(sample.date)) < 1 }
                self.persistReadings()
                self.loadWeightHistory()
            }
            completion(result)
        }
    }

    func deleteMeasurement(_ sample: WeightSample) {
        guard sample.isFromThisApp else { return }
        weightHistory.removeAll { $0.id == sample.id }
        readings.removeAll { abs($0.capturedAt.timeIntervalSince(sample.date)) < 1 }
        persistReadings()
        healthKit.deleteMeasurement(at: sample.date) { [weak self] result in
            switch result {
            case .success:
                self?.loadWeightHistory()
            case .failure(let error):
                self?.lastSyncError = error.localizedDescription
            }
        }
    }

    /// Arm a new weigh-in from the UI: show the overlay in its `.waiting` state
    /// ("step on your scale") and make sure we're scanning. Incoming adverts then
    /// drive it to `.measuring`/`.finalizing` via `updatePhase`.
    func startMeasurement() {
        dismissTask?.cancel()
        idleTask?.cancel()
        simulateTask?.cancel()
        liveStartedAt = nil
        manualMeasurementActive = true
        awaitingStepOff = false   // user explicitly wants a fresh weigh-in
        measurementPhase = .waiting
        scanner.start()   // idempotent; ensures the scan is running
    }

    /// Show a non-persisted **sample** weigh-in so the flow can be evaluated
    /// without the physical scale (e.g. App Review, or a curious first-run user).
    /// Writes nothing to Apple Health, learns no signature, saves no reading.
    func showSampleReading() {
        dismissTask?.cancel(); idleTask?.cancel(); simulateTask?.cancel()
        let weightKg = 80.0, impedance = 500
        let composition = BodyCompositionCalculator.compute(
            weightKg: weightKg, impedanceOhms: Double(impedance),
            profile: BodyProfile(from: profile.coreProfile, at: Date()))
        let demo = LoggedReading(capturedAt: Date(), weightKg: weightKg, impedanceOhms: impedance,
                                 resolution: "Sample", composition: composition,
                                 healthKitStatus: .skipped(String(localized: "Sample — not saved")),
                                 note: String(localized: "Example reading. Nothing was saved to Apple Health."))
        liveStartedAt = Date()
        simulateTask = Task { [weak self] in
            guard let self else { return }
            for i in 1...10 {
                if Task.isCancelled { return }
                self.measurementPhase = .measuring(liveWeightKg: max(self.minLiveWeightKg, weightKg * Double(i) / 10))
                try? await Task.sleep(nanoseconds: 90_000_000)
            }
            if Task.isCancelled { return }
            self.measurementPhase = .finalizing(liveWeightKg: weightKg)
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            self.liveStartedAt = nil
            self.measurementPhase = .result(demo)   // show result WITHOUT persist/write/learn
            self.armDismiss(for: demo.id)
        }
    }

    /// Manually dismiss the weigh-in overlay.
    func dismissOverlay() {
        dismissTask?.cancel()
        idleTask?.cancel()
        simulateTask?.cancel()
        liveStartedAt = nil
        manualMeasurementActive = false
        awaitingStepOff = false
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
                                capturedAt: Date(), deviceTimestamp: nil),
               from: pairedScaleID)
    }

    /// Inject a synthetic weigh-in so the full resolve→compute→HealthKit path
    /// (and the live overlay animation) can be exercised without the scale.
    func simulateWeighIn(weightKg: Double = 80.0, impedanceOhms: Int = 500, animated: Bool = true) {
        guard animated else {
            handle(FinalizedReading(weightKg: weightKg, impedanceOhms: impedanceOhms,
                                    capturedAt: Date(), deviceTimestamp: nil),
                   from: pairedScaleID)
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
                                         capturedAt: Date(), deviceTimestamp: nil),
                        from: self.pairedScaleID)
        }
    }

    // MARK: - Live frame → phase

    private func appendFrame(_ frame: ObservedFrame) {
        recentFrames.insert(frame, at: 0)
        if recentFrames.count > maxFrames { recentFrames.removeLast(recentFrames.count - maxFrames) }
        if pairingScanActive,
           !frame.parsed.isWeightRemoved,
           frame.parsed.weightKg >= minLiveWeightKg {
            scaleCandidate = ScaleCandidate(peripheralID: frame.peripheralID,
                                            weightKg: frame.parsed.weightKg,
                                            lastSeen: frame.receivedAt)
        }
        // Once a scale is paired, only it drives the live overlay — otherwise a
        // neighbour's 0x181B scale would pop the overlay for a reading handle()
        // will drop anyway. Before pairing, any scale drives it (as today).
        if let pairedScaleID, frame.peripheralID != pairedScaleID { return }
        updatePhase(from: frame.parsed)
    }

    private func updatePhase(from adv: ParsedAdvertisement) {
        // Step-off clears the post-reading lock so the next weigh-in can show.
        if adv.isWeightRemoved { awaitingStepOff = false; return }
        // Never disturb a result that's being shown / auto-dismissed (the stable
        // burst keeps arriving during the finalizer's cooldown).
        if case .result = measurementPhase { return }
        // After a completed weigh-in, ignore the continuing "still standing"
        // frames until the user steps off — otherwise the overlay would re-arm
        // and look like a new measurement is starting.
        if awaitingStepOff { return }
        guard adv.weightKg >= minLiveWeightKg else { return }

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
                // A user-armed measurement returns to "step on the scale" rather
                // than closing, so a brief step-off doesn't abandon the weigh-in.
                self.measurementPhase = self.manualMeasurementActive ? .waiting : .idle
            default: break
            }
        }
    }

    // MARK: - Pipeline

    private func handle(_ reading: FinalizedReading, from peripheralID: UUID?) {
        // Once a scale is remembered, ignore weigh-ins from any other 0x181B
        // device entirely (a neighbour's scale must never reach Apple Health).
        if let pairedScaleID, let peripheralID, peripheralID != pairedScaleID {
            return
        }

        // Decide whose body this is from the (weight, impedance) signature.
        let decision = AttributionClassifier.decide(weightKg: reading.weightKg,
                                                    impedanceOhms: reading.impedanceOhms,
                                                    model: attribution)

        // Compute composition (full if impedance present, else partial) using the
        // owner's body profile — only used if the reading is kept/confirmed.
        let bodyProfile = BodyProfile(from: profile.coreProfile, at: reading.capturedAt)
        let composition: BodyComposition
        var note: String?
        if (1...3000).contains(reading.impedanceOhms) {
            composition = BodyCompositionCalculator.compute(
                weightKg: reading.weightKg,
                impedanceOhms: Double(reading.impedanceOhms),
                profile: bodyProfile)
        } else {
            composition = BodyCompositionCalculator.partial(
                weightKg: reading.weightKg, profile: bodyProfile)
            note = String(localized: "No impedance — weight + BMI only.")
        }

        var logged = LoggedReading(
            capturedAt: reading.capturedAt,
            weightKg: reading.weightKg,
            impedanceOhms: reading.impedanceOhms,
            resolution: attributionLabel(decision),
            composition: composition,
            healthKitStatus: .pending,
            note: note
        )

        let inBackground = UIApplication.shared.applicationState != .active

        switch decision {
        case .me:
            learnMe(weightKg: reading.weightKg, impedanceOhms: reading.impedanceOhms)
            logged.healthKitStatus = .pending
            finish(with: logged)
            writeReadingToHealth(logged)
            if inBackground { notifications.notifySaved(weightKg: reading.weightKg) }
        case .other:
            logged.healthKitStatus = .skipped(String(localized: "not you"))
            finish(with: logged)
        case .uncertain:
            logged.needsConfirmation = true
            logged.healthKitStatus = .skipped(String(localized: "needs review"))
            finish(with: logged)
            if inBackground {
                notifications.notifyNeedsReview(readingID: logged.id, weightKg: reading.weightKg)
            }
        }
    }

    /// Write a kept reading's four metrics to Apple Health and track the result.
    private func writeReadingToHealth(_ logged: LoggedReading) {
        guard let composition = logged.composition else { return }
        let readingID = logged.id
        healthKit.write(composition: composition,
                        capturedAt: logged.capturedAt,
                        impedanceOhms: logged.impedanceOhms,
                        profile: profile.coreProfile,
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
        manualMeasurementActive = false   // the weigh-in completed
        awaitingStepOff = true            // ignore "still standing" frames until step-off
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
        persistReadings()
    }

    private func updateStatus(_ id: UUID, _ status: LoggedReading.SinkStatus) {
        guard let idx = readings.firstIndex(where: { $0.id == id }) else { return }
        readings[idx].healthKitStatus = status
        persistReadings()
        // Keep the overlay's sync badge in sync if it's still showing this reading.
        if case .result(let r) = measurementPhase, r.id == id {
            measurementPhase = .result(readings[idx])
        }
    }

    private func persistReadings() {
        ReadingsStore.save(readings)
    }
}
