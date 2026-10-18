import Foundation

/// A goal with an optional deadline: a straight line from where the user
/// started to the goal on the target date. Everything is judged against the
/// smoothed trend, never a single noisy weigh-in.
public struct GoalPlan: Equatable, Sendable {
    public let startKg: Double
    public let startDate: Date
    public let goalKg: Double
    public let targetDate: Date

    public init(startKg: Double, startDate: Date, goalKg: Double, targetDate: Date) {
        self.startKg = startKg
        self.startDate = startDate
        self.goalKg = goalKg
        self.targetDate = targetDate
    }

    /// Where the plan says the weight should be at `date` (clamped to the
    /// start / goal outside the plan's time span).
    public func expectedKg(at date: Date) -> Double {
        let total = targetDate.timeIntervalSince(startDate)
        guard total > 0 else { return goalKg }
        let t = min(1, max(0, date.timeIntervalSince(startDate) / total))
        return startKg + (goalKg - startKg) * t
    }

    /// How far ahead of the plan `trendKg` is, in kg toward the goal:
    /// positive = ahead, negative = behind. Works for losing and gaining.
    public func aheadKg(trendKg: Double, at date: Date) -> Double {
        let direction: Double = goalKg < startKg ? -1 : 1
        return (trendKg - expectedKg(at: date)) * direction
    }

    /// Weekly change still needed (signed, kg/week) to reach the goal by the
    /// target date from `currentKg`. nil once the target date has passed.
    public func requiredWeeklyRateKg(currentKg: Double, now: Date) -> Double? {
        let weeks = targetDate.timeIntervalSince(now) / (7 * 86_400)
        guard weeks > 0.1 else { return nil }
        return (goalKg - currentKg) / weeks
    }
}

/// Status of the trend against a plan, with a tolerance band (daily weight
/// swings ±0.5 kg, so being within that is "on plan").
public enum PlanStatus: Equatable, Sendable {
    case onPlan
    case ahead(kg: Double)
    case behind(kg: Double)

    public init(aheadKg: Double, toleranceKg: Double = 0.5) {
        if aheadKg > toleranceKg { self = .ahead(kg: aheadKg) }
        else if aheadKg < -toleranceKg { self = .behind(kg: -aheadKg) }
        else { self = .onPlan }
    }
}

/// One step on the way to the goal.
public struct Milestone: Equatable, Sendable, Identifiable {
    public let kg: Double
    /// When the smoothed trend first got there (nil = not yet).
    public let reachedAt: Date?
    public var id: Double { kg }

    public init(kg: Double, reachedAt: Date?) {
        self.kg = kg
        self.reachedAt = reachedAt
    }
}

public enum BMICategory: Equatable, Sendable {
    case underweight, normal, overweight, obese

    public init(bmi: Double) {
        switch bmi {
        case ..<18.5: self = .underweight
        case ..<25: self = .normal
        case ..<30: self = .overweight
        default: self = .obese
        }
    }
}

/// Pure goal-page logic, unit-testable without a simulator.
public enum GoalInsights {

    /// Milestone step for a goal distance: fine steps for small goals, coarse
    /// ones for big goals, so there are roughly 3–10 milestones.
    public static func milestoneStepKg(distanceKg: Double) -> Double {
        let d = abs(distanceKg)
        if d <= 3 { return 0.5 }
        if d <= 15 { return 1 }
        return 2
    }

    /// Milestones between start and goal (exclusive of the start, inclusive of
    /// the goal), on round values, each with the date the trend first passed
    /// it after `startDate`. `trend` must be the smoothed series.
    public static func milestones(startKg: Double, goalKg: Double, startDate: Date,
                                  trend: [WeightSample]) -> [Milestone] {
        let distance = goalKg - startKg
        guard abs(distance) >= 0.25 else { return [] }
        let step = milestoneStepKg(distanceKg: distance)
        let losing = distance < 0
        var values: [Double] = []
        // First round value strictly past the start, then every step until the goal.
        var v = losing ? (startKg / step).rounded(.down) * step : (startKg / step).rounded(.up) * step
        if abs(v - startKg) < 1e-9 { v += losing ? -step : step }
        while losing ? v > goalKg + 1e-9 : v < goalKg - 1e-9 {
            values.append(v)
            v += losing ? -step : step
        }
        values.append(goalKg)

        let after = trend.filter { $0.date >= startDate }.sorted { $0.date < $1.date }
        return values.map { target in
            let hit = after.first { losing ? $0.weightKg <= target + 1e-9 : $0.weightKg >= target - 1e-9 }
            return Milestone(kg: target, reachedAt: hit?.date)
        }
    }

    /// Whole days the trend has stayed within `toleranceKg` of the goal, up to
    /// its latest point. nil when the latest trend value is outside the range.
    public static func daysInRange(trend: [WeightSample], goalKg: Double,
                                   toleranceKg: Double = 1) -> Int? {
        let sorted = trend.sorted { $0.date < $1.date }
        guard let last = sorted.last, abs(last.weightKg - goalKg) <= toleranceKg else { return nil }
        var since = last.date
        for s in sorted.reversed() {
            if abs(s.weightKg - goalKg) > toleranceKg { break }
            since = s.date
        }
        return Int(last.date.timeIntervalSince(since) / 86_400)
    }

    /// Weight range for a healthy BMI (18.5–25) at this height.
    public static func healthyWeightRange(heightCm: Double) -> ClosedRange<Double> {
        let m = heightCm / 100
        return (18.5 * m * m)...(25 * m * m)
    }

    /// For each of the last `days` calendar days (oldest first), whether there
    /// was at least one weigh-in.
    public static func weighInDays(_ samples: [WeightSample], days: Int, now: Date,
                                   calendar: Calendar = .current) -> [Bool] {
        let today = calendar.startOfDay(for: now)
        let logged = Set(samples.map { calendar.startOfDay(for: $0.date) })
        return (0..<days).reversed().map { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return false }
            return logged.contains(day)
        }
    }

    /// Progress toward a body-fat goal, 0…1, from the starting value.
    public static func bodyFatProgress(startPercent: Double, currentPercent: Double, goalPercent: Double) -> Double? {
        WeightHistory.goalProgress(startKg: startPercent, currentKg: currentPercent, goalKg: goalPercent)
    }
}
