import Foundation
import SwiftUI
import MyOpenScaleCore

/// The body details needed to compute composition on the watch. Populated from
/// HealthKit where available (DOB/sex/height sync from the phone's Health
/// profile — height once the iOS app writes it), with a watch-local fallback the
/// user can fill in when Health doesn't have a value. Height is mandatory (BMI
/// and everything downstream need it); sex/DOB gate the *full* fat/lean estimate
/// (their absence falls back to a weight+BMI-only reading).
struct WatchProfile: Codable, Equatable {
    var id: UUID = UUID()
    var heightCm: Double?
    var sex: BiologicalSex?
    var dateOfBirth: Date?

    /// True once we have the minimum needed to run a weigh-in (a height).
    var isUsable: Bool { (heightCm ?? 0) > 0 }
}

/// Watch-local persistence for `WatchProfile`. App Groups don't cross the
/// phone↔watch boundary, so the watch keeps its own copy (kept in sync from
/// HealthKit on each launch).
enum WatchProfileStore {
    private static let key = "myopenscale.watch.profile.v1"

    static func load() -> WatchProfile {
        guard let data = UserDefaults.standard.data(forKey: key),
              let p = try? JSONDecoder().decode(WatchProfile.self, from: data) else {
            let fresh = WatchProfile()
            save(fresh)
            return fresh
        }
        return p
    }

    static func save(_ profile: WatchProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

/// Orchestrator for the standalone watch app: owns the BLE scanner + HealthKit
/// sink, drives the weigh-in phases, computes composition with the shared core,
/// and writes to the watch's own HealthKit. A slim sibling of the iOS `AppModel`
/// with no multi-user attribution (the wearer is the only user), widgets, or
/// notifications.
@MainActor
final class WatchAppModel: ObservableObject {

    /// Lifecycle of a weigh-in as the watch UI experiences it.
    enum Phase: Equatable {
        case idle
        case searching                  // scanning, "step on the scale"
        case live(weightKg: Double)     // seeing weight, not stabilized yet
        case saving                     // finalized; writing to Health
        case saved(WeighInResult)       // done
        case error(String)

        var isActive: Bool { self != .idle }
    }

    /// A completed weigh-in ready to show on the result screen.
    struct WeighInResult: Equatable {
        var weightKg: Double
        var composition: BodyComposition
        var savedToHealth: Bool
        /// Full = fat/lean present; partial = weight + BMI only (no impedance or
        /// missing sex/DOB).
        var isFull: Bool
        /// Mochi's reaction (nil when Mochi is off).
        var mochi: MochiPresentation?
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var bleStatus: WatchBLEStatus = .unknown
    @Published private(set) var authState: HealthKitSink.AuthState = .notRequested
    @Published private(set) var currentWeightKg: Double?
    @Published private(set) var trendDeltaKg: Double?
    @Published private(set) var profile: WatchProfile
    @Published private(set) var history: [WeightSample] = []
    @Published private(set) var latestBodyFat: Double?
    /// Goal, name and Mochi switch from the phone.
    @Published private(set) var sync: WatchSyncPayload?
    let mochi = WatchMochi()

    /// Mochi shows unless the phone says it's off.
    var mochiEnabled: Bool { sync?.mochiEnabled ?? true }
    var name: String? { sync?.name }

    var goal: WeightGoal {
        WeightGoal(type: sync?.goalType.flatMap(GoalType.init(rawValue:)) ?? .lose,
                   targetKg: sync?.goalKg, startKg: sync?.goalStartKg)
    }

    /// The smoothed 30-day trend change (same as the phone's "30-day trend").
    var monthTrendKg: Double? { WeightHistory.trendChangeKg(history, lastDays: 30, now: Date()) }

    var bmi: Double? {
        guard let w = currentWeightKg, let h = profile.heightCm, h > 0 else { return nil }
        return BodyCompositionCalculator.bmi(weightKg: w, heightCm: h)
    }

    /// True when the user must supply a height before weighing in.
    var needsSetup: Bool { !profile.isUsable }

    private let scanner = WatchBLEScanner()
    private let healthKit = HealthKitSink()

    /// Ignore sub-threshold weights so an empty scale doesn't drive the UI.
    private let minLiveWeightKg = 5.0

    private var appBuild: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(v) (\(b))"
    }

    init() {
        self.profile = WatchProfileStore.load()
        if !HealthKitSink.isAvailable { self.authState = .unavailable }

        scanner.onStatusChange = { [weak self] status in
            Task { @MainActor in self?.bleStatus = status }
        }
        scanner.onFrame = { [weak self] parsed, _ in
            Task { @MainActor in self?.updateLive(parsed) }
        }
        scanner.onReading = { [weak self] reading, _ in
            Task { @MainActor in self?.handle(reading) }
        }

        sync = WatchSyncReceiver.stored
        WatchSyncReceiver.shared.onChange = { [weak self] payload in
            guard let self else { return }
            let mochiChanged = payload.mochiEnabled != self.sync?.mochiEnabled
            self.sync = payload
            if mochiChanged || payload.goalKg != nil { self.refreshMochi(force: true) }
        }
        WatchSyncReceiver.shared.activate()
    }

    /// New overview greeting (forced on tap / after changes, else only when stale).
    func refreshMochi(force: Bool = false) {
        guard mochiEnabled else { return }
        if force {
            mochi.refreshHome(history: history, goal: goal, name: name)
        } else {
            mochi.refreshHomeIfStale(history: history, goal: goal, name: name)
        }
    }

    // MARK: - Authorization / profile sync

    /// Request HealthKit authorization, then merge the user's characteristics
    /// (DOB / sex / height) into the watch profile and load the latest weight for
    /// the dashboard. Always safe to call on appear.
    func requestAuthorizationAndSync() {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "demoWeightHistory") { loadLatestWeight(); return }
        #endif
        guard HealthKitSink.isAvailable else { authState = .unavailable; return }
        healthKit.requestAuthorization { [weak self] state in
            guard let self else { return }
            self.authState = state
            guard state == .requested else { return }
            self.syncProfileFromHealth()
            self.loadLatestWeight()
        }
    }

    /// Fill any missing profile fields from HealthKit (never overwrites a value
    /// the user entered on the watch), and persist.
    private func syncProfileFromHealth() {
        healthKit.readUserCharacteristics { [weak self] prefill in
            guard let self else { return }
            var p = self.profile
            if p.heightCm == nil, let h = prefill.heightCm, h > 0 { p.heightCm = h }
            if p.sex == nil, let s = prefill.sex { p.sex = s }
            if p.dateOfBirth == nil, let d = prefill.dateOfBirth { p.dateOfBirth = d }
            if p != self.profile {
                self.profile = p
                WatchProfileStore.save(p)
            }
        }
    }

    /// Persist a profile the user edited on the watch (the setup screen).
    func updateProfile(_ updated: WatchProfile) {
        profile = updated
        WatchProfileStore.save(updated)
    }

    /// Refresh the latest weight + trend from HealthKit for the dashboard.
    func loadLatestWeight() {
        #if DEBUG
        // `-demoWeightHistory YES`: synthetic history + goal for simulator checks.
        if UserDefaults.standard.bool(forKey: "demoWeightHistory") {
            var rng = SystemRandomNumberGenerator()
            history = (0..<60).reversed().map { day in
                WeightSample(id: UUID(), date: Date().addingTimeInterval(-Double(day) * 86_400 - 3600),
                             weightKg: ((82 - Double(60 - day) * 0.03 + Double.random(in: -0.4...0.4, using: &rng)) * 10).rounded() / 10)
            }
            currentWeightKg = history.last?.weightKg
            latestBodyFat = 24.8
            if profile.heightCm == nil { profile.heightCm = 178 }
            sync = WatchSyncPayload(name: "Philipp", goalKg: 76, goalType: "lose", goalStartKg: 82, mochiEnabled: true)
            refreshMochi(force: true)
            return
        }
        #endif
        healthKit.readWeightHistory { [weak self] result in
            guard let self, case .success(let samples) = result else { return }
            self.history = samples
            self.currentWeightKg = samples.last?.weightKg
            self.trendDeltaKg = WeightHistory.trendDeltaKg(samples)
            self.refreshMochi()
        }
        healthKit.readLatest(.bodyFat) { [weak self] sample in
            self?.latestBodyFat = sample.flatMap { $0.value.isFinite ? $0.value : nil }
        }
    }

    // MARK: - Weigh-in

    /// Start a standalone weigh-in: scan for the scale and wait for the user to
    /// step on. No-op if the profile still needs a height.
    func startWeighIn() {
        guard !needsSetup else { return }
        phase = .searching
        scanner.start()
    }

    /// Cancel an in-progress weigh-in and return to idle.
    func cancel() {
        scanner.stop()
        phase = .idle
    }

    /// Dismiss the result screen and return to the dashboard.
    func done() {
        scanner.stop()
        phase = .idle
        loadLatestWeight()
    }

    private func updateLive(_ adv: ParsedAdvertisement) {
        switch phase {
        case .searching, .live:
            guard !adv.isWeightRemoved, adv.weightKg >= minLiveWeightKg else { return }
            phase = .live(weightKg: adv.weightKg)
        default:
            break
        }
    }

    private func handle(_ reading: FinalizedReading) {
        // Ignore stray finalizations that arrive after we've left the weigh-in.
        switch phase {
        case .searching, .live: break
        default: return
        }
        scanner.stop()
        phase = .saving

        guard let height = profile.heightCm, height > 0 else {
            phase = .error(String(localized: "Missing height — set it up first."))
            return
        }

        // Mochi reacts against the history before this reading.
        let reaction = mochiEnabled
            ? mochi.reaction(newKg: reading.weightKg, at: reading.capturedAt, history: history, goal: goal, name: name)
            : nil

        let composition: BodyComposition
        let isFull: Bool
        if (1...3000).contains(reading.impedanceOhms), let sex = profile.sex, let dob = profile.dateOfBirth {
            let body = BodyProfile(heightCm: height,
                                   ageYears: Double(DateMath.ageYears(dateOfBirth: dob, at: reading.capturedAt)),
                                   sex: sex)
            composition = BodyCompositionCalculator.compute(
                weightKg: reading.weightKg,
                impedanceOhms: Double(reading.impedanceOhms),
                profile: body)
            isFull = true
        } else {
            // Partial only needs height for BMI; sex/age are unused here.
            let body = BodyProfile(heightCm: height, ageYears: 30, sex: .male)
            composition = BodyCompositionCalculator.partial(weightKg: reading.weightKg, profile: body)
            isFull = false
        }

        healthKit.write(composition: composition,
                        capturedAt: reading.capturedAt,
                        impedanceOhms: reading.impedanceOhms,
                        profile: coreProfile,
                        appBuild: appBuild) { [weak self] result in
            guard let self else { return }
            let saved: Bool
            switch result {
            case .success:
                saved = true
                self.loadLatestWeight()
            case .failure:
                saved = false
            }
            self.phase = .saved(WeighInResult(weightKg: reading.weightKg,
                                              composition: composition,
                                              savedToHealth: saved,
                                              isFull: isFull,
                                              mochi: reaction))
        }
    }

    // MARK: - Manual entry

    /// Save a weight typed in with the Digital Crown (no scale). BMI from the
    /// height; shown on the same result screen with Mochi's reaction.
    func saveManual(weightKg: Double) {
        let now = Date()
        let reaction = mochiEnabled
            ? mochi.reaction(newKg: weightKg, at: now, history: history, goal: goal, name: name)
            : nil
        let composition = BodyCompositionCalculator.manual(weightKg: weightKg, bodyFatPercent: nil,
                                                           heightCm: profile.heightCm ?? 175)
        phase = .saving
        healthKit.writeManual(composition: composition, at: now) { [weak self] result in
            guard let self else { return }
            let saved: Bool
            if case .success = result { saved = true; self.loadLatestWeight() } else { saved = false }
            self.phase = .saved(WeighInResult(weightKg: weightKg, composition: composition,
                                              savedToHealth: saved, isFull: false, mochi: reaction))
        }
    }

    /// The core profile used only to tag the HealthKit sample (id/owner). Missing
    /// sex/DOB fall back to neutral placeholders — they don't affect the already
    /// computed composition.
    private var coreProfile: UserProfile {
        UserProfile(
            id: profile.id,
            name: String(localized: "Me"),
            heightCm: profile.heightCm ?? 175,
            dateOfBirth: profile.dateOfBirth ?? Date(timeIntervalSince1970: 0),
            sex: profile.sex ?? .male,
            weightRangeKg: 30...250,
            isHealthKitOwner: true)
    }
}
