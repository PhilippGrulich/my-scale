import XCTest
@testable import MyOpenScaleCore

final class ReminderPlannerTests: XCTestCase {
    private let berlin: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }()

    private func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = berlin
        f.timeZone = berlin.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }
    private func d(_ s: String) -> Date { formatter("yyyy-MM-dd HH:mm").date(from: s)! }
    private func ymdhm(_ date: Date) -> String { formatter("yyyy-MM-dd HH:mm").string(from: date) }
    private func ymd(_ date: Date) -> String { formatter("yyyy-MM-dd").string(from: date) }
    private func s(_ str: String, _ kg: Double) -> WeightSample {
        WeightSample(id: UUID(), date: d(str), weightKg: kg)
    }

    func testSmartBackoffOffsets() {
        let p = ReminderPlanner.plan(lastWeighIn: d("2026-10-18 07:10"), now: d("2026-10-18 07:15"), mode: .smart, minuteOfDay: 7*60+10, count: 6, calendar: berlin)
        XCTAssertEqual(p.map { ymdhm($0.fireDate) }, ["2026-10-19 07:10", "2026-10-20 07:10", "2026-10-22 07:10", "2026-10-26 07:10", "2026-11-02 07:10", "2026-11-09 07:10"])
        XCTAssertEqual(p.map(\.stage), [.day1, .day2, .day4, .day8, .weekly, .weekly])
    }

    func testSkipsPastReminders() {
        let p = ReminderPlanner.plan(lastWeighIn: d("2026-10-10 07:00"), now: d("2026-10-13 09:00"), mode: .smart, minuteOfDay: 420, count: 2, calendar: berlin)
        XCTAssertEqual(p.map { ymdhm($0.fireDate) }, ["2026-10-14 07:00", "2026-10-18 07:00"])
    }

    func testDSTKeepsWallClockTime() {   // Europe/Berlin falls back on 2026-10-25
        let p = ReminderPlanner.plan(lastWeighIn: d("2026-10-24 07:00"), now: d("2026-10-24 08:00"), mode: .smart, minuteOfDay: 420, count: 2, calendar: berlin)
        XCTAssertEqual(p.map { ymdhm($0.fireDate) }, ["2026-10-25 07:00", "2026-10-26 07:00"])
    }

    func testFixedNeverOnWeighInDayAndOncePerDay() {
        let p = ReminderPlanner.plan(lastWeighIn: d("2026-10-18 06:00"), now: d("2026-10-18 06:05"), mode: .fixed, minuteOfDay: 20*60, count: 3, calendar: berlin)
        XCTAssertEqual(p.map { ymdhm($0.fireDate) }, ["2026-10-19 20:00", "2026-10-20 20:00", "2026-10-21 20:00"])
        XCTAssertEqual(Set(p.map { ymd($0.fireDate) }).count, p.count)
    }

    func testFixedStagesProgress() {
        let p = ReminderPlanner.plan(lastWeighIn: d("2026-10-18 06:00"), now: d("2026-10-18 06:05"), mode: .fixed, minuteOfDay: 20*60, count: 6, calendar: berlin)
        XCTAssertEqual(p.map(\.stage), [.day1, .day2, .day4, .day8, .weekly, .weekly])
    }

    func testSmartOncePerDay() {
        let p = ReminderPlanner.plan(lastWeighIn: d("2026-10-01 07:00"), now: d("2026-10-01 08:00"), mode: .smart, minuteOfDay: 420, count: 8, calendar: berlin)
        XCTAssertEqual(Set(p.map { ymd($0.fireDate) }).count, 8)
    }

    func testSmartNoWeighInEverStartsAtNextOccurrence() {
        // Before today's slot: first reminder today.
        var p = ReminderPlanner.plan(lastWeighIn: nil, now: d("2026-10-18 06:00"), mode: .smart, minuteOfDay: 420, count: 4, calendar: berlin)
        XCTAssertEqual(p.map { ymdhm($0.fireDate) }, ["2026-10-18 07:00", "2026-10-19 07:00", "2026-10-21 07:00", "2026-10-25 07:00"])
        XCTAssertEqual(p.map(\.stage), [.day1, .day2, .day4, .day8])
        // After today's slot: first reminder tomorrow.
        p = ReminderPlanner.plan(lastWeighIn: nil, now: d("2026-10-18 09:00"), mode: .smart, minuteOfDay: 420, count: 2, calendar: berlin)
        XCTAssertEqual(p.map { ymdhm($0.fireDate) }, ["2026-10-19 07:00", "2026-10-20 07:00"])
    }

    func testFixedNoWeighInEverIsDaily() {
        let p = ReminderPlanner.plan(lastWeighIn: nil, now: d("2026-10-18 09:00"), mode: .fixed, minuteOfDay: 420, count: 3, calendar: berlin)
        XCTAssertEqual(p.map { ymdhm($0.fireDate) }, ["2026-10-19 07:00", "2026-10-20 07:00", "2026-10-21 07:00"])
    }

    func testLineEvents() {
        XCTAssertEqual(ReminderStage.allCases.map(\.lineEvent).sorted(), ["reminder1", "reminder2", "reminder4", "reminder8", "reminderWeekly"])
    }

    func testUsualTimeIsCircularMedian() {
        let h = ["2026-10-14 23:50", "2026-10-15 23:55", "2026-10-16 00:05", "2026-10-17 00:10", "2026-10-18 12:00"].map { s($0, 80) }
        let m = ReminderPlanner.usualMinuteOfDay(history: h, calendar: berlin)!
        XCTAssertTrue(m >= 23*60+50 || m <= 10, "got \(m)")
    }

    func testUsualTimeEmpty() { XCTAssertNil(ReminderPlanner.usualMinuteOfDay(history: [], calendar: berlin)) }
}
