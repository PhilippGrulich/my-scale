import Foundation

/// Coarse workout family Mochi has lines for.
public enum MochiWorkoutKind: String, Codable, Sendable, CaseIterable {
    case run, walk, ride, swim, strength, yoga, other
}

/// One workout as Mochi sees it (mapped from HealthKit in the app).
public struct MochiWorkout: Equatable, Sendable {
    public var id: String
    public var start: Date
    public var end: Date
    public var kind: MochiWorkoutKind
    /// Localized display name, e.g. "Laufen" (fills the `{activity}` placeholder).
    public var name: String

    public init(id: String, start: Date, end: Date, kind: MochiWorkoutKind, name: String) {
        self.id = id
        self.start = start
        self.end = end
        self.kind = kind
        self.name = name
    }

    public var minutes: Int { max(1, Int((end.timeIntervalSince(start) / 60).rounded())) }
}

/// What Mochi knows about recent activity: the latest workout from today or
/// yesterday, how many workouts this week, and whether today or yesterday was a
/// big step day. Pure, built from Apple Health data the app already reads.
public struct MochiActivityContext: Equatable, Sendable {
    /// Latest workout that ended today or yesterday.
    public var latest: MochiWorkout?
    public var latestIsToday: Bool
    /// The latest workout ended less than 24 hours ago (water retention window).
    public var recentWithin24h: Bool
    public var workoutsLast7Days: Int
    /// Steps of today / yesterday, nil when unknown.
    public var stepsToday: Double?
    public var stepsYesterday: Double?

    /// A day with at least this many steps counts as a big step day.
    public static let bigStepDay: Double = 10_000

    public static let none = MochiActivityContext(latest: nil, latestIsToday: false, recentWithin24h: false,
                                                  workoutsLast7Days: 0, stepsToday: nil, stepsYesterday: nil)

    public init(latest: MochiWorkout?, latestIsToday: Bool, recentWithin24h: Bool,
                workoutsLast7Days: Int, stepsToday: Double?, stepsYesterday: Double?) {
        self.latest = latest
        self.latestIsToday = latestIsToday
        self.recentWithin24h = recentWithin24h
        self.workoutsLast7Days = workoutsLast7Days
        self.stepsToday = stepsToday
        self.stepsYesterday = stepsYesterday
    }

    /// `stepsByDay` is keyed by start of day (local calendar).
    public static func make(workouts: [MochiWorkout], stepsByDay: [Date: Double],
                            now: Date, calendar: Calendar) -> MochiActivityContext {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let past = workouts.filter { $0.end <= now }
        let latest = past.filter { $0.end >= yesterday }.max { $0.end < $1.end }
        return MochiActivityContext(
            latest: latest,
            latestIsToday: latest.map { $0.end >= today } ?? false,
            recentWithin24h: latest.map { now.timeIntervalSince($0.end) < 86_400 } ?? false,
            workoutsLast7Days: past.filter { $0.end >= weekAgo }.count,
            stepsToday: stepsByDay[today],
            stepsYesterday: stepsByDay[yesterday])
    }

    /// The step day worth mentioning (today first), or nil.
    public var bigStepDay: (isToday: Bool, steps: Double)? {
        if let s = stepsToday, s >= Self.bigStepDay { return (true, s) }
        if let s = stepsYesterday, s >= Self.bigStepDay { return (false, s) }
        return nil
    }

    /// Tags lines filter on.
    public var tags: Set<String> {
        var result = Set<String>()
        if let latest {
            result.insert(latestIsToday ? "workout:today" : "workout:yesterday")
            result.insert("workout:\(latest.kind.rawValue)")
        }
        if workoutsLast7Days >= 3 { result.insert("workout:week") }
        if let day = bigStepDay { result.insert(day.isToday ? "steps:today" : "steps:yesterday") }
        return result
    }

    /// Values for the `{activity}`, `{minutes}` and `{steps}` placeholders.
    public func values(formatSteps: (Double) -> String) -> [String: String] {
        var values: [String: String] = [:]
        if let latest {
            values["activity"] = latest.name
            values["minutes"] = String(latest.minutes)
        }
        if let day = bigStepDay { values["steps"] = formatSteps(day.steps) }
        return values
    }
}
