import XCTest
@testable import MyOpenScaleCore

final class MochiReactionEngineTests: XCTestCase {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// 2026-10-18 07:00 UTC.
    private let base = Date(timeIntervalSince1970: 1_792_306_800)

    private func lose(_ target: Double, start: Double) -> WeightGoal {
        WeightGoal(type: .lose, targetKg: target, startKg: start)
    }

    private func gain(_ target: Double, start: Double) -> WeightGoal {
        WeightGoal(type: .gain, targetKg: target, startKg: start)
    }

    private func s(daysAgo: Int, _ kg: Double) -> WeightSample {
        WeightSample(id: UUID(), date: base.addingTimeInterval(-Double(daysAgo) * 86_400), weightKg: kg)
    }

    private func react(
        _ kg: Double,
        history: [WeightSample],
        goal: WeightGoal,
        state: MochiProgressState? = nil
    ) -> (MochiReaction, MochiProgressState) {
        MochiReactionEngine.react(
            newKg: kg, at: base, history: history, goal: goal,
            state: state ?? .fresh(for: goal), calendar: cal
        )
    }

    func testFirstEverWeighInIsThumbsUp() {
        let (r, _) = react(80, history: [], goal: lose(70, start: 80))
        XCTAssertEqual(r.event, .toward); XCTAssertEqual(r.pose, .thumbsUp); XCTAssertFalse(r.isWelcomeBack); XCTAssertNil(r.changeKg)
    }

    func testUpDayGetsHugNotShame() {
        let (r, _) = react(80.6, history: [s(daysAgo: 1, 80)], goal: lose(70, start: 80.5))
        XCTAssertEqual(r.event, .away); XCTAssertEqual(r.pose, .selfHug)
    }

    func testGainerUpDayIsToward() {
        let (r, _) = react(60.6, history: [s(daysAgo: 1, 60)], goal: gain(70, start: 60.5))
        XCTAssertEqual(r.event, .toward)
    }

    func testHalfwayMilestoneFiresOnce() {
        var st = MochiProgressState.fresh(for: lose(70, start: 80))
        let (r1, st1) = react(74.9, history: [s(daysAgo: 1, 75.3)], goal: lose(70, start: 80), state: st)
        XCTAssertEqual(r1.event, .milestonePercent(50)); XCTAssertEqual(r1.pose, .confetti)
        st = st1
        let (r2, _) = react(74.8, history: [s(daysAgo: 1, 74.9)], goal: lose(70, start: 80), state: st)
        XCTAssertNotEqual(r2.event, .milestonePercent(50))
    }

    func testGoalReachedBeatsEverything() {
        let (r, _) = react(69.9, history: [s(daysAgo: 1, 70.3)], goal: lose(70, start: 80))
        XCTAssertEqual(r.event, .goalReached)
    }

    func testNoGoalNeverFiresMilestones() {
        let g = WeightGoal(type: .lose, targetKg: nil, startKg: nil)
        let (r, _) = react(70, history: [s(daysAgo: 1, 75)], goal: g)
        XCTAssertFalse([.goalReached, .milestonePercent(50), .milestoneKg(5)].contains(r.event))
    }

    func testChangingGoalResetsProgress() {
        let old = lose(70, start: 80)
        let (_, st) = react(74.9, history: [s(daysAgo: 1, 75.3)], goal: old)
        let newGoal = lose(65, start: 74.9)
        let (r, st2) = react(74.8, history: [s(daysAgo: 1, 74.9)], goal: newGoal, state: st)
        XCTAssertTrue(st.firedMilestones.contains("pct:50"))
        XCTAssertEqual(st2.goalSignature, newGoal.signature())
        XCTAssertFalse(st2.firedMilestones.contains("pct:50"))
        XCTAssertNotEqual(r.event, .milestonePercent(50))
    }

    func testSameDayDuplicateIsIgnoredForChange() {
        // Watch already wrote this weigh-in 20 s earlier.
        let now = base
        let (r, _) = MochiReactionEngine.react(newKg: 79.0, at: now,
            history: [s(daysAgo: 1, 80), WeightSample(id: UUID(), date: now.addingTimeInterval(-20), weightKg: 79.0)],
            goal: lose(70, start: 82), state: .fresh(for: lose(70, start: 82)), calendar: cal)
        XCTAssertEqual(r.changeKg!, -1.0, accuracy: 1e-9)
    }

    func testWelcomeBackWaves() {
        let (r, _) = react(80, history: [s(daysAgo: 9, 80.2)], goal: lose(70, start: 80))
        XCTAssertTrue(r.isWelcomeBack); XCTAssertEqual(r.pose, .helloWave)
    }

    func testStreakCelebratedAtThree() {
        let (r, _) = react(79.9, history: [s(daysAgo: 2, 80.1), s(daysAgo: 1, 80.0)], goal: lose(70, start: 79))
        XCTAssertEqual(r.event, .streak(3))
    }

    func testMaintainReentryIsGoalReached() {
        let g = WeightGoal(type: .maintain, targetKg: 70, startKg: nil)
        var st = MochiProgressState.fresh(for: g)
        (_, st) = react(71.5, history: [s(daysAgo: 1, 71.4)], goal: g, state: st)
        let (r, _) = react(70.8, history: [s(daysAgo: 1, 71.5)], goal: g, state: st)
        XCTAssertEqual(r.event, .goalReached)
    }

    // R2: moving away from the goal never fires a kg milestone.
    func testMovingAwayNeverFiresKgMilestone() {
        let (r, st) = react(82.2, history: [s(daysAgo: 1, 81.0)], goal: lose(70, start: 80))
        XCTAssertEqual(r.event, .away)
        XCTAssertTrue(st.firedMilestones.isEmpty)
    }

    func testKgMilestoneTowardGoal() {
        let (r, st) = react(77.9, history: [s(daysAgo: 1, 78.1)], goal: lose(70, start: 80))
        XCTAssertEqual(r.event, .milestoneKg(2))
        XCTAssertEqual(st.firedMilestones, ["kg:1", "kg:2"])
    }

    func testNotYouLeavesNoTrace() {
        let r = MochiReactionEngine.notYou()
        XCTAssertEqual(r.event, .notYou); XCTAssertEqual(r.pose, .idle); XCTAssertNil(r.changeKg)
        XCTAssertEqual(r.event.lineEvent, "notYou")
    }
}
