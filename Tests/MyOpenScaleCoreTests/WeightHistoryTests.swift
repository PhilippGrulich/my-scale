import XCTest
@testable import MyOpenScaleCore

final class WeightHistoryTests: XCTestCase {

    // Fixed reference instant so the day-window math is deterministic.
    private let now: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 6; c.day = 30; c.hour = 12
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }()

    private func sample(daysAgo: Double, kg: Double) -> WeightSample {
        WeightSample(id: UUID(), date: now.addingTimeInterval(-daysAgo * 86_400), weightKg: kg)
    }

    // MARK: - chart axis

    func testChartAxisUsesSafeFallbackForEmptySamples() {
        let axis = WeightHistory.chartAxis(for: [])
        XCTAssertEqual(axis.domain, 0...100)
        XCTAssertEqual(axis.strideKg, 25)
    }

    func testChartAxisGivesStableReadingsAtLeastThreeKilograms() {
        let axis = WeightHistory.chartAxis(for: [
            sample(daysAgo: 2, kg: 79.8),
            sample(daysAgo: 1, kg: 80.2),
        ])
        XCTAssertEqual(axis.domain, 78...82)
        XCTAssertEqual(axis.strideKg, 1)
        XCTAssertEqual(axis.ticks, [78, 79, 80, 81, 82])
    }

    func testChartAxisCentersIdenticalReadingsWithoutDegenerating() {
        let axis = WeightHistory.chartAxis(for: [
            sample(daysAgo: 2, kg: 80),
            sample(daysAgo: 1, kg: 80),
        ])
        XCTAssertEqual(axis.domain, 78...82)
    }

    func testChartAxisMakesOneKilogramDriftVisible() {
        // A slow 1 kg drift with ±0.3 kg noise should use a meaningful share of
        // the plot height (old 6 kg minimum squashed it to a flat line).
        let axis = WeightHistory.chartAxis(for: [
            sample(daysAgo: 20, kg: 81.3), sample(daysAgo: 10, kg: 80.6), sample(daysAgo: 1, kg: 80.0),
        ])
        let span = axis.domain.upperBound - axis.domain.lowerBound
        XCTAssertLessThanOrEqual(span, 4)
        XCTAssertTrue(axis.domain.contains(81.3) && axis.domain.contains(80.0))
    }

    func testChartAxisPadsLargeSpreadAndRoundsOutward() {
        let axis = WeightHistory.chartAxis(for: [
            sample(daysAgo: 2, kg: 70.4),
            sample(daysAgo: 1, kg: 80.6),
        ])
        XCTAssertEqual(axis.domain, 68...83)
        XCTAssertEqual(axis.strideKg, 5)
        XCTAssertEqual(axis.ticks, [70, 75, 80])
    }

    // MARK: - bucketing / trend

    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    func testBucketedAveragesSameDayReadings() {
        // Two weigh-ins on the same day (e.g. phone + watch) become one point.
        let s = [sample(daysAgo: 1.1, kg: 80.0), sample(daysAgo: 1.0, kg: 80.6), sample(daysAgo: 0, kg: 79.9)]
        let daily = WeightHistory.bucketed(s, by: .day, calendar: utc)
        XCTAssertEqual(daily.count, 2)
        XCTAssertEqual(daily[0].weightKg, 80.3, accuracy: 1e-9)
        XCTAssertEqual(daily[1].weightKg, 79.9, accuracy: 1e-9)
        XCTAssertEqual(daily[0].id, s[0].id)
    }

    func testBucketedByWeekGroupsSevenDays() {
        let s = (0..<14).map { sample(daysAgo: Double($0), kg: 80) }
        let weekly = WeightHistory.bucketed(s, by: .week, calendar: utc)
        XCTAssertLessThanOrEqual(weekly.count, 3)
        XCTAssertGreaterThanOrEqual(weekly.count, 2)
    }

    func testTrendDampsSingleHeavyDay() {
        let s = [sample(daysAgo: 3, kg: 80), sample(daysAgo: 2, kg: 80),
                 sample(daysAgo: 1, kg: 81), sample(daysAgo: 0, kg: 80)]
        let t = WeightHistory.trend(s)
        XCTAssertEqual(t.count, 4)
        // A +1 kg water day moves the trend by well under half a kilo.
        XCTAssertLessThan(t[2].weightKg, 80.25)
        XCTAssertGreaterThan(t[2].weightKg, 80.0)
    }

    func testTrendCatchesUpFasterAfterLongGap() {
        let short = WeightHistory.trend([sample(daysAgo: 1, kg: 80), sample(daysAgo: 0, kg: 82)])
        let long = WeightHistory.trend([sample(daysAgo: 20, kg: 80), sample(daysAgo: 0, kg: 82)])
        XCTAssertGreaterThan(long[1].weightKg, short[1].weightKg)
        XCTAssertEqual(long[1].weightKg, 82, accuracy: 0.1)
    }

    func testCenteredTrendDoesNotLagASteadyLoss() {
        // Losing 0.1 kg/day: the one-way trend trails above the data, the
        // centered one tracks it in the middle of the range.
        let s = (0..<60).map { sample(daysAgo: Double(60 - $0), kg: 86 - Double($0) * 0.1) }
        let causal = WeightHistory.trend(s, halfLifeDays: 7)
        let centered = WeightHistory.trend(s, halfLifeDays: 7, centered: true)
        XCTAssertEqual(centered.count, s.count)
        XCTAssertGreaterThan(causal[30].weightKg - s[30].weightKg, 0.5)
        XCTAssertEqual(centered[30].weightKg, s[30].weightKg, accuracy: 0.1)
    }

    func testTrendChangeIgnoresNoisyEndpoint() {
        // Steady 80 kg for a month, then one +1 kg morning: raw change says +1,
        // the trend change stays small.
        var s = (1...30).map { sample(daysAgo: Double($0), kg: 80) }
        s.append(sample(daysAgo: 0, kg: 81))
        XCTAssertEqual(WeightHistory.changeKg(s, lastDays: 30, now: now)!, 1, accuracy: 1e-9)
        let trendChange = WeightHistory.trendChangeKg(s, lastDays: 30, now: now, calendar: utc)!
        XCTAssertLessThan(trendChange, 0.25)
    }

    // MARK: - trends / goal

    func testChangeKgOverWindow() {
        let s = [sample(daysAgo: 28, kg: 82), sample(daysAgo: 14, kg: 81), sample(daysAgo: 1, kg: 80)]
        XCTAssertEqual(WeightHistory.changeKg(s, lastDays: 30, now: now)!, -2, accuracy: 1e-9)
        XCTAssertNil(WeightHistory.changeKg([sample(daysAgo: 1, kg: 80)], lastDays: 30, now: now))
    }

    func testWeeklyRateIsNegativeWhenLosing() {
        // ~1 kg over 14 days ⇒ ~ -0.5 kg/week.
        let s = [sample(daysAgo: 14, kg: 81), sample(daysAgo: 7, kg: 80.5), sample(daysAgo: 0, kg: 80)]
        let rate = WeightHistory.weeklyRateKg(s, lastDays: 30, now: now)!
        XCTAssertEqual(rate, -0.5, accuracy: 0.05)
    }

    func testGoalProgressForLosingAndGaining() {
        XCTAssertEqual(WeightHistory.goalProgress(startKg: 80, currentKg: 78, goalKg: 76)!, 0.5, accuracy: 1e-9)
        XCTAssertEqual(WeightHistory.goalProgress(startKg: 60, currentKg: 61, goalKg: 64)!, 0.25, accuracy: 1e-9)
    }

    func testGoalProgressClampsAndHandlesNoDistance() {
        XCTAssertEqual(WeightHistory.goalProgress(startKg: 80, currentKg: 81, goalKg: 76), 0)   // wrong way
        XCTAssertEqual(WeightHistory.goalProgress(startKg: 80, currentKg: 75, goalKg: 76), 1)   // passed it
        XCTAssertNil(WeightHistory.goalProgress(startKg: 80, currentKg: 80, goalKg: 80))
    }

    func testWeeksToGoalOnlyWhenMovingToward() {
        // Losing 0.5/wk, want to drop 3 kg ⇒ ~6 weeks.
        XCTAssertEqual(WeightHistory.weeksToGoal(currentKg: 80, goalKg: 77, weeklyRateKg: -0.5)!, 6, accuracy: 1e-9)
        // Gaining while goal is below ⇒ never (nil).
        XCTAssertNil(WeightHistory.weeksToGoal(currentKg: 80, goalKg: 77, weeklyRateKg: 0.3))
        // Already at goal ⇒ nil.
        XCTAssertNil(WeightHistory.weeksToGoal(currentKg: 77, goalKg: 77, weeklyRateKg: -0.5))
    }

    func testMovingAverageSmoothsAndPreservesCount() {
        let s = [sample(daysAgo: 4, kg: 80), sample(daysAgo: 3, kg: 84),
                 sample(daysAgo: 2, kg: 80), sample(daysAgo: 1, kg: 84)]
        let ema = WeightHistory.movingAverage(s, alpha: 0.25)
        XCTAssertEqual(ema.count, 4)
        // Spikes are damped: the smoothed series never reaches the raw peak, and
        // stays within the raw range.
        XCTAssertLessThan(ema.map(\.weightKg).max()!, 84)
        XCTAssertTrue(ema.allSatisfy { $0.weightKg >= 80 && $0.weightKg <= 84 })
        XCTAssertLessThan(ema[1].weightKg, 84)   // the first 84 spike is smoothed down
    }

    // MARK: - filter

    func testFilterEmptyReturnsEmpty() {
        XCTAssertEqual(WeightHistory.filter([], lastDays: 30, now: now), [])
    }

    func testFilterKeepsSamplesWithinWindowAndDropsOlder() {
        let recent = sample(daysAgo: 5, kg: 80)
        let old = sample(daysAgo: 40, kg: 85)
        let result = WeightHistory.filter([old, recent], lastDays: 30, now: now)
        XCTAssertEqual(result, [recent])
    }

    func testFilterBoundaryIsInclusive() {
        let onEdge = sample(daysAgo: 30, kg: 82)
        let result = WeightHistory.filter([onEdge], lastDays: 30, now: now)
        XCTAssertEqual(result, [onEdge])
    }

    func testFilterReturnsAscendingByDate() {
        let a = sample(daysAgo: 1, kg: 80)
        let b = sample(daysAgo: 10, kg: 81)
        let c = sample(daysAgo: 3, kg: 82)
        let result = WeightHistory.filter([a, b, c], lastDays: 30, now: now)
        XCTAssertEqual(result.map(\.weightKg), [81, 82, 80]) // b(10d), c(3d), a(1d)
    }

    // MARK: - trendDeltaKg

    func testTrendDeltaNilWhenEmpty() {
        XCTAssertNil(WeightHistory.trendDeltaKg([]))
    }

    func testTrendDeltaNilWhenSingleSample() {
        XCTAssertNil(WeightHistory.trendDeltaKg([sample(daysAgo: 1, kg: 80)]))
    }

    func testTrendDeltaIsLatestMinusPrevious() {
        let prev = sample(daysAgo: 7, kg: 81.0)
        let latest = sample(daysAgo: 1, kg: 80.2)
        let delta = WeightHistory.trendDeltaKg([prev, latest])
        XCTAssertEqual(delta!, -0.8, accuracy: 1e-9)
    }

    func testTrendDeltaSortsByDateBeforeComputing() {
        // Unsorted input: latest is the 1-day-ago sample regardless of order.
        let prev = sample(daysAgo: 7, kg: 81.0)
        let latest = sample(daysAgo: 1, kg: 80.2)
        let delta = WeightHistory.trendDeltaKg([latest, prev])
        XCTAssertEqual(delta!, -0.8, accuracy: 1e-9)
    }
}
