import Foundation

/// Pure, platform-free helpers for the weight-history chart: windowing by time
/// range and trend computation. Kept in the core (like `UserResolver` /
/// `BodyCompositionCalculator`) so it is unit-testable with no simulator.
public enum WeightHistory {

    /// Samples within the last `lastDays` days of `now`, sorted ascending by
    /// date (chart-friendly). The lower bound is inclusive.
    public static func filter(_ samples: [WeightSample], lastDays: Int, now: Date) -> [WeightSample] {
        let cutoff = now.addingTimeInterval(-Double(lastDays) * 86_400)
        return samples
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
    }

    /// Change from the previous reading to the latest one (latest − previous),
    /// in kg. Negative means weight went down. Returns nil with fewer than two
    /// samples. Input need not be pre-sorted.
    public static func trendDeltaKg(_ samples: [WeightSample]) -> Double? {
        guard samples.count >= 2 else { return nil }
        let sorted = samples.sorted { $0.date < $1.date }
        return sorted[sorted.count - 1].weightKg - sorted[sorted.count - 2].weightKg
    }
}
