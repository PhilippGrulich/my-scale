import Foundation
import MyOpenScaleCore

/// Mochi on the watch: the same line library and reaction engine as the phone
/// (`MyOpenScaleCore`), with the watch's own small state. Greets on the
/// overview, talks the user through the weigh-in, and reacts to the result.
@MainActor
final class WatchMochi: ObservableObject {
    /// What the overview shows.
    @Published private(set) var home: MochiPresentation?
    private var homeAt: Date?

    private let library: MochiLibrary
    private var random = SystemRandomNumberGenerator()
    private var calendar: Calendar { .current }

    init() {
        let isGerman = Locale.preferredLanguages.first?.lowercased().hasPrefix("de") ?? false
        let name = isGerman ? "MochiLines-de" : "MochiLines-en"
        if let url = Bundle.main.url(forResource: name, withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let lib = try? JSONDecoder().decode(MochiLibrary.self, from: data) {
            library = lib
        } else {
            library = MochiLibrary(version: 0, lines: [])
        }
    }

    // MARK: - Overview greeting

    /// A new greeting unless the current one is still fresh (30 min, same day).
    func refreshHomeIfStale(history: [WeightSample], goal: WeightGoal, name: String?, now: Date = Date()) {
        if let at = homeAt, now.timeIntervalSince(at) < 30 * 60, calendar.isDate(at, inSameDayAs: now) { return }
        refreshHome(history: history, goal: goal, name: name, now: now)
    }

    func refreshHome(history: [WeightSample], goal: WeightGoal, name: String?, now: Date = Date()) {
        let stats = MochiStats.compute(history: history, now: now, firstLaunch: MochiStateStore.firstLaunch,
                                       goal: goal, calendar: calendar)
        let latest = history.max { $0.date < $1.date }?.weightKg
        let values = Self.values(name: name, goal: goal, currentKg: latest, history: history, stats: stats, now: now)
        let tags = context(now).tags
        let idle = (stats.daysSinceLastWeighIn ?? 0) >= 3
        let text = line(idle ? "homeIdle" : "home", goal: goal, tags: tags, streak: stats.streakDays, values: values, now: now)
            ?? line("home", goal: goal, tags: tags, streak: stats.streakDays, values: values, now: now) ?? ""
        home = MochiPresentation(pose: idle ? .snoozing : .idle, text: text, display: latest?.formatted(1) ?? "– –")
        homeAt = now
    }

    // MARK: - Weigh-in

    /// Mochi while waiting for the scale / reading it (fixed texts, like the phone).
    static func waiting(isListening: Bool) -> MochiPresentation {
        MochiPresentation(pose: .waiting,
                          text: isListening ? String(localized: "Step on your scale") : String(localized: "Can't reach Bluetooth"),
                          display: "– –")
    }

    static func measuring(_ kg: Double) -> MochiPresentation {
        MochiPresentation(pose: .waiting, text: String(localized: "Stay still on the scale."), display: kg.formatted(1))
    }

    /// Mochi's reaction to a new own weigh-in (scale or manual). `history` is
    /// the weight history *before* this reading.
    func reaction(newKg: Double, at now: Date, history: [WeightSample], goal: WeightGoal, name: String?) -> MochiPresentation {
        let state = MochiStateStore.progress ?? .fresh(for: goal)
        let (reaction, newState) = MochiReactionEngine.react(newKg: newKg, at: now, history: history,
                                                             goal: goal, state: state, calendar: calendar)
        MochiStateStore.progress = newState
        let withReading = history + [WeightSample(id: UUID(), date: now, weightKg: newKg)]
        let stats = MochiStats.compute(history: withReading, now: now, firstLaunch: MochiStateStore.firstLaunch,
                                       goal: goal, calendar: calendar)
        var values = Self.values(name: name, goal: goal, currentKg: newKg, history: withReading, stats: stats, now: now)
        if let change = reaction.changeKg, let text = Self.signed(change) { values["change"] = text }
        switch reaction.event {
        case .milestonePercent(let p): values["percent"] = String(p)
        case .daysInRange(let d): values["days"] = String(d)
        case .streak(let d): values["streak"] = String(d)
        case .milestoneKg: if let start = goal.startKg, let t = Self.signed(newKg - start) { values["change"] = t }
        default: break
        }
        let tags = context(now).tags
        var text = line(reaction.event.lineEvent, goal: goal, tags: tags, streak: stats.streakDays, values: values, now: now) ?? ""
        if reaction.isWelcomeBack, let hello = line("welcomeBack", goal: goal, tags: tags, streak: stats.streakDays,
                                                    values: values, now: now) {
            text = text.isEmpty ? hello : hello + " " + text
        }
        // The overview greeting is stale after a weigh-in.
        homeAt = nil
        return MochiPresentation(pose: reaction.pose, text: text, display: newKg.formatted(1))
    }

    // MARK: - Helpers

    private func context(_ now: Date) -> MochiCalendarContext {
        MochiCalendarContext.make(now: now, dateOfBirth: nil, calendar: calendar,
                                  regionCode: Locale.current.region?.identifier)
    }

    private func line(_ event: String, goal: WeightGoal, tags: Set<String>, streak: Int,
                      values: [String: String], now: Date) -> String? {
        var history = MochiStateStore.lineHistory
        let situation = MochiSituation(event: event, goalType: goal.type, tags: tags, streakDays: streak, values: values)
        guard let pick = MochiMessageSelector.select(from: library.lines, situation: situation,
                                                     history: history, now: now, random: &random) else { return nil }
        history.record(pick.line.id, at: now)
        MochiStateStore.lineHistory = history
        return pick.text
    }

    /// Same keys as the phone's `MochiPlaceholders`.
    private static func values(name: String?, goal: WeightGoal, currentKg: Double?, history: [WeightSample],
                               stats: MochiStats?, now: Date) -> [String: String] {
        var values: [String: String] = [:]
        if let name, !name.isEmpty { values["name"] = name }
        if let target = goal.targetKg { values["target"] = target.formatted(1) }
        if let streak = stats?.streakDays, streak > 0 { values["streak"] = String(streak) }
        guard let currentKg else { return values }
        values["weight"] = currentKg.formatted(1)
        if let target = goal.targetKg {
            let left = abs(target - currentKg)
            if left >= WeightGoal.noiseKg { values["left"] = left.formatted(1) }
            if let rate = WeightHistory.weeklyRateKg(history, lastDays: 28, now: now),
               let weeks = WeightHistory.weeksToGoal(currentKg: currentKg, goalKg: target, weeklyRateKg: rate) {
                values["weeks"] = String(max(1, Int(weeks.rounded(.up))))
            }
        }
        if let fraction = goal.progressFraction(currentKg) {
            values["percent"] = String(Int((fraction * 100).rounded()))
        }
        return values
    }

    static func signed(_ kg: Double) -> String? {
        guard abs(kg) + 1e-9 >= WeightGoal.noiseKg else { return nil }
        return (kg > 0 ? "+" : "\u{2212}") + abs(kg).formatted(1)
    }
}
