import XCTest
@testable import MyOpenScaleCore

final class MochiCalendarContextTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private func date(_ s: String) -> Date { formatter.date(from: s)! }
    private func ymd(_ d: Date) -> String { String(formatter.string(from: d).prefix(10)) }

    private func make(_ now: String, dob: String? = nil, region: String? = nil) -> MochiCalendarContext {
        MochiCalendarContext.make(now: date(now), dateOfBirth: dob.map(date), calendar: cal, regionCode: region)
    }

    func testEasterDates() {
        XCTAssertEqual(ymd(MochiCalendarContext.easterSunday(year: 2026, calendar: cal)), "2026-04-05")
        XCTAssertEqual(ymd(MochiCalendarContext.easterSunday(year: 2027, calendar: cal)), "2027-03-28")
    }

    func testMondayMorning() {
        let c = make("2026-10-19 07:30", region: "DE")
        XCTAssertTrue(c.isMonday); XCTAssertFalse(c.isWeekend)
        XCTAssertEqual(c.timeOfDay, .morning); XCTAssertEqual(c.season, .autumn)
        XCTAssertTrue(c.tags.isSuperset(of: ["monday", "time:morning", "season:autumn", "weekday:2"]))
    }

    func testChristmasEveIsRegional() {
        XCTAssertEqual(make("2026-12-24 10:00", region: "DE").holiday, .christmas)
        XCTAssertNil(make("2026-12-24 10:00", region: "US").holiday)
        XCTAssertEqual(make("2026-12-25 10:00", region: "US").holiday, .christmas)
    }

    func testEasterMondayAndNewYear() {
        XCTAssertEqual(make("2026-04-06 09:00").holiday, .easter)
        XCTAssertEqual(make("2026-04-03 09:00").holiday, .easter)
        XCTAssertNil(make("2026-04-07 09:00").holiday)
        XCTAssertEqual(make("2027-01-01 09:00").holiday, .newYear)
        XCTAssertEqual(make("2026-12-31 23:00").holiday, .newYear)
    }

    func testBirthdayIgnoresYear() {
        let c = make("2026-03-14 08:00", dob: "1990-03-14 00:00")
        XCTAssertTrue(c.isBirthday); XCTAssertTrue(c.tags.contains("birthday"))
        XCTAssertFalse(make("2026-03-15 08:00", dob: "1990-03-14 00:00").isBirthday)
    }

    func testLeapDayBirthdayMatchesFeb28InNonLeapYears() {
        XCTAssertTrue(make("2027-02-28 08:00", dob: "1992-02-29 00:00").isBirthday)
        XCTAssertFalse(make("2028-02-28 08:00", dob: "1992-02-29 00:00").isBirthday)
        XCTAssertTrue(make("2028-02-29 08:00", dob: "1992-02-29 00:00").isBirthday)
    }

    func testTimeOfDayBoundariesAreStartInclusive() {
        XCTAssertEqual(make("2026-10-19 04:00").timeOfDay, .earlyMorning)
        XCTAssertEqual(make("2026-10-19 07:00").timeOfDay, .morning)
        XCTAssertEqual(make("2026-10-19 11:00").timeOfDay, .midday)
        XCTAssertEqual(make("2026-10-19 14:00").timeOfDay, .afternoon)
        XCTAssertEqual(make("2026-10-19 18:00").timeOfDay, .evening)
        XCTAssertEqual(make("2026-10-19 22:00").timeOfDay, .night)
        XCTAssertEqual(make("2026-10-19 03:59").timeOfDay, .night)
    }

    func testNightWrapsMidnight() {
        XCTAssertEqual(make("2026-10-19 02:00").timeOfDay, .night)
    }

    func testWeekendFridayAndSeasonTags() {
        let sat = make("2026-10-17 12:00")
        XCTAssertTrue(sat.isWeekend); XCTAssertTrue(sat.tags.contains("weekend"))
        XCTAssertEqual(sat.weekday, 7)
        XCTAssertTrue(make("2026-10-16 12:00").tags.contains("friday"))
        XCTAssertEqual(make("2026-12-01 12:00").season, .winter)
        XCTAssertEqual(make("2026-03-01 12:00").season, .spring)
        XCTAssertEqual(make("2026-06-01 12:00").season, .summer)
        let h = make("2026-12-25 12:00")
        XCTAssertTrue(h.tags.contains("holiday:christmas"))
        XCTAssertFalse(make("2026-10-19 12:00").tags.contains(where: { $0.hasPrefix("holiday:") || $0 == "birthday" }))
    }
}
