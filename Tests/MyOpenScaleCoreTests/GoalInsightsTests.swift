import XCTest
@testable import MyOpenScaleCore

final class GoalInsightsTests: XCTestCase {

    private let now: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 6; c.day = 30; c.hour = 12
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }()

    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func day(_ offset: Double) -> Date { now.addingTimeInterval(offset * 86_400) }
    private func sample(_ offset: Double, _ kg: Double) -> WeightSample {
        WeightSample(id: UUID(), date: day(offset), weightKg: kg)
    }

    // MARK: - Plan

    private var plan: GoalPlan {
        // 80 → 76 kg over 8 weeks, started 4 weeks ago.
        GoalPlan(startKg: 80, startDate: day(-28), goalKg: 76, targetDate: day(28))
    }

    func testPlanExpectedWeightIsLinearAndClamped() {
        XCTAssertEqual(plan.expectedKg(at: now), 78, accuracy: 1e-9)
        XCTAssertEqual(plan.expectedKg(at: day(-60)), 80, accuracy: 1e-9)
        XCTAssertEqual(plan.expectedKg(at: day(60)), 76, accuracy: 1e-9)
    }

    func testPlanAheadIsPositiveWhenLowerThanPlannedWhileLosing() {
        XCTAssertEqual(plan.aheadKg(trendKg: 77.4, at: now), 0.6, accuracy: 1e-9)
        XCTAssertEqual(plan.aheadKg(trendKg: 79.2, at: now), -1.2, accuracy: 1e-9)
    }

    func testPlanAheadWorksWhenGaining() {
        let gain = GoalPlan(startKg: 60, startDate: day(-28), goalKg: 64, targetDate: day(28))
        XCTAssertEqual(gain.aheadKg(trendKg: 62.5, at: now), 0.5, accuracy: 1e-9)
    }

    func testRequiredWeeklyRate() {
        XCTAssertEqual(plan.requiredWeeklyRateKg(currentKg: 78, now: now)!, -0.5, accuracy: 1e-9)
        XCTAssertNil(plan.requiredWeeklyRateKg(currentKg: 78, now: day(40)))
    }

    func testPlanStatusUsesTolerance() {
        XCTAssertEqual(PlanStatus(aheadKg: 0.3), .onPlan)
        XCTAssertEqual(PlanStatus(aheadKg: 0.8), .ahead(kg: 0.8))
        XCTAssertEqual(PlanStatus(aheadKg: -1.2), .behind(kg: 1.2))
    }

    // MARK: - Milestones

    func testMilestoneStepScalesWithDistance() {
        XCTAssertEqual(GoalInsights.milestoneStepKg(distanceKg: -2), 0.5)
        XCTAssertEqual(GoalInsights.milestoneStepKg(distanceKg: -8), 1)
        XCTAssertEqual(GoalInsights.milestoneStepKg(distanceKg: 20), 2)
    }

    func testMilestonesAreRoundValuesEndingAtGoalWithReachDates() {
        let trend = [sample(-20, 80.3), sample(-10, 79.4), sample(-5, 78.9), sample(0, 78.2)]
        let ms = GoalInsights.milestones(startKg: 80.3, goalKg: 76.5, startDate: day(-21), trend: trend)
        XCTAssertEqual(ms.map(\.kg), [80, 79, 78, 77, 76.5])
        XCTAssertEqual(ms[0].reachedAt, day(-10))   // first ≤ 80
        XCTAssertEqual(ms[1].reachedAt, day(-5))    // first ≤ 79
        XCTAssertNil(ms[2].reachedAt)               // 78 not yet
    }

    func testMilestonesForGainingGoal() {
        let ms = GoalInsights.milestones(startKg: 60, goalKg: 62, startDate: day(-10),
                                         trend: [sample(-5, 60.6), sample(0, 61.1)])
        XCTAssertEqual(ms.map(\.kg), [60.5, 61, 61.5, 62])
        XCTAssertEqual(ms.filter { $0.reachedAt != nil }.count, 2)
    }

    func testNoMilestonesWithoutDistance() {
        XCTAssertTrue(GoalInsights.milestones(startKg: 75, goalKg: 75.1, startDate: now, trend: []).isEmpty)
    }

    // MARK: - Maintenance range

    func testDaysInRangeCountsTrailingStretch() {
        let trend = [sample(-30, 78), sample(-20, 76.8), sample(-10, 75.4), sample(0, 75.2)]
        XCTAssertEqual(GoalInsights.daysInRange(trend: trend, goalKg: 76), 20)
        XCTAssertNil(GoalInsights.daysInRange(trend: trend + [sample(1, 77.5)], goalKg: 76))
    }

    // MARK: - BMI / healthy range

    func testHealthyRangeAndCategories() {
        let r = GoalInsights.healthyWeightRange(heightCm: 180)
        XCTAssertEqual(r.lowerBound, 59.94, accuracy: 0.01)
        XCTAssertEqual(r.upperBound, 81.0, accuracy: 0.01)
        XCTAssertEqual(BMICategory(bmi: 17), .underweight)
        XCTAssertEqual(BMICategory(bmi: 22), .normal)
        XCTAssertEqual(BMICategory(bmi: 27), .overweight)
        XCTAssertEqual(BMICategory(bmi: 31), .obese)
    }

    func testWeightForBMIInvertsTheFormula() {
        XCTAssertEqual(GoalInsights.weightForBMI(25, heightCm: 180), 81, accuracy: 1e-9)
        let w = GoalInsights.weightForBMI(22, heightCm: 175)
        XCTAssertEqual(BodyCompositionCalculator.bmi(weightKg: w, heightCm: 175), 22, accuracy: 1e-9)
    }

    // MARK: - Consistency

    func testWeighInDaysMarksLoggedDays() {
        let s = [sample(0, 80), sample(-0.2, 80.1), sample(-2, 80.2), sample(-20, 81)]
        let days = GoalInsights.weighInDays(s, days: 5, now: now, calendar: utc)
        XCTAssertEqual(days, [false, false, true, false, true])
    }
}
