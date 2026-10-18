import Foundation

/// A readable vertical scale for the weight-history chart.
public struct WeightChartAxis: Equatable, Sendable {
    public let domain: ClosedRange<Double>
    public let strideKg: Double

    public init(domain: ClosedRange<Double>, strideKg: Double) {
        self.domain = domain
        self.strideKg = strideKg
    }

    /// Gridline values: every multiple of `strideKg` inside the domain.
    public var ticks: [Double] {
        guard strideKg > 0 else { return [] }
        var values: [Double] = []
        var v = (domain.lowerBound / strideKg).rounded(.up) * strideKg
        while v <= domain.upperBound + 1e-9 {
            values.append(v)
            v += strideKg
        }
        return values
    }
}

/// Time bucket for collapsing raw weigh-ins into chart points.
public enum WeightBucket: Sendable {
    case day
    case week
}

/// Pure, platform-free helpers for the weight-history chart: windowing by time
/// range and trend computation. Kept in the core (like `UserResolver` /
/// `BodyCompositionCalculator`) so it is unit-testable with no simulator.
public enum WeightHistory {

    /// A rounded chart scale that keeps small fluctuations visible without
    /// exaggerating them. The span is at least `minimumSpanKg` (so ±0.3 kg of
    /// daily noise never fills the plot) and otherwise 130% of the observed
    /// spread. Bounds are rounded outward to whole kilograms (half kilograms
    /// for sub-kilogram strides); labels land on 0.5/1/2/5/… kg steps.
    public static func chartAxis(
        for samples: [WeightSample],
        minimumSpanKg: Double = 3
    ) -> WeightChartAxis {
        let weights = samples.map(\.weightKg)
        guard let minimum = weights.min(), let maximum = weights.max() else {
            return WeightChartAxis(domain: 0...100, strideKg: 25)
        }

        let midpoint = (minimum + maximum) / 2
        let desiredSpan = max(minimumSpanKg, (maximum - minimum) * 1.3)
        let niceStrides: [Double] = [0.5, 1, 2, 5, 10, 20, 25, 50]
        let targetStride = desiredSpan / 4
        let stride = niceStrides.first { $0 >= targetStride }
            ?? ceil(targetStride / 50) * 50
        let unit = stride < 1 ? 0.5 : 1
        let lower = floor((midpoint - desiredSpan / 2) / unit) * unit
        let upper = ceil((midpoint + desiredSpan / 2) / unit) * unit
        return WeightChartAxis(domain: lower...upper, strideKg: stride)
    }

    /// Collapses raw weigh-ins into one point per calendar day (or week): the
    /// mean weight, placed at the middle of the bucket. Several readings on the
    /// same morning (or the phone and the watch both saving one) otherwise show
    /// up as a jagged zig-zag. Output is ascending by date; the id is the first
    /// sample's id so SwiftUI identity stays stable across reloads.
    public static func bucketed(
        _ samples: [WeightSample],
        by bucket: WeightBucket = .day,
        calendar: Calendar = .current
    ) -> [WeightSample] {
        let sorted = samples.sorted { $0.date < $1.date }
        var result: [WeightSample] = []
        var currentStart: Date?
        var group: [WeightSample] = []

        func flush() {
            guard let start = currentStart, let first = group.first else { return }
            let mean = group.map(\.weightKg).reduce(0, +) / Double(group.count)
            let length: TimeInterval = bucket == .day ? 86_400 : 7 * 86_400
            result.append(WeightSample(id: first.id, date: start.addingTimeInterval(length / 2), weightKg: mean))
        }

        for s in sorted {
            let start: Date
            switch bucket {
            case .day:
                start = calendar.startOfDay(for: s.date)
            case .week:
                start = calendar.dateInterval(of: .weekOfYear, for: s.date)?.start
                    ?? calendar.startOfDay(for: s.date)
            }
            if start != currentStart {
                flush()
                currentStart = start
                group = []
            }
            group.append(s)
        }
        flush()
        return result
    }

    /// Time-aware exponential moving average (the "Hacker's Diet" trend): each
    /// new reading pulls the trend toward it by `1 − 0.5^(Δdays / halfLife)`,
    /// so gaps between weigh-ins are handled correctly and a single heavy day
    /// barely moves the line. Ascending by date, same count as the input.
    ///
    /// `centered: true` runs the same filter forward and then backward
    /// (zero-phase). A one-way average always trails a steady loss or gain,
    /// which on a chart reads as a line floating above/below its own dots; the
    /// centered version sits in the middle of the readings. Use it for drawing
    /// history, not for "where am I now" numbers.
    public static func trend(
        _ samples: [WeightSample],
        halfLifeDays: Double = 4,
        centered: Bool = false
    ) -> [WeightSample] {
        let sorted = samples.sorted { $0.date < $1.date }
        let forward = ema(sorted, halfLifeDays: halfLifeDays)
        guard centered else { return forward }
        return ema(forward.reversed(), halfLifeDays: halfLifeDays).reversed()
    }

    private static func ema(_ samples: [WeightSample], halfLifeDays: Double) -> [WeightSample] {
        guard let first = samples.first else { return [] }
        var value = first.weightKg
        var lastDate = first.date
        return samples.map { s in
            let days = abs(s.date.timeIntervalSince(lastDate)) / 86_400
            let alpha = 1 - pow(0.5, days / halfLifeDays)
            value += alpha * (s.weightKg - value)
            lastDate = s.date
            return WeightSample(id: s.id, date: s.date, weightKg: value)
        }
    }

    /// Change of the smoothed trend over the last `lastDays` days (latest trend
    /// value minus the trend value at the start of the window). Calmer than raw
    /// last − first, which swings with a single water-heavy morning. nil with
    /// fewer than two daily points in the window.
    public static func trendChangeKg(
        _ samples: [WeightSample],
        lastDays: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> Double? {
        let smoothed = trend(bucketed(samples, by: .day, calendar: calendar))
        let win = filter(smoothed, lastDays: lastDays, now: now)
        guard win.count >= 2, let first = win.first, let last = win.last else { return nil }
        return last.weightKg - first.weightKg
    }

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
