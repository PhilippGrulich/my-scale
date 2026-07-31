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

    func testChartAxisGivesStableReadingsAtLeastSixKilograms() {
        let axis = WeightHistory.chartAxis(for: [
            sample(daysAgo: 2, kg: 79.8),
            sample(daysAgo: 1, kg: 80.2),
        ])
        XCTAssertGreaterThanOrEqual(axis.domain.upperBound - axis.domain.lowerBound, 6)
        XCTAssertLessThanOrEqual(axis.domain.lowerBound, 79.8)
        XCTAssertGreaterThanOrEqual(axis.domain.upperBound, 80.2)
        XCTAssertEqual(axis.strideKg, 2)
    }

    func testChartAxisCentersIdenticalReadingsWithoutDegenerating() {
        let axis = WeightHistory.chartAxis(for: [
            sample(daysAgo: 2, kg: 80),
            sample(daysAgo: 1, kg: 80),
        ])
        XCTAssertEqual(axis.domain, 77...83)
    }

    func testChartAxisPadsLargeSpreadAndRoundsOutward() {
        let axis = WeightHistory.chartAxis(for: [
            sample(daysAgo: 2, kg: 70.4),
            sample(daysAgo: 1, kg: 80.6),
        ])
        XCTAssertEqual(axis.domain, 68...83)
        XCTAssertEqual(axis.strideKg, 5)
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
