import XCTest
@testable import MiScaleCore

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
