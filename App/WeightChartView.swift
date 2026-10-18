import SwiftUI
import Charts
import MyOpenScaleCore

enum ChartRange: String, CaseIterable, Identifiable {
    case d30 = "30D"
    case m6 = "6M"
    case y1 = "1Y"
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .d30: return "30D"
        case .m6: return "6M"
        case .y1: return "1Y"
        }
    }
    var days: Int {
        switch self {
        case .d30: return 30
        case .m6: return 182
        case .y1: return 365
        }
    }
    /// Longer ranges smooth harder: a 3-day half-life is right for spotting a
    /// week-to-week change, but reads as wobble on a year-long axis.
    var trendHalfLifeDays: Double {
        switch self {
        case .d30: return 3
        case .m6: return 6
        case .y1: return 10
        }
    }
}

/// Interactive weight-history chart (Swift Charts) sourced from Apple Health.
struct WeightChartView: View {
    let history: [WeightSample]
    var goalKg: Double? = nil
    /// Tapping the header title opens the full measurement list.
    var onShowHistory: (() -> Void)? = nil

    @State private var range: ChartRange = .d30
    @State private var selectedDate: Date?

    /// One dot per day (per week on the 1Y range) so repeated weigh-ins don't
    /// draw a zig-zag.
    private var points: [WeightSample] {
        let bucket: WeightBucket = range == .y1 ? .week : .day
        return WeightHistory.filter(WeightHistory.bucketed(history, by: bucket), lastDays: range.days, now: Date())
    }

    /// Smoothed trend, computed over the *whole* history and then windowed, so
    /// the line doesn't restart from a noisy first reading at the range edge.
    /// Centered (zero-phase) so it runs through the dots instead of lagging.
    private var trend: [WeightSample] {
        WeightHistory.filter(WeightHistory.trend(WeightHistory.bucketed(history, by: .day),
                                                   halfLifeDays: range.trendHalfLifeDays, centered: true),
                             lastDays: range.days, now: Date())
    }

    private var yAxis: WeightChartAxis {
        WeightHistory.chartAxis(for: points + trend)
    }

    private var selected: WeightSample? {
        guard let date = selectedDate, points.count >= 2 else { return nil }
        return points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    private var selectedTrend: WeightSample? {
        guard let date = selected?.date else { return nil }
        return trend.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
            Picker("Range", selection: $range) {
                ForEach(ChartRange.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
        .glassEffect(in: .rect(cornerRadius: 26))
        .animation(.snappy, value: range)
    }

    private var header: some View {
        HStack {
            Button { onShowHistory?() } label: {
                HStack(spacing: 4) {
                    Label("Weight history", systemImage: "chart.xyaxis.line")
                    if onShowHistory != nil {
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.headline)
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .disabled(onShowHistory == nil)
            .accessibilityHint("Shows all measurements")
            Spacer()
            if let s = selected {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(s.weightKg.formatted(1) + " kg").font(.subheadline.weight(.semibold))
                    HStack(spacing: 4) {
                        if let t = selectedTrend {
                            Text("Trend \(t.weightKg.formatted(1))")
                                .foregroundStyle(Theme.accent)
                        }
                        Text(s.date, format: range == .y1 ? .dateTime.month().day().year(.twoDigits)
                                                           : .dateTime.month().day())
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption2)
                }
                .transition(.opacity)
            } else if trend.count >= 2, let first = trend.first, let last = trend.last {
                let delta = last.weightKg - first.weightKg
                Text("Trend \(delta >= 0 ? "+" : "−")\(abs(delta).formatted(1)) kg")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: delta))
            }
        }
    }

    // A weight chart only makes sense with at least two points; 0–1 samples
    // get a friendly prompt instead of a degenerate area mark.
    @ViewBuilder
    private var content: some View {
        if points.count >= 2 {
            chart
        } else {
            emptyState
        }
    }

    // The smoothed trend is the hero line; raw weigh-ins are small dots around
    // it. Daily ±0.5 kg water swings then read as scatter instead of a jagged
    // curve, while real drift shows up as a clear slope. Monotone interpolation
    // never overshoots between points (catmull-rom invented bumps that weren't
    // in the data).
    private var chart: some View {
        Chart {
            ForEach(trend) { t in
                AreaMark(
                    x: .value("Date", t.date),
                    yStart: .value("Baseline", yAxis.domain.lowerBound),
                    yEnd: .value("Trend", t.weightKg)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(colors: [Theme.accent.opacity(0.22), Theme.accent.opacity(0.02)],
                                   startPoint: .top, endPoint: .bottom)
                )

                LineMark(x: .value("Date", t.date), y: .value("Trend", t.weightKg),
                         series: .value("Series", "Trend"))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }

            ForEach(points) { p in
                PointMark(x: .value("Date", p.date), y: .value("Weight", p.weightKg))
                    .foregroundStyle(Theme.accent.opacity(0.45))
                    .symbolSize(range == .d30 ? 28 : 12)
            }

            if let goalKg, yAxis.domain.contains(goalKg) {
                RuleMark(y: .value("Goal", goalKg))
                    .foregroundStyle(Theme.accentSecondary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Goal \(goalKg.formatted(1)) kg")
                            .font(.caption2).foregroundStyle(Theme.accentSecondary)
                    }
            }

            if let sel = selected {
                RuleMark(x: .value("Date", sel.date))
                    .foregroundStyle(.secondary.opacity(0.4))
                PointMark(x: .value("Date", sel.date), y: .value("Weight", sel.weightKg))
                    .foregroundStyle(Theme.accent)
                    .symbolSize(110)
            }
        }
        .chartYScale(domain: yAxis.domain)
        .chartXSelection(value: $selectedDate)
        .chartYAxis {
            AxisMarks(position: .leading, values: yAxis.ticks) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let kg = value.as(Double.self) {
                        Text(kg.formatted(yAxis.strideKg < 1 ? 1 : 0))
                    }
                }
            }
        }
        .chartXAxis { AxisMarks(preset: .aligned) }
        .frame(height: 200)
        .chartPlotStyle { plot in plot.clipped() }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "scalemass")
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.accent)
            Text(points.count == 1 ? "One reading so far" : "No weight data in this range")
                .font(.subheadline.weight(.medium))
            Text(points.count == 1
                 ? "Weigh in again to start seeing your trend."
                 : "Step on the scale, or add weight in the Health app, and it'll appear here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(.vertical, 8)
    }
}
