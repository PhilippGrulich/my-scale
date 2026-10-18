import Foundation
import UIKit
import MyOpenScaleCore

/// Glue between `AppModel` and the pure Mochi core: runs the reaction engine, picks
/// lines, persists Mochi's state and plays haptics.
@MainActor
final class MochiCoordinator: ObservableObject {
    /// Persisted on every change, which also reschedules the reminders.
    @Published var settings: MochiSettings {
        didSet {
            guard settings != oldValue else { return }
            MochiStateStore.settings = settings
            rescheduleReminders(history: historyProvider(), profile: profileProvider(),
                                lastWeighInOverride: lastWeighInProvider())
        }
    }

    /// What the home-screen Mochi currently shows.
    @Published private(set) var homePresentation: MochiPresentation?
    /// When `homePresentation` was produced; decides whether the greeting is still fresh.
    private(set) var homeProducedAt: Date?
    /// A greeting older than this is replaced on the next dashboard appear or foreground.
    static let homeFreshness: TimeInterval = 30 * 60

    /// Current weight history and profile, supplied by `AppModel`, for work not
    /// triggered by a call that passes them in (e.g. reminders after a settings change).
    var historyProvider: () -> [WeightSample] = { [] }
    /// Newest own weigh-in that may not be in the history (e.g. a failed Health write).
    var lastWeighInProvider: () -> Date? = { nil }
    var profileProvider: () -> StoredProfile = { StoredProfile.makeDefault() }

    private let library: MochiLibrary
    private let reminderScheduler = MochiReminderScheduler()
    private var random = SystemRandomNumberGenerator()
    private var calendar: Calendar { .current }

    init(library loader: () -> MochiLibrary = MochiCoordinator.loadBundledLibrary) {
        self.library = loader()
        var initial = MochiStateStore.settings
        #if DEBUG
        // `-mochiEnabled YES|NO` on launch turns Mochi on or off (and persists it) for simulator checks.
        if UserDefaults.standard.object(forKey: "mochiEnabled") != nil {
            initial.enabled = UserDefaults.standard.bool(forKey: "mochiEnabled")
            MochiStateStore.settings = initial
        }
        #endif
        self.settings = initial
    }

    /// The bundled line library for the user's language (German or English). Never fails:
    /// a missing or invalid file yields an empty library, and Mochi just says nothing.
    nonisolated static func loadBundledLibrary() -> MochiLibrary {
        let isGerman = Locale.preferredLanguages.first?.lowercased().hasPrefix("de") ?? false
        let name = isGerman ? "MochiLines-de" : "MochiLines-en"
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let library = try? JSONDecoder().decode(MochiLibrary.self, from: data)
        else { return MochiLibrary(version: 0, lines: []) }
        return library
    }

    // MARK: - Weigh-in

    /// Mochi's reaction to a finalized weigh-in. Updates the celebration state for the owner's readings.
    func presentationForWeighIn(_ reading: LoggedReading, history: [WeightSample], profile: StoredProfile) -> MochiPresentation {
        let now = reading.capturedAt
        let display = reading.weightKg.formatted(1)
        let goal = profile.weightGoal
        let context = calendarContext(now: now, profile: profile)
        let isOwn = reading.resolution == "You" && !reading.needsConfirmation

        guard isOwn else {
            let reaction = MochiReactionEngine.notYou()
            let text = line(reaction.event.lineEvent, goalType: goal.type, tags: context.tags,
                            streakDays: 0, values: [:], now: now) ?? ""
            return MochiPresentation(pose: reaction.pose, text: text, display: display)
        }

        let state = MochiStateStore.progress ?? .fresh(for: goal)
        let (reaction, newState) = MochiReactionEngine.react(newKg: reading.weightKg, at: now, history: history,
                                                             goal: goal, state: state, calendar: calendar)
        MochiStateStore.progress = newState

        let withReading = history + [WeightSample(id: reading.id, date: now, weightKg: reading.weightKg)]
        let stats = MochiStats.compute(history: withReading, now: now, firstLaunch: MochiStateStore.firstLaunch,
                                       goal: goal, calendar: calendar)
        var values = MochiPlaceholders.values(profile: profile, currentKg: reading.weightKg,
                                              history: withReading, stats: stats, now: now)
        MochiPlaceholders.applyReaction(reaction, goal: goal, currentKg: reading.weightKg, to: &values)

        func say(_ event: String) -> String? {
            line(event, goalType: goal.type, tags: context.tags, streakDays: stats.streakDays, values: values, now: now)
        }

        let presentation: MochiPresentation
        if context.isBirthday && reaction.event != .goalReached {
            // No weight talk on the user's birthday, except for reaching the goal.
            presentation = MochiPresentation(pose: .birthday, text: say("birthday") ?? "", display: display)
        } else {
            var text = say(reaction.event.lineEvent) ?? ""
            if reaction.isWelcomeBack, let hello = say("welcomeBack") {
                text = text.isEmpty ? hello : hello + " " + text
            }
            presentation = MochiPresentation(pose: reaction.pose, text: text, display: display)
        }
        return presentation
    }

    /// Keep a background weigh-in's reaction for the home screen.
    func stash(_ presentation: MochiPresentation) {
        MochiStateStore.pendingHomeReaction = presentation
    }

    // MARK: - Home

    /// Shows a stashed background reaction, if there is one. Never generates a greeting.
    @discardableResult
    func showPendingHomeReaction(now: Date = Date()) -> Bool {
        guard let pending = MochiStateStore.pendingHomeReaction else { return false }
        MochiStateStore.pendingHomeReaction = nil
        homePresentation = pending
        homeProducedAt = now
        return true
    }

    /// Whether there is no greeting yet, or it is older than 30 minutes or from another day.
    func isHomeStale(now: Date = Date()) -> Bool {
        guard homePresentation != nil, let at = homeProducedAt else { return true }
        return now.timeIntervalSince(at) > Self.homeFreshness || !calendar.isDate(at, inSameDayAs: now)
    }

    /// Dashboard appear / foreground: a stashed reaction first, else a new greeting only when
    /// the current one is stale. Keeps a fresh greeting (and the repeat-avoidance history) untouched.
    func refreshHomeIfStale(history: [WeightSample], profile: StoredProfile, now: Date = Date()) {
        if showPendingHomeReaction(now: now) { return }
        if isHomeStale(now: now) { refreshHome(history: history, profile: profile, now: now) }
    }

    /// Picks what the home-screen Mochi shows: a stashed reaction first, else a new greeting.
    func refreshHome(history: [WeightSample], profile: StoredProfile, now: Date = Date()) {
        if showPendingHomeReaction(now: now) { return }

        let goal = profile.weightGoal
        let context = calendarContext(now: now, profile: profile)
        let stats = MochiStats.compute(history: history, now: now, firstLaunch: MochiStateStore.firstLaunch,
                                       goal: goal, calendar: calendar)
        let latestKg = history.max(by: { $0.date < $1.date })?.weightKg
        var values = MochiPlaceholders.values(profile: profile, currentKg: latestKg,
                                              history: history, stats: stats, now: now)

        let event: String
        var pose = MochiPose.idle
        if context.isBirthday {
            event = "birthday"
            pose = .birthday
        } else if let days = stats.daysSinceLastWeighIn, days >= 3 {
            event = "homeIdle"
            pose = .snoozing
        } else if [30, 100, 365].contains(stats.daysUsingApp) {
            event = "anniversary"
            values["days"] = String(stats.daysUsingApp)
        } else {
            event = "home"
        }

        func say(_ event: String) -> String? {
            line(event, goalType: goal.type, tags: context.tags, streakDays: stats.streakDays, values: values, now: now)
        }
        // A special occasion without a fitting line falls back to a plain greeting.
        let text = say(event) ?? (event == "home" ? nil : say("home")) ?? ""
        homePresentation = MochiPresentation(pose: pose, text: text, display: latestKg?.formatted(1) ?? "– –")
        homeProducedAt = now
    }

    // MARK: - Goal page

    /// What the Goal page's Mochi currently shows, and when it was produced.
    @Published private(set) var goalPresentation: MochiPresentation?
    private(set) var goalProducedAt: Date?

    /// Same freshness rule as the home greeting: none yet, older than 30 minutes, or from another day.
    func isGoalStale(now: Date = Date()) -> Bool {
        guard goalPresentation != nil, let at = goalProducedAt else { return true }
        return now.timeIntervalSince(at) > Self.homeFreshness || !calendar.isDate(at, inSameDayAs: now)
    }

    /// Goal page appear / foreground: a new line only when the current one is stale.
    func refreshGoalIfStale(history: [WeightSample], profile: StoredProfile, status: MochiGoalStatus, now: Date = Date()) {
        if isGoalStale(now: now) { refreshGoal(history: history, profile: profile, status: status, now: now) }
    }

    /// A new goal-focused line (tap, or the goal or its state changed).
    func refreshGoal(history: [WeightSample], profile: StoredProfile, status: MochiGoalStatus, now: Date = Date()) {
        goalPresentation = goalPresentation(history: history, profile: profile, status: status, now: now)
        goalProducedAt = now
    }

    /// The Goal page's line: an invite without a goal, progress on the way, praise once reached.
    func goalPresentation(history: [WeightSample], profile: StoredProfile, status: MochiGoalStatus,
                          now: Date = Date()) -> MochiPresentation {
        let goal = profile.weightGoal
        let context = calendarContext(now: now, profile: profile)
        let stats = MochiStats.compute(history: history, now: now, firstLaunch: MochiStateStore.firstLaunch,
                                       goal: goal, calendar: calendar)
        var values = MochiPlaceholders.values(profile: profile, currentKg: status.currentKg,
                                              history: history, stats: stats, now: now)
        // The page's own numbers, so Mochi agrees with the ring.
        if let progress = status.progress, goal.type != .maintain {
            values["percent"] = String(Int((progress * 100).rounded()))
        }
        if let days = status.daysInRange { values["days"] = String(days) }

        let event: String
        var pose = MochiPose.idle
        if goal.targetKg == nil || status.currentKg == nil {
            event = "goalNone"
        } else if status.reached {
            event = "goalReachedHome"
            pose = .doubleThumbs
        } else {
            event = "goalProgress"
            if let progress = status.progress, progress >= 0.75 { pose = .doubleThumbs }
        }
        let text = line(event, goalType: goal.type, tags: context.tags, streakDays: stats.streakDays,
                        values: values, now: now) ?? ""
        return MochiPresentation(pose: pose, text: text, display: status.currentKg?.formatted(1) ?? "– –")
    }

    // MARK: - Notifications

    /// Body of the "Weigh-in saved" notification in Mochi's voice.
    func savedNotificationBody(weightKg: Double, profile: StoredProfile) -> String {
        let now = Date()
        var values = MochiPlaceholders.values(profile: profile, currentKg: nil, history: [], stats: nil, now: now)
        values["weight"] = weightKg.formatted(1)
        return line("saved", goalType: profile.weightGoal.type, tags: tags(now: now, profile: profile),
                    streakDays: 0, values: values, now: now)
            ?? String(localized: "\(weightKg.formatted(.number.precision(.fractionLength(1)))) kg saved to Apple Health.")
    }

    /// Body of a weigh-in reminder for `stage`.
    func reminderBody(stage: ReminderStage, profile: StoredProfile) -> String {
        var history = MochiStateStore.lineHistory
        let body = reminderBody(stage: stage, profile: profile, history: &history)
        MochiStateStore.lineHistory = history
        return body
    }

    /// Same, but recording the pick into `history` only; the caller decides whether to persist it.
    private func reminderBody(stage: ReminderStage, profile: StoredProfile, history: inout MochiLineHistory) -> String {
        let now = Date()
        let weights = historyProvider()
        let stats = MochiStats.compute(history: weights, now: now, firstLaunch: MochiStateStore.firstLaunch,
                                       goal: profile.weightGoal, calendar: calendar)
        var values = MochiPlaceholders.values(profile: profile, currentKg: nil, history: [], stats: nil, now: now)
        if stats.streakDays > 0 { values["streak"] = String(stats.streakDays) }
        return line(stage.lineEvent, goalType: profile.weightGoal.type, tags: tags(now: now, profile: profile),
                    streakDays: stats.streakDays, values: values, now: now, history: &history)
            ?? String(localized: "Time for a quick weigh-in?")
    }

    /// Recomputes the pending reminders: none when Mochi or reminders are off.
    ///
    /// `lastWeighInOverride` is a weigh-in not (yet) in `history`, e.g. when the Health write
    /// or read failed; the later of the two counts as the last weigh-in.
    func rescheduleReminders(history: [WeightSample], profile: StoredProfile, now: Date = Date(),
                             lastWeighInOverride: Date? = nil) {
        guard settings.enabled, settings.remindersEnabled else {
            reminderScheduler.cancelAll()
            return
        }
        let minute: Int
        switch settings.reminderMode {
        case .fixed:
            minute = settings.fixedMinuteOfDay
        case .smart:
            minute = settings.smartMinuteOverride
                ?? ReminderPlanner.usualMinuteOfDay(history: history, calendar: calendar)
                ?? ReminderPlanner.defaultMinuteOfDay
        }
        let planned = ReminderPlanner.plan(lastWeighIn: ([lastWeighInOverride].compactMap { $0 } + history.map(\.date)).max(), now: now,
                                           mode: settings.reminderMode, minuteOfDay: minute,
                                           count: Self.reminderCount(settings.reminderMode), calendar: calendar)
        // Bodies are picked against a scratch copy of the line history: they avoid repeating
        // within this schedule, but are never recorded as shown (nothing was delivered yet).
        var scratch = MochiStateStore.lineHistory
        let reminders = planned.map { ($0, title: "Mochi", body: reminderBody(stage: $0.stage, profile: profile, history: &scratch)) }
        reminderScheduler.replace(with: reminders)
    }

    /// How many reminders are kept pending: fixed is daily for a month; smart covers its
    /// 1/2/4/8-day stages and then weekly for about three months. Rescheduled whenever the
    /// app runs, so this is only the horizon for a user who never opens it (best effort).
    static func reminderCount(_ mode: ReminderMode) -> Int {
        switch mode {
        case .fixed: return 30
        case .smart: return 16
        }
    }

    // MARK: - Private

    /// The one place the calendar context is built: the birthday only counts when the
    /// profile's date of birth is real, never for the placeholder default.
    private func calendarContext(now: Date, profile: StoredProfile) -> MochiCalendarContext {
        MochiCalendarContext.make(now: now, dateOfBirth: profile.knownDateOfBirth,
                                  calendar: calendar, regionCode: Locale.current.region?.identifier)
    }

    private func tags(now: Date, profile: StoredProfile) -> Set<String> {
        calendarContext(now: now, profile: profile).tags
    }

    /// Picks and renders a line for `event`, remembering it so it is not repeated soon.
    private func line(_ event: String, goalType: GoalType, tags: Set<String>, streakDays: Int,
                      values: [String: String], now: Date) -> String? {
        var history = MochiStateStore.lineHistory
        let text = line(event, goalType: goalType, tags: tags, streakDays: streakDays,
                        values: values, now: now, history: &history)
        MochiStateStore.lineHistory = history
        return text
    }

    /// As above, but records into the caller's `history` and persists nothing.
    private func line(_ event: String, goalType: GoalType, tags: Set<String>, streakDays: Int,
                      values: [String: String], now: Date, history: inout MochiLineHistory) -> String? {
        let situation = MochiSituation(event: event, goalType: goalType, tags: tags,
                                       streakDays: streakDays, values: values)
        guard let pick = MochiMessageSelector.select(from: library.lines, situation: situation,
                                                     history: history, now: now, random: &random)
        else { return nil }
        history.record(pick.line.id, at: now)
        return pick.text
    }

    /// A light tap when the user squishes Mochi.
    func playTapHaptic() {
        guard settings.haptics else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Haptic for a reaction the user is about to see (not for stashed or background ones).
    func playHaptic(for pose: MochiPose) {
        guard settings.haptics else { return }
        switch pose {
        case .confetti, .doubleThumbs:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        default:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

/// What the Goal page knows about the goal, so Mochi's line matches what the page shows.
struct MochiGoalStatus: Equatable {
    /// Trend weight now (nil before the first weigh-in).
    var currentKg: Double?
    /// The page shows the goal as reached (maintenance).
    var reached: Bool
    /// Progress 0...1 as on the ring; nil without a goal.
    var progress: Double?
    /// Days the trend has stayed in the goal range, once reached.
    var daysInRange: Int?
}
