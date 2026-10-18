import Foundation

public enum ReminderMode: String, Codable, Sendable {
    case smart
    case fixed
}

public enum ReminderStage: Int, Codable, Sendable, CaseIterable {
    case day1 = 1, day2 = 2, day4 = 4, day8 = 8, weekly = 0

    public var lineEvent: String {
        switch self {
        case .day1: return "reminder1"
        case .day2: return "reminder2"
        case .day4: return "reminder4"
        case .day8: return "reminder8"
        case .weekly: return "reminderWeekly"
        }
    }
}

public struct PlannedReminder: Equatable, Sendable {
    public let fireDate: Date
    public let stage: ReminderStage

    public init(fireDate: Date, stage: ReminderStage) {
        self.fireDate = fireDate
        self.stage = stage
    }
}

public enum ReminderPlanner {
    public static let defaultMinuteOfDay = 8 * 60

    private static let minutesPerDay = 24 * 60

    /// Circular median of the minute-of-day of the latest `sampleCount` samples.
    public static func usualMinuteOfDay(history: [WeightSample], calendar: Calendar, sampleCount: Int = 10) -> Int? {
        let minutes = history
            .sorted { $0.date > $1.date }
            .prefix(sampleCount)
            .map { sample -> Int in
                let c = calendar.dateComponents([.hour, .minute], from: sample.date)
                return (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        guard !minutes.isEmpty else { return nil }

        func circularDistance(_ a: Int, _ b: Int) -> Int {
            let d = abs(a - b)
            return min(d, minutesPerDay - d)
        }
        // Ties resolve to the earliest minute for determinism.
        return minutes.sorted().min { lhs, rhs in
            let l = minutes.reduce(0) { $0 + circularDistance(lhs, $1) }
            let r = minutes.reduce(0) { $0 + circularDistance(rhs, $1) }
            return l < r
        }
    }

    public static func plan(
        lastWeighIn: Date?,
        now: Date,
        mode: ReminderMode,
        minuteOfDay: Int,
        count: Int = 8,
        calendar: Calendar
    ) -> [PlannedReminder] {
        guard count > 0 else { return [] }

        // The day that day offsets are counted from.
        let anchor: Date
        if let lastWeighIn {
            anchor = calendar.startOfDay(for: lastWeighIn)
        } else {
            // No weigh-in ever: the first reminder is the next minuteOfDay after now,
            // so treat the day before it as the anchor.
            guard let firstToday = fireDate(on: calendar.startOfDay(for: now), minuteOfDay: minuteOfDay, calendar: calendar),
                  let firstDay = firstToday > now
                    ? calendar.startOfDay(for: now)
                    : calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
                  let before = calendar.date(byAdding: .day, value: -1, to: firstDay)
            else { return [] }
            anchor = before
        }

        var result: [PlannedReminder] = []
        var index = 0
        while result.count < count && index < 10_000 {
            index += 1
            let offset: Int
            let stage: ReminderStage
            switch mode {
            case .smart:
                (offset, stage) = smartStep(index)
            case .fixed:
                offset = index
                stage = fixedStage(emittedCount: result.count)
            }
            guard let day = calendar.date(byAdding: .day, value: offset, to: anchor),
                  let fire = fireDate(on: day, minuteOfDay: minuteOfDay, calendar: calendar)
            else { continue }
            guard fire > now else { continue }
            result.append(PlannedReminder(fireDate: fire, stage: stage))
        }
        return result
    }

    /// 1-based step in the smart back-off: days +1, +2, +4, +8, then every 7 days (+15, +22, ...).
    private static func smartStep(_ n: Int) -> (offset: Int, stage: ReminderStage) {
        switch n {
        case 1: return (1, .day1)
        case 2: return (2, .day2)
        case 3: return (4, .day4)
        case 4: return (8, .day8)
        default: return (8 + 7 * (n - 4), .weekly)
        }
    }

    private static func fixedStage(emittedCount: Int) -> ReminderStage {
        switch emittedCount {
        case 0: return .day1
        case 1: return .day2
        case 2: return .day4
        case 3: return .day8
        default: return .weekly
        }
    }

    private static func fireDate(on day: Date, minuteOfDay: Int, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: day)
    }
}
