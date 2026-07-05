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

    /// Exponential moving average (ascending by date) to smooth daily noise into
    /// a trend line. `alpha` in (0,1]; higher follows the data more closely.
    public static func movingAverage(_ samples: [WeightSample], alpha: Double = 0.25) -> [WeightSample] {
        let sorted = samples.sorted { $0.date < $1.date }
        guard var ema = sorted.first?.weightKg else { return [] }
        return sorted.map { s in
            ema = alpha * s.weightKg + (1 - alpha) * ema
            return WeightSample(id: s.id, date: s.date, weightKg: ema)
        }
    }

    /// Total change (last − first) over the window, or nil with < 2 samples.
    public static func changeKg(_ samples: [WeightSample], lastDays: Int, now: Date) -> Double? {
        let win = filter(samples, lastDays: lastDays, now: now)
        guard win.count >= 2, let first = win.first, let last = win.last else { return nil }
        return last.weightKg - first.weightKg
    }

    /// Least-squares trend slope over the window, expressed as kg per week.
    /// Robust to noise; nil with < 2 samples or no time span.
    public static func weeklyRateKg(_ samples: [WeightSample], lastDays: Int, now: Date) -> Double? {
        let win = filter(samples, lastDays: lastDays, now: now)
        guard win.count >= 2 else { return nil }
        let t0 = win[0].date.timeIntervalSince1970
        let xs = win.map { ($0.date.timeIntervalSince1970 - t0) / 86_400 }
        let ys = win.map(\.weightKg)
        let n = Double(win.count)
        let sx = xs.reduce(0, +), sy = ys.reduce(0, +)
        let sxx = zip(xs, xs).reduce(0) { $0 + $1.0 * $1.1 }
        let sxy = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let denom = n * sxx - sx * sx
        guard abs(denom) > 1e-9 else { return nil }
        return (n * sxy - sx * sy) / denom * 7
    }

    /// Estimated weeks to reach `goalKg` from `currentKg` at the recent weekly
    /// rate. nil when there's no goal, already there, or the trend moves away
    /// from the goal (rate sign doesn't reduce the remaining distance).
    public static func weeksToGoal(currentKg: Double, goalKg: Double, weeklyRateKg rate: Double) -> Double? {
        let remaining = goalKg - currentKg            // signed: negative = need to lose
        guard abs(remaining) >= 0.1, abs(rate) >= 1e-3 else { return nil }
        guard (remaining < 0) == (rate < 0) else { return nil }   // moving toward the goal?
        return remaining / rate
    }
}
