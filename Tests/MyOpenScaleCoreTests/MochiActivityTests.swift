import XCTest
@testable import MyOpenScaleCore

final class MochiActivityTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    /// Thursday 2026-10-15 18:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_792_087_200)

    private func workout(_ hoursAgo: Double, minutes: Double = 45, kind: MochiWorkoutKind = .run) -> MochiWorkout {
        let end = now.addingTimeInterval(-hoursAgo * 3600)
        return MochiWorkout(id: UUID().uuidString, start: end.addingTimeInterval(-minutes * 60), end: end,
                            kind: kind, name: "Laufen")
    }

    func testLatestWorkoutTodayGivesTagsAndValues() {
        let ctx = MochiActivityContext.make(workouts: [workout(30), workout(2, minutes: 40)],
                                            stepsByDay: [:], now: now, calendar: cal)
        XCTAssertTrue(ctx.latestIsToday)
        XCTAssertTrue(ctx.recentWithin24h)
        XCTAssertEqual(ctx.tags, ["workout:today", "workout:run"])
        XCTAssertEqual(ctx.values(formatSteps: { "\(Int($0))" }), ["activity": "Laufen", "minutes": "40"])
    }

    func testYesterdayWorkoutAndWeekCount() {
        let ws = [workout(20, kind: .strength), workout(50), workout(100), workout(150)]
        let ctx = MochiActivityContext.make(workouts: ws, stepsByDay: [:], now: now, calendar: cal)
        XCTAssertFalse(ctx.latestIsToday)
        XCTAssertTrue(ctx.recentWithin24h)
        XCTAssertEqual(ctx.workoutsLast7Days, 4)
        XCTAssertEqual(ctx.tags, ["workout:yesterday", "workout:strength", "workout:week"])
    }

    func testOldWorkoutIsNotMentioned() {
        let ctx = MochiActivityContext.make(workouts: [workout(60)], stepsByDay: [:], now: now, calendar: cal)
        XCTAssertNil(ctx.latest)
        XCTAssertFalse(ctx.recentWithin24h)
        XCTAssertTrue(ctx.tags.isEmpty)
    }

    func testFutureWorkoutIgnored() {
        let ctx = MochiActivityContext.make(workouts: [workout(-2)], stepsByDay: [:], now: now, calendar: cal)
        XCTAssertNil(ctx.latest)
    }

    func testBigStepDayPrefersToday() {
        let today = cal.startOfDay(for: now)
        let yesterday = today.addingTimeInterval(-86_400)
        var ctx = MochiActivityContext.make(workouts: [], stepsByDay: [today: 4_000, yesterday: 14_500],
                                            now: now, calendar: cal)
        XCTAssertEqual(ctx.bigStepDay?.isToday, false)
        XCTAssertEqual(ctx.tags, ["steps:yesterday"])
        XCTAssertEqual(ctx.values(formatSteps: { "\(Int($0))" })["steps"], "14500")
        ctx = MochiActivityContext.make(workouts: [], stepsByDay: [today: 11_000, yesterday: 14_500],
                                        now: now, calendar: cal)
        XCTAssertEqual(ctx.tags, ["steps:today"])
    }
}
