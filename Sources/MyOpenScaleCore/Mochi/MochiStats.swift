import Foundation

/// Weigh-in statistics Mochi uses to pick greetings and reactions.
public struct MochiStats: Equatable, Sendable {
    /// Consecutive calendar days with at least one sample, ending today (or yesterday if today has none yet).
    public var streakDays: Int
    /// Whole calendar days since the latest sample (0 = today). Nil with no history.
    public var daysSinceLastWeighIn: Int?
    /// Mean of the last 7 days minus mean of the 7 days before. Nil if either window is empty.
    public var weekChangeKg: Double?
    /// Same as `weekChangeKg`, shifted back one week.
    public var previousWeekChangeKg: Double?
    /// Maintain goals only: consecutive weigh-in days (ending at the latest) whose daily mean is in band.
    public var daysInRangeStreak: Int
    /// Calendar days from first launch to now.
    public var daysUsingApp: Int

    public init(
        streakDays: Int,
        daysSinceLastWeighIn: Int?,
        weekChangeKg: Double?,
        previousWeekChangeKg: Double?,
        daysInRangeStreak: Int,
        daysUsingApp: Int
    ) {
        self.streakDays = streakDays
        self.daysSinceLastWeighIn = daysSinceLastWeighIn
        self.weekChangeKg = weekChangeKg
        self.previousWeekChangeKg = previousWeekChangeKg
        self.daysInRangeStreak = daysInRangeStreak
        self.daysUsingApp = daysUsingApp
    }

    public static func compute(
        history: [WeightSample],
        now: Date,
        firstLaunch: Date,
        goal: WeightGoal,
        calendar: Calendar
    ) -> MochiStats {
        let today = calendar.startOfDay(for: now)

        func dayCount(from a: Date, to b: Date) -> Int {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? 0
        }

        // Weights grouped by calendar day.
        var byDay: [Date: [Double]] = [:]
        for sample in history {
            byDay[calendar.startOfDay(for: sample.date), default: []].append(sample.weightKg)
        }

        // Streak: walk back from today, or from yesterday if today has no sample yet.
        var streak = 0
        var cursor = byDay[today] != nil ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        while byDay[cursor] != nil {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }

        let latestDay = byDay.keys.max()
        let daysSince = latestDay.map { dayCount(from: $0, to: now) }

        func mean(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        func windowMean(weeksBack: Int) -> Double? {
            guard let end = calendar.date(byAdding: .day, value: -7 * weeksBack, to: now),
                  let start = calendar.date(byAdding: .day, value: -7, to: end) else { return nil }
            return mean(history.filter { $0.date > start && $0.date <= end }.map(\.weightKg))
        }
        func change(weeksBack: Int) -> Double? {
            guard let recent = windowMean(weeksBack: weeksBack),
                  let earlier = windowMean(weeksBack: weeksBack + 1) else { return nil }
            return recent - earlier
        }

        var inRange = 0
        if goal.type == .maintain {
            for day in byDay.keys.sorted(by: >) {
                guard let dailyMean = mean(byDay[day] ?? []), goal.isInBand(dailyMean) else { break }
                inRange += 1
            }
        }

        return MochiStats(
            streakDays: streak,
            daysSinceLastWeighIn: daysSince,
            weekChangeKg: change(weeksBack: 0),
            previousWeekChangeKg: change(weeksBack: 1),
            daysInRangeStreak: inRange,
            daysUsingApp: dayCount(from: firstLaunch, to: now)
        )
    }
}
