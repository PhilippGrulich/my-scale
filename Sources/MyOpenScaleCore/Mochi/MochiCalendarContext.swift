import Foundation

/// Coarse part of the day, used to pick greetings. Boundaries are start-inclusive.
public enum TimeOfDay: String, Codable, Sendable {
    case earlyMorning // 04-07
    case morning      // 07-11
    case midday       // 11-14
    case afternoon    // 14-18
    case evening      // 18-22
    case night        // 22-04
}

/// Holidays Mochi has special lines for.
public enum Holiday: String, Codable, Sendable {
    case christmas, newYear, easter
}

/// Northern hemisphere season by month.
public enum Season: String, Codable, Sendable {
    case spring, summer, autumn, winter
}

/// What day it is for Mochi: time of day, weekday, holiday, season and birthday,
/// reducible to tags that dialogue lines filter on.
public struct MochiCalendarContext: Equatable, Sendable {
    public var timeOfDay: TimeOfDay
    /// 1 = Sunday ... 7 = Saturday (Calendar convention).
    public var weekday: Int
    public var isWeekend: Bool
    public var isMonday: Bool
    public var isFriday: Bool
    public var holiday: Holiday?
    public var season: Season
    public var isBirthday: Bool

    public init(
        timeOfDay: TimeOfDay,
        weekday: Int,
        isWeekend: Bool,
        isMonday: Bool,
        isFriday: Bool,
        holiday: Holiday?,
        season: Season,
        isBirthday: Bool
    ) {
        self.timeOfDay = timeOfDay
        self.weekday = weekday
        self.isWeekend = isWeekend
        self.isMonday = isMonday
        self.isFriday = isFriday
        self.holiday = holiday
        self.season = season
        self.isBirthday = isBirthday
    }

    /// Builds the context for `now`. `regionCode` (ISO 3166, e.g. "DE") widens the Christmas window
    /// to include Dec 24 where that is the main celebration.
    public static func make(now: Date, dateOfBirth: Date?, calendar: Calendar, regionCode: String?) -> MochiCalendarContext {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .weekday], from: now)
        let month = parts.month ?? 1
        let day = parts.day ?? 1
        let weekday = parts.weekday ?? 1

        return MochiCalendarContext(
            timeOfDay: timeOfDay(hour: parts.hour ?? 0),
            weekday: weekday,
            isWeekend: weekday == 1 || weekday == 7,
            isMonday: weekday == 2,
            isFriday: weekday == 6,
            holiday: holiday(now: now, year: parts.year ?? 1970, month: month, day: day,
                             calendar: calendar, regionCode: regionCode),
            season: season(month: month),
            isBirthday: isBirthday(month: month, day: day, year: parts.year ?? 1970,
                                   dateOfBirth: dateOfBirth, calendar: calendar)
        )
    }

    /// Easter Sunday (start of day) via the Anonymous Gregorian algorithm.
    public static func easterSunday(year: Int, calendar: Calendar) -> Date {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    /// The context as tags that dialogue lines filter on.
    public var tags: Set<String> {
        var result: Set<String> = [
            "time:\(timeOfDay.rawValue)",
            "weekday:\(weekday)",
            "season:\(season.rawValue)"
        ]
        if isWeekend { result.insert("weekend") }
        if isMonday { result.insert("monday") }
        if isFriday { result.insert("friday") }
        if let holiday { result.insert("holiday:\(holiday.rawValue)") }
        if isBirthday { result.insert("birthday") }
        return result
    }

    private static func timeOfDay(hour: Int) -> TimeOfDay {
        switch hour {
        case 4..<7: return .earlyMorning
        case 7..<11: return .morning
        case 11..<14: return .midday
        case 14..<18: return .afternoon
        case 18..<22: return .evening
        default: return .night
        }
    }

    private static func season(month: Int) -> Season {
        switch month {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .autumn
        default: return .winter
        }
    }

    private static func holiday(now: Date, year: Int, month: Int, day: Int,
                                calendar: Calendar, regionCode: String?) -> Holiday? {
        if month == 12 {
            let christmasStart = ["DE", "AT", "CH"].contains(regionCode?.uppercased() ?? "") ? 24 : 25
            if (christmasStart...26).contains(day) { return .christmas }
            if day == 31 { return .newYear }
        }
        if month == 1 && day == 1 { return .newYear }

        // Good Friday (Easter - 2 days) through Easter Monday (Easter + 1 day).
        let easter = easterSunday(year: year, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        if let start = calendar.date(byAdding: .day, value: -2, to: easter),
           let end = calendar.date(byAdding: .day, value: 1, to: easter),
           today >= start, today <= end {
            return .easter
        }
        return nil
    }

    /// Compares month and day only; a Feb 29 birthday is celebrated on Feb 28 in non-leap years.
    private static func isBirthday(month: Int, day: Int, year: Int, dateOfBirth: Date?, calendar: Calendar) -> Bool {
        guard let dateOfBirth else { return false }
        let dob = calendar.dateComponents([.month, .day], from: dateOfBirth)
        guard let dobMonth = dob.month, var dobDay = dob.day else { return false }
        if dobMonth == 2, dobDay == 29 {
            let isLeap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            if !isLeap { dobDay = 28 }
        }
        return dobMonth == month && dobDay == day
    }
}
