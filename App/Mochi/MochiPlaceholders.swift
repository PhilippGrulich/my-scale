import Foundation
import MyOpenScaleCore

/// Builds the `{key}` values Mochi's lines are rendered with, in local number formatting.
/// Keys whose data is missing are left out, so lines that need them are not picked.
enum MochiPlaceholders {
    /// Values that do not depend on a particular reaction: name, weight, target, left, percent, streak, weeks.
    static func values(profile: StoredProfile, currentKg: Double?, history: [WeightSample],
                       stats: MochiStats?, now: Date) -> [String: String] {
        var values: [String: String] = [:]
        let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { values["name"] = name }

        let goal = profile.weightGoal
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

    /// Adds the values a weigh-in reaction carries: change, and the event's own number.
    static func applyReaction(_ reaction: MochiReaction, goal: WeightGoal, currentKg: Double,
                              to values: inout [String: String]) {
        let change: Double?
        switch reaction.event {
        case .milestoneKg:
            // Total moved since the goal was set.
            change = goal.startKg.map { currentKg - $0 }
        default:
            change = reaction.changeKg
        }
        if let change, let text = signed(change) { values["change"] = text }

        switch reaction.event {
        case .milestonePercent(let percent): values["percent"] = String(percent)
        case .daysInRange(let days): values["days"] = String(days)
        case .streak(let days): values["streak"] = String(days)
        default: break
        }
    }

    /// "+0,6" / "−0,6" (true minus sign); nil for flat changes below the noise threshold.
    static func signed(_ kg: Double) -> String? {
        // The epsilon keeps binary rounding (80.1 - 80.0 = 0.0999…) from hiding a real 0.1 kg.
        guard abs(kg) + 1e-9 >= WeightGoal.noiseKg else { return nil }
        return (kg > 0 ? "+" : "\u{2212}") + abs(kg).formatted(1)
    }
}
