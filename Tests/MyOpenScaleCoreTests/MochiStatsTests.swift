import XCTest
@testable import MyOpenScaleCore

final class MochiStatsTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func d(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = s.count > 16 ? "yyyy-MM-dd HH:mm:ss" : "yyyy-MM-dd HH:mm"
        return f.date(from: s)!
    }

    private func s(_ date: String, _ kg: Double) -> WeightSample {
        WeightSample(id: UUID(), date: d(date), weightKg: kg)
    }

    private func stats(_ h: [WeightSample], now: String, goal: WeightGoal = WeightGoal(type: .lose, targetKg: nil, startKg: nil)) -> MochiStats {
        MochiStats.compute(history: h, now: d(now), firstLaunch: d("2026-10-01 00:00"), goal: goal, calendar: cal)
    }

    func testStreakCountsDaysNotReadings() {
        let h = [s("2026-10-16 07:00", 80), s("2026-10-17 07:00", 79.8), s("2026-10-18 07:00", 79.7), s("2026-10-18 07:00:30", 79.7)]
        XCTAssertEqual(stats(h, now: "2026-10-18 20:00").streakDays, 3)
    }

    func testStreakSurvivesUntilTodaysWeighIn() {
        let h = [s("2026-10-16 07:00", 80), s("2026-10-17 07:00", 79.8)]
        XCTAssertEqual(stats(h, now: "2026-10-18 06:00").streakDays, 2)
        XCTAssertEqual(stats(h, now: "2026-10-19 06:00").streakDays, 0)
    }

    func testEmptyHistory() {
        let st = stats([], now: "2026-10-18 06:00")
        XCTAssertEqual(st.streakDays, 0); XCTAssertNil(st.daysSinceLastWeighIn); XCTAssertNil(st.weekChangeKg)
    }

    func testDaysSinceAndWeekChange() {
        let h = [s("2026-10-05 07:00", 81), s("2026-10-08 07:00", 80.6), s("2026-10-13 07:00", 80), s("2026-10-15 07:00", 79.6)]
        let st = stats(h, now: "2026-10-18 09:00")
        XCTAssertEqual(st.daysSinceLastWeighIn, 3)
        XCTAssertEqual(st.weekChangeKg!, (80 + 79.6)/2 - (81 + 80.6)/2, accuracy: 1e-9)
        XCTAssertNil(st.previousWeekChangeKg)
    }

    func testPreviousWeekChange() {
        let h = [s("2026-09-30 07:00", 82), s("2026-10-05 07:00", 81), s("2026-10-13 07:00", 80)]
        let st = stats(h, now: "2026-10-18 09:00")
        XCTAssertEqual(st.weekChangeKg!, 80 - 81, accuracy: 1e-9)
        XCTAssertEqual(st.previousWeekChangeKg!, 81 - 82, accuracy: 1e-9)
    }

    func testDaysUsingApp() {
        XCTAssertEqual(stats([], now: "2026-10-18 09:00").daysUsingApp, 17)
    }

    func testDaysInRangeForMaintain() {
        let g = WeightGoal(type: .maintain, targetKg: 70, startKg: nil)
        let h = [s("2026-10-14 07:00", 72), s("2026-10-15 07:00", 70.5), s("2026-10-17 07:00", 69.6), s("2026-10-18 07:00", 70.2)]
        XCTAssertEqual(stats(h, now: "2026-10-18 09:00", goal: g).daysInRangeStreak, 3)
        XCTAssertEqual(stats(h, now: "2026-10-18 09:00").daysInRangeStreak, 0)
    }
}
