import Foundation
import Combine
import HealthKit
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
    @Published var bleStatus: BLEStatus = .notInUse
    @Published var healthAuth: HealthKitSink.AuthState = .notRequested
    @Published var profile: StoredProfile
    @Published private(set) var recentFrames: [ObservedFrame] = []
    @Published private(set) var readings: [LoggedReading] = []
    @Published private(set) var measurementPhase: MeasurementPhase = .idle
    /// When the current in-progress weigh-in began (drives the overlay's
    /// progress + the "save current weight" escape hatch). Nil when idle.
    @Published private(set) var liveStartedAt: Date?
    /// Mochi's reaction to the weigh-in on the overlay's result. Nil when Mochi is off.
    @Published private(set) var weighInPresentation: MochiPresentation?
    @Published private(set) var weightHistory: [WeightSample] = []
    /// Set when something outside the UI (Control Center, Siri, Shortcuts) asks
    /// for a new measurement; `RootTabView` opens the Add Measurement sheet and
    /// clears it.
    @Published var addMeasurementRequested = false
    /// Set with `addMeasurementRequested` when the Weigh in tab should open
    /// straight into pairing (Settings → Pair); the tab consumes it on entry.
    var pairingRequested = false

    /// Open the Weigh in tab in pairing mode.
    func requestPairing() {
        pairingRequested = true
        addMeasurementRequested = true
    }
    /// Activity context for the History feed (from Apple Health, any app).
    @Published private(set) var workouts: [HealthKitSink.WorkoutEntry] = []
    @Published private(set) var dailyTotals: [Date: HealthKitSink.DailyTotals] = [:]
    private var activityAuthRequested = false
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

    /// Mochi companion: reactions, greetings and settings.
    let mochi: MochiCoordinator
    private var mochiSettingsObserver: AnyCancellable?

    /// Created only once a scale is paired (at launch) or being paired (the user
    /// tapped "Pair my scale"), so people without a scale never see the
    /// Bluetooth permission prompt. Nil means Bluetooth is not in use.
    private var scanner: BLEScanner?
    private let healthKit = HealthKitSink()
    private let notifications = NotificationManager()
    /// Capture time of the newest weigh-in attributed to the owner this session.
    private var lastOwnWeighInAt: Date?

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
        self.mochi = MochiCoordinator()
        if !HealthKitSink.isAvailable { self.healthAuth = .unavailable }

        mochi.historyProvider = { [weak self] in self?.weightHistory ?? [] }
        mochi.lastWeighInProvider = { [weak self] in self?.lastOwnWeighInAt }
        mochi.profileProvider = { [weak self] in self?.profile ?? ProfileStore.load() }
        mochi.activityProvider = { [weak self] now in self?.mochiActivity(now: now) ?? .none }

        // Keep the watch's goal / name / Mochi switch in step with the phone.
        WatchSync.shared.activate()
        mochiSettingsObserver = mochi.$settings
            .removeDuplicates { $0.enabled == $1.enabled }
            .sink { [weak self] settings in self?.pushWatchSync(mochiEnabled: settings.enabled) }

        notifications.configure()
        notifications.onConfirm = { [weak self] id in
            Task { @MainActor in self?.confirmReading(id) }
        }
        notifications.onReject = { [weak self] id in
            Task { @MainActor in self?.rejectReading(id) }
        }
        notifications.onReminderTap = { [weak self] in
            Task { @MainActor in self?.addMeasurementRequested = true }
        }

        // A paired scale scans from launch (passive weigh-ins, and iOS restoring our
        // central manager after a background relaunch needs it created right away).
        if pairedScaleID != nil { startBluetooth() }
        // Home content waits for the app to be active (see `appIsActive`). A cold launch
        // never changes scenePhase, so catch the moment it becomes active here.
        becameActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshMochiHomeOnActivation() }
        }
    }

    private var becameActiveObserver: NSObjectProtocol?

    // MARK: - Bluetooth

    /// Create the scanner on first use and start scanning. Its central manager
    /// asks for Bluetooth permission the first time; scanning then begins once
    /// Bluetooth is on. Idempotent.
    private func startBluetooth() {
        if let scanner { scanner.start(); return }
        let made = BLEScanner()
        made.onStatusChange = { [weak self, weak made] status in
            Task { @MainActor in
                // Ignore a scanner that was already torn down.
                guard let self, let made, self.scanner === made else { return }
                self.bleStatus = status
            }
        }
        made.onFrame = { [weak self] frame in
            Task { @MainActor in self?.appendFrame(frame) }
        }
        made.onReading = { [weak self] reading, peripheralID in
            Task { @MainActor in self?.handle(reading, from: peripheralID) }
        }
        scanner = made
        bleStatus = made.status
    }

    /// Stop scanning and release the central manager: Bluetooth is "not in use"
    /// again (no scale paired and none being paired).
    private func stopBluetooth() {
        guard let scanner else { return }
        scanner.onStatusChange = nil
        scanner.onFrame = nil
        scanner.onReading = nil
        scanner.stop()
        self.scanner = nil
        bleStatus = .notInUse
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

    // MARK: - Body composition (all estimates from impedance)

    /// One point of a body metric's timeline.
    struct MetricPoint: Identifiable, Equatable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    /// Every weigh-in with an impedance, turned into the full set of estimates
    /// (with the user's age at that date). Ascending by date.
    var bodyMetricSeries: [(date: Date, values: BodyMetricValues)] {
        weightHistory
            .filter { $0.impedanceOhms != nil }
            .sorted { $0.date < $1.date }
            .map { s in
                (s.date, BodyMetricsCalculator.compute(
                    weightKg: s.weightKg, impedanceOhms: Double(s.impedanceOhms ?? 0),
                    profile: BodyProfile(from: profile.coreProfile, at: s.date)))
            }
    }

    /// The user's age today (for reference ranges).
    var ageYears: Double {
        BodyProfile(from: profile.coreProfile, at: Date()).ageYears
    }

    /// Timeline of one metric. Impedance-based estimates first; body fat and
    /// lean mass fall back to whatever Apple Health has (manual entries,
    /// other apps) when there are no scale readings.
    func metricHistory(_ metric: BodyMetric) -> [MetricPoint] {
        bodyMetricSeries.map { MetricPoint(date: $0.date, value: $0.values.value(metric)) }
    }

    /// Latest value of a metric and when it was measured; nil when there is
    /// nothing to show (then the Overview hides the tile).
    func latestMetric(_ metric: BodyMetric) -> MetricPoint? {
        let scale = bodyMetricSeries.last.map { MetricPoint(date: $0.date, value: $0.values.value(metric)) }
        // Body fat / lean mass may also come from Health (manual entry, other
        // apps) — whichever is newer wins.
        let kind: HealthKitSink.MetricKind? = metric == .bodyFat ? .bodyFat : (metric == .lean ? .lean : nil)
        let health = kind.flatMap { latestMetrics[$0] }
            .flatMap { $0.value.isFinite ? MetricPoint(date: $0.date, value: $0.value) : nil }
        switch (scale, health) {
        case let (s?, h?): return h.date > s.date.addingTimeInterval(1) ? h : s
        case let (s?, nil): return s
        case let (nil, h?): return h
        default: return nil
        }
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

    /// Ask for notification permission (so background weigh-ins can alert). Called from
    /// onboarding's Mochi reminders step and once the dashboard is showing; the system
    /// only prompts the first time.
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

    /// Begin scanning for a scale to pair (onboarding's "Pair my scale", or the
    /// Weigh in tab's pairing mode). Without a paired scale this is the first
    /// time Bluetooth is used, so it brings up the permission prompt.
    func beginPairingScan() {
        pairingScanActive = true
        scaleCandidate = nil
        startBluetooth()
    }

    /// Stop surfacing scale candidates once the pairing step is done. If no
    /// scale got paired, Bluetooth goes back to not in use.
    func endPairingScan() {
        pairingScanActive = false
        scaleCandidate = nil
        if !hasPairedScale { stopBluetooth() }
    }

    /// Remember this peripheral as the user's scale. From now on only readings
    /// from it are accepted.
    func pairScale(_ id: UUID) {
        let scale = PairedScale(peripheralID: id,
                                pairedAt: Date(),
                                lastSeenWeightKg: scaleCandidate?.weightKg)
        PairedScaleStore.save(scale)
        pairedScaleID = id
        pushWatchSync()
    }

    /// Forget the paired scale (developer / re-pair) and stop scanning.
    func unpairScale() {
        PairedScaleStore.clear()
        pairedScaleID = nil
        pushWatchSync()
        if !pairingScanActive { stopBluetooth() }
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
                                    weightKg: (kg * 10).rounded() / 10,
                                    impedanceOhms: 490 + Int.random(in: -15...15, using: &rng) + (200 - day) / 20)
            }
            rescheduleMochiReminders()
            refreshMochiHomeAfterLoad()
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
                // Also covers a just-written weigh-in (the write reloads history) and
                // Watch weigh-ins that arrive through Health.
                self.rescheduleMochiReminders()
                self.updateWidgetSnapshot()
                self.refreshMochiHomeAfterLoad()
            case .failure(let error):
                self.lastSyncError = error.localizedDescription
                self.refreshMochiHomeAfterLoad()
            }
        }
    }

    /// Whether the dashboard is on screen (set by the view); Mochi's home line only updates then.
    var dashboardVisible = false

    /// Home content is only consumed or generated while the app is in the foreground: a
    /// background weigh-in's stash must survive until the user actually opens the app
    /// (`dashboardVisible` stays true while backgrounded, as `onDisappear` doesn't fire).
    private var appIsActive: Bool { UIApplication.shared.applicationState == .active }

    private var mochiHomeCanUpdate: Bool {
        mochi.settings.enabled && measurementPhase == .idle && appIsActive
    }

    /// Dashboard appear / foreground: a stashed reaction, or a new greeting if the old one is stale.
    func refreshMochiHomeIfStale() {
        guard mochiHomeCanUpdate else { return }
        refreshMochiHomeIfStaleNow()
    }

    private func refreshMochiHomeIfStaleNow() {
        guard mochi.settings.enabled, measurementPhase == .idle else { return }
        mochi.refreshHomeIfStale(history: weightHistory, profile: profile)
    }

    /// The app became active: show a waiting stash, or a first / stale greeting.
    private func refreshMochiHomeOnActivation() {
        guard dashboardVisible, mochiHomeCanUpdate else { return }
        if weightHistory.isEmpty && mochi.homePresentation == nil {
            // No history yet: show a waiting stash; the load under way gives the first greeting.
            mochi.showPendingHomeReaction()
        } else {
            mochi.refreshHomeIfStale(history: weightHistory, profile: profile)
        }
    }

    /// A history load never regenerates the greeting: it may show a stashed reaction, and gives
    /// the very first greeting (so it sees the loaded history).
    private func refreshMochiHomeAfterLoad() {
        guard mochiHomeCanUpdate, dashboardVisible else { return }
        if !mochi.showPendingHomeReaction(), mochi.homePresentation == nil {
            mochi.refreshHome(history: weightHistory, profile: profile)
        }
    }

    /// A new greeting on request (tap, or after a weigh-in result is dismissed).
    func refreshMochiHome() {
        guard mochi.settings.enabled, appIsActive else { return }
        mochi.refreshHome(history: weightHistory, profile: profile)
    }

    /// Goal page appear / foreground: a new goal line only if the old one is stale.
    func refreshMochiGoalIfStale(status: MochiGoalStatus) {
        guard mochi.settings.enabled else { return }
        mochi.refreshGoalIfStale(history: weightHistory, profile: profile, status: status)
    }

    /// A new goal line on request (tap) or when the goal or its state changed.
    func refreshMochiGoal(status: MochiGoalStatus) {
        guard mochi.settings.enabled else { return }
        mochi.refreshGoal(history: weightHistory, profile: profile, status: status)
    }

    /// A weigh-in result was on screen in the foreground: its reaction was seen, so a stash of
    /// the same reaction (made because the app was inactive at that moment) must not show again.
    private func noteWeighInResultSeen() {
        guard appIsActive, let shown = weighInPresentation,
              MochiStateStore.pendingHomeReaction == shown else { return }
        MochiStateStore.pendingHomeReaction = nil
    }

    /// A goal with a target but no start weight (set before any weight was known) starts from
    /// the owner's previous known weight, else this first reading, so milestones and % progress
    /// can count. Mochi only: with Mochi off the profile stays as the user saved it.
    private func fillGoalStartIfNeeded(for reading: LoggedReading) {
        guard mochi.settings.enabled, profile.goalWeightKg != nil, profile.goalStartKg == nil else { return }
        let previous = weightHistory.filter { $0.date < reading.capturedAt.addingTimeInterval(-60) }
            .max { $0.date < $1.date }?.weightKg
        profile.goalStartKg = previous ?? reading.weightKg
        if profile.goalSetAt == nil { profile.goalSetAt = reading.capturedAt }
        ProfileStore.save(profile)
    }

    private func noteOwnWeighIn(at date: Date) {
        lastOwnWeighInAt = max(lastOwnWeighInAt ?? date, date)
        rescheduleMochiReminders()
    }

    /// Reschedule Mochi's reminders. The newest own weigh-in counts even if it never reached
    /// the Health history (failed write or read), so no reminder fires on a day already weighed in.
    private func rescheduleMochiReminders() {
        mochi.rescheduleReminders(history: weightHistory, profile: profile, lastWeighInOverride: lastOwnWeighInAt)
    }

    /// Publish the latest weight to the widget snapshot (read by the Home/Lock
    /// Screen widget) and ask any installed widgets to refresh.
    func updateWidgetSnapshot() {
        guard let weightKg = currentWeightKg else { return }
        // Same picture as the Overview chart: daily dots + centered trend over
        // 30 days, on the app's calm axis.
        let now = Date()
        let daily = WeightHistory.filter(WeightHistory.bucketed(weightHistory), lastDays: 30, now: now)
        let trend = WeightHistory.filter(
            WeightHistory.trend(WeightHistory.bucketed(weightHistory), halfLifeDays: 3, centered: true),
            lastDays: 30, now: now)
        let axis = WeightHistory.chartAxis(for: daily + trend)
        let progress: Double? = profile.goalWeightKg.flatMap { goal in
            let start = profile.goalStartKg ?? WeightHistory.filter(weightHistory, lastDays: 90, now: now).first?.weightKg
            return start.flatMap { WeightHistory.goalProgress(startKg: $0, currentKg: weightKg, goalKg: goal) }
        }
        WidgetSnapshotStore.write(WidgetSnapshot(
            weightKg: weightKg,
            date: weightHistory.max { $0.date < $1.date }?.date ?? now,
            trendDeltaKg: trendDeltaKg,
            goalKg: profile.goalWeightKg,
            points: daily.map { WidgetPoint(date: $0.date, weightKg: $0.weightKg) },
            trendPoints: trend.map { WidgetPoint(date: $0.date, weightKg: $0.weightKg) },
            monthTrendKg: WeightHistory.trendChangeKg(weightHistory, lastDays: 30, now: now),
            axisLowerKg: axis.domain.lowerBound,
            axisUpperKg: axis.domain.upperBound,
            goalProgress: progress,
            metrics: widgetMetrics(weightKg: weightKg, now: now),
            goalStatus: widgetGoalStatus(currentKg: weightKg, now: now)))
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Weight + the most telling body values with their 30-day change, for the
    /// Progress widget. Only values with data.
    private func widgetMetrics(weightKg: Double, now: Date) -> [WidgetMetric] {
        func signed(_ v: Double, digits: Int, unit: String) -> String {
            let n = abs(v).formatted(.number.precision(.fractionLength(digits)))
            let sign = abs(v) < 0.5 * pow(10, -Double(digits)) ? "±" : (v > 0 ? "+" : "−")
            return unit.isEmpty ? "\(sign)\(n)" : "\(sign)\(n) \(unit)"
        }
        /// Losing weight/fat is good unless the goal is to gain.
        let losing = (profile.goalWeightKg ?? weightKg - 1) < weightKg
        var result: [WidgetMetric] = []

        let monthChange = WeightHistory.trendChangeKg(weightHistory, lastDays: 30, now: now)
        result.append(WidgetMetric(
            id: "weight", title: String(localized: "Weight"), symbol: "scalemass.fill",
            value: weightKg.formatted(.number.precision(.fractionLength(1))), unit: "kg",
            change: monthChange.map { signed($0, digits: 1, unit: "kg") },
            changeIsGood: monthChange.flatMap { abs($0) < 0.05 ? nil : (($0 < 0) == losing) }))

        let wanted: [(BodyMetric, Bool)] = [(.bodyFat, false), (.muscle, true), (.water, true), (.visceralFat, false)]
        for (metric, upIsGood) in wanted {
            guard let latest = latestMetric(metric) else { continue }
            let history = metricHistory(metric)
            let cutoff = now.addingTimeInterval(-30 * 86_400)
            let then = history.filter { $0.date <= cutoff }.last ?? history.first
            let delta: Double? = then.flatMap { $0.date < latest.date ? latest.value - $0.value : nil }
            let digits = metric == .visceralFat ? 0 : 1
            result.append(WidgetMetric(
                id: metric.rawValue, title: metric.title, symbol: metric.systemImage,
                value: latest.value.formatted(.number.precision(.fractionLength(digits))), unit: metric.unit,
                change: delta.map { signed($0, digits: digits, unit: metric.unit) },
                changeIsGood: delta.flatMap { abs($0) < 0.05 ? nil : (($0 > 0) == upIsGood) }))
        }
        return result
    }

    /// "Im Plan" / "0,6 kg voraus" with a target date, otherwise the forecast
    /// month, otherwise nil.
    private func widgetGoalStatus(currentKg: Double, now: Date) -> String? {
        guard let goal = profile.goalWeightKg else { return nil }
        let trendNow = WeightHistory.trend(WeightHistory.bucketed(weightHistory)).last?.weightKg ?? currentKg
        if let target = profile.goalTargetDate {
            let start = profile.goalStartKg ?? currentKg
            let plan = GoalPlan(startKg: start, startDate: profile.goalSetAt ?? now, goalKg: goal, targetDate: target)
            switch PlanStatus(aheadKg: plan.aheadKg(trendKg: trendNow, at: now)) {
            case .onPlan: return String(localized: "On plan")
            case .ahead(let kg): return String(localized: "\(kg.formatted(1)) kg ahead")
            case .behind(let kg): return String(localized: "\(kg.formatted(1)) kg behind")
            }
        }
        guard let rate = WeightHistory.weeklyRateKg(weightHistory, lastDays: 30, now: now),
              let weeks = WeightHistory.weeksToGoal(currentKg: trendNow, goalKg: goal, weeklyRateKg: rate),
              weeks <= 104 else { return nil }
        let eta = now.addingTimeInterval(weeks * 7 * 86_400)
        return String(localized: "Goal around \(eta.formatted(.dateTime.month(.abbreviated).year()))")
    }

    /// Called by the view when the app returns to the foreground.
    func onForeground() {
        loadWeightHistory()
        // The scene just became active; don't depend on UIApplication's state having caught up.
        if dashboardVisible { refreshMochiHomeIfStaleNow() }
    }

    /// Send the watch what it can't read from Health (goal, name, Mochi switch).
    func pushWatchSync(mochiEnabled: Bool? = nil) {
        let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        WatchSync.shared.push(WatchSyncPayload(
            name: name.isEmpty ? nil : name,
            goalKg: profile.goalWeightKg,
            goalType: profile.goalWeightKg == nil ? nil : (profile.goalType ?? .lose).rawValue,
            goalStartKg: profile.goalStartKg,
            mochiEnabled: mochiEnabled ?? mochi.settings.enabled,
            hasPairedScale: hasPairedScale))
    }

    func saveProfile(_ updated: StoredProfile) {
        var updated = updated
        // A new or changed goal starts its progress from today's weight.
        if updated.goalType != profile.goalType || updated.goalWeightKg != profile.goalWeightKg {
            updated.goalStartKg = updated.goalWeightKg == nil ? nil : currentWeightKg
            updated.goalSetAt = updated.goalWeightKg == nil ? nil : Date()
            updated.goalMilestonesSeen = nil
            if updated.goalWeightKg == nil { updated.goalTargetDate = nil }
        }
        if updated.goalBodyFatPercent != profile.goalBodyFatPercent {
            updated.goalBodyFatStartPercent = updated.goalBodyFatPercent == nil ? nil : latestValue(.bodyFat).flatMap { $0.isFinite ? $0 : nil }
        }
        let goalChanged = updated.goalWeightKg != profile.goalWeightKg
        profile = updated
        ProfileStore.save(updated)
        pushWatchSync()
        // The widget shows the goal line and progress ring.
        if goalChanged { updateWidgetSnapshot() }
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
        noteOwnWeighIn(at: reading.capturedAt)
        if mochi.settings.enabled {
            // The reading is now the owner's: Mochi reacts on the home screen. History is
            // from before the reading (the engine appends it itself).
            // Only samples from before it: a reading confirmed days later must not count later ones.
            let history = weightHistory.filter { $0.date < reading.capturedAt.addingTimeInterval(-60) }
            fillGoalStartIfNeeded(for: reading)
            mochi.stash(mochi.presentationForWeighIn(reading, history: history, profile: profile))
        }
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
    // MARK: - Activity (History feed)

    /// How far back the History feed shows workouts / steps / calories.
    static let activityDays = 90

    /// Load workouts and daily totals. The first call asks Apple Health for the
    /// activity read types (only those not answered yet show a prompt).
    func loadActivity() {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "demoWeightHistory") { loadDemoActivity(); return }
        #endif
        let since = Date().addingTimeInterval(-Double(Self.activityDays) * 86_400)
        let load = { [weak self] in
            guard let self else { return }
            self.healthKit.readWorkouts(since: since) { [weak self] in
                self?.workouts = $0
                self?.greetNewActivity()
            }
            self.healthKit.readDailyTotals(since: since) { [weak self] in
                self?.dailyTotals = $0
                self?.greetNewActivity()
            }
        }
        guard !activityAuthRequested else { load(); return }
        activityAuthRequested = true
        healthKit.requestActivityAuthorization(load)
    }

    /// Recent workouts and steps for Mochi.
    func mochiActivity(now: Date) -> MochiActivityContext {
        let mapped = workouts.map { w in
            MochiWorkout(id: w.id.uuidString, start: w.start, end: w.end,
                         kind: Self.mochiKind(w.activityType), name: w.activityType.title)
        }
        return MochiActivityContext.make(workouts: mapped,
                                         stepsByDay: dailyTotals.compactMapValues(\.steps),
                                         now: now, calendar: .current)
    }

    private static func mochiKind(_ type: HKWorkoutActivityType) -> MochiWorkoutKind {
        switch type {
        case .running: return .run
        case .walking, .hiking: return .walk
        case .cycling: return .ride
        case .swimming: return .swim
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining,
             .highIntensityIntervalTraining, .crossTraining: return .strength
        case .yoga, .pilates, .mindAndBody: return .yoga
        default: return .other
        }
    }

    /// A workout or big step day just arrived from Health that Mochi hasn't
    /// mentioned: say something about it now if the Overview is showing.
    private func greetNewActivity() {
        guard mochiHomeCanUpdate, dashboardVisible, mochi.hasUngreetedActivity() else { return }
        mochi.refreshHome(history: weightHistory, profile: profile)
    }

    /// One History card: everything that happened on a calendar day.
    struct ActivityDay: Identifiable {
        let day: Date
        var weighIns: [WeightSample] = []
        var workouts: [HealthKitSink.WorkoutEntry] = []
        var totals: HealthKitSink.DailyTotals?
        var id: Date { day }
    }

    /// Weigh-ins (all of them) plus workouts and daily totals, grouped by local
    /// day, newest first. Days with nothing at all don't appear.
    var activityFeed: [ActivityDay] {
        let cal = Calendar.current
        var days: [Date: ActivityDay] = [:]
        for s in weightHistory {
            let d = cal.startOfDay(for: s.date)
            days[d, default: ActivityDay(day: d)].weighIns.append(s)
        }
        for w in workouts {
            let d = cal.startOfDay(for: w.start)
            days[d, default: ActivityDay(day: d)].workouts.append(w)
        }
        for (d, t) in dailyTotals {
            days[d, default: ActivityDay(day: d)].totals = t
        }
        return days.values
            .map { day in
                var day = day
                day.weighIns.sort { $0.date > $1.date }
                day.workouts.sort { $0.start > $1.start }
                return day
            }
            .sorted { $0.day > $1.day }
    }

    #if DEBUG
    private func loadDemoActivity() {
        let cal = Calendar.current
        var totals: [Date: HealthKitSink.DailyTotals] = [:]
        var demo: [HealthKitSink.WorkoutEntry] = []
        let types: [HKWorkoutActivityType] = [.running, .walking, .cycling, .traditionalStrengthTraining, .yoga]
        for offset in 0..<40 {
            guard let day = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: Date())) else { continue }
            totals[day] = HealthKitSink.DailyTotals(steps: Double(Int.random(in: 3_000...14_000)),
                                                    activeKcal: Double(Int.random(in: 250...900)),
                                                    eatenKcal: offset % 3 == 0 ? nil : Double(Int.random(in: 1_700...2_600)))
            if offset % 2 == 0 {
                let start = day.addingTimeInterval(Double(Int.random(in: 7...19)) * 3600)
                let minutes = Double(Int.random(in: 20...75))
                demo.append(.init(id: UUID(), start: start, end: start.addingTimeInterval(minutes * 60),
                                  activityType: types[offset / 2 % types.count],
                                  activeKcal: minutes * Double(Int.random(in: 6...11)), sourceName: "Apple Watch"))
            }
        }
        dailyTotals = totals
        workouts = demo
        greetNewActivity()
    }
    #endif

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
            var reaction: (LoggedReading, MochiPresentation)?
            switch result {
            case .success:
                self?.lastSyncError = nil
                reaction = self?.reactToManualEntry(weightKg: weightKg, date: date)
                self?.loadWeightHistory()
            case .failure(let error):
                self?.lastSyncError = error.localizedDescription
            }
            completion(result)
            // After the Weigh in tab has finished (and switched to Overview), so its
            // cleanup doesn't close the reaction straight away.
            if let (reading, presentation) = reaction { self?.showManualReaction(reading, presentation) }
        }
    }

    #if DEBUG
    /// `-testNotifications YES` (simulator): post the real "saved" and "Was this you?"
    /// notifications a few seconds from now, for a pending review item when there is one.
    func debugPostTestNotifications() {
        notifications.debugDelay = 6
        let kg = currentWeightKg ?? 80
        if mochi.settings.enabled {
            notifications.notifySaved(title: "Mochi", body: mochi.savedNotificationBody(weightKg: kg, profile: profile))
        } else {
            notifications.notifySaved(weightKg: kg)
        }
        notifications.debugDelay = 9
        let review = pendingConfirmations.first
        notifications.notifyNeedsReview(readingID: review?.id ?? UUID(), weightKg: review?.weightKg ?? kg + 3)
        notifications.debugDelay = nil
    }
    #endif

    /// Mochi reacts to a typed weigh-in too (the user did weigh in). Mochi off: nothing.
    private func reactToManualEntry(weightKg: Double, date: Date) -> (LoggedReading, MochiPresentation)? {
        guard mochi.settings.enabled else { return nil }
        let reading = LoggedReading(capturedAt: date, weightKg: weightKg, impedanceOhms: 0,
                                    resolution: "You", composition: nil, healthKitStatus: .written)
        // Only samples from before it; the Health reload after the write would contain it.
        let history = weightHistory.filter { $0.date < date.addingTimeInterval(-60) }
        fillGoalStartIfNeeded(for: reading)
        let presentation = mochi.presentationForWeighIn(reading, history: history, profile: profile)
        return (reading, presentation)
    }

    /// Shows a manual entry's reaction full screen, like a scale weigh-in's result (same
    /// overlay, tap to dismiss, same auto-dismiss). Nothing is logged or written again.
    private func showManualReaction(_ reading: LoggedReading, _ presentation: MochiPresentation) {
        dismissTask?.cancel()
        idleTask?.cancel()
        simulateTask?.cancel()
        liveStartedAt = nil
        manualMeasurementActive = false
        weighInPresentation = presentation
        measurementPhase = .result(reading)
        if appIsActive { mochi.playHaptic(for: presentation.pose) }
        armDismiss(for: reading.id)
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
    /// ("step on your scale") and make sure we're scanning (only with a paired
    /// scale — otherwise Bluetooth stays off). Incoming adverts then drive it to
    /// `.measuring`/`.finalizing` via `updatePhase`.
    func startMeasurement() {
        dismissTask?.cancel()
        idleTask?.cancel()
        simulateTask?.cancel()
        liveStartedAt = nil
        manualMeasurementActive = true
        awaitingStepOff = false   // user explicitly wants a fresh weigh-in
        measurementPhase = .waiting
        if hasPairedScale { startBluetooth() }   // idempotent; ensures the scan is running
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
            self.weighInPresentation = nil         // Mochi has no reaction to a sample
            self.measurementPhase = .result(demo)   // show result WITHOUT persist/write/learn
            self.armDismiss(for: demo.id)
        }
    }

    /// Manually dismiss the weigh-in overlay.
    func dismissOverlay() {
        var wasResult = false
        if case .result = measurementPhase { wasResult = true }
        dismissTask?.cancel()
        idleTask?.cancel()
        simulateTask?.cancel()
        liveStartedAt = nil
        manualMeasurementActive = false
        awaitingStepOff = false
        measurementPhase = .idle
        if wasResult { noteWeighInResultSeen() }
        weighInPresentation = nil
        if wasResult { refreshMochiHome() }
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
            noteOwnWeighIn(at: logged.capturedAt)
            writeReadingToHealth(logged)
            if inBackground {
                if mochi.settings.enabled, let presentation = weighInPresentation {
                    notifications.notifySaved(title: "Mochi",
                                              body: mochi.savedNotificationBody(weightKg: reading.weightKg,
                                                                                profile: profile))
                    mochi.stash(presentation)
                } else {
                    notifications.notifySaved(weightKg: reading.weightKg)
                }
            }
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
        // Before the Health write, so `weightHistory` doesn't contain this reading yet.
        if mochi.settings.enabled {
            if logged.resolution == "You" && !logged.needsConfirmation { fillGoalStartIfNeeded(for: logged) }
            let presentation = mochi.presentationForWeighIn(logged, history: weightHistory, profile: profile)
            weighInPresentation = presentation
            if appIsActive { mochi.playHaptic(for: presentation.pose) }
        } else {
            weighInPresentation = nil
        }
        measurementPhase = .result(logged)
        armDismiss(for: logged.id)
    }

    private func armDismiss(for id: UUID) {
        dismissTask?.cancel()
        // Mochi's line needs time to read: at least 10 s, longer for long lines.
        let delay: UInt64
        if mochi.settings.enabled {
            let characters = Double(weighInPresentation?.text.count ?? 0)
            delay = UInt64(max(10, 3 + 0.07 * characters) * 1_000_000_000)
        } else {
            delay = 3_500_000_000
        }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled else { return }
            if case .result(let r) = self.measurementPhase, r.id == id {
                self.measurementPhase = .idle
                self.noteWeighInResultSeen()
                self.weighInPresentation = nil
                self.refreshMochiHome()
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
