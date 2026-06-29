import SwiftUI
import Charts
import MiScaleCore

enum ChartRange: String, CaseIterable, Identifiable {
    case d30 = "30D"
    case m6 = "6M"
    case y1 = "1Y"
    var id: String { rawValue }
    var days: Int {
        switch self {
        case .d30: return 30
        case .m6: return 182
        case .y1: return 365
        }
    }
}

/// Interactive weight-history chart (Swift Charts) sourced from Apple Health.
struct WeightChartView: View {
    let history: [WeightSample]

    @State private var range: ChartRange = .d30
    @State private var selectedDate: Date?

    private var samples: [WeightSample] {
        WeightHistory.filter(history, lastDays: range.days, now: Date())
    }

    private var selected: WeightSample? {
        guard let date = selectedDate, samples.count >= 2 else { return nil }
        return samples.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
            Picker("Range", selection: $range) {
                ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
        .glassEffect(in: .rect(cornerRadius: 26))
        .animation(.snappy, value: range)
    }

    private var header: some View {
        HStack {
            Label("Weight history", systemImage: "chart.xyaxis.line")
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            if let s = selected {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(s.weightKg.formatted(1) + " kg").font(.subheadline.weight(.semibold))
                    Text(s.date, format: .dateTime.month().day()).font(.caption2).foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }
        }
    }

    // A weight chart only makes sense with at least two points; 0–1 samples
    // get a friendly prompt instead of a degenerate area mark.
    @ViewBuilder
    private var content: some View {
        if samples.count >= 2 {
            chart
        } else {
            emptyState
        }
    }

    private var chart: some View {
        Chart(samples) { s in
            AreaMark(
                x: .value("Date", s.date),
                yStart: .value("Baseline", yDomain.lowerBound),
                yEnd: .value("Weight", s.weightKg)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                LinearGradient(colors: [Theme.accent.opacity(0.30), Theme.accent.opacity(0.02)],
                               startPoint: .top, endPoint: .bottom)
            )

            LineMark(x: .value("Date", s.date), y: .value("Weight", s.weightKg))
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Theme.accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))

            if let sel = selected {
                RuleMark(x: .value("Date", sel.date))
                    .foregroundStyle(.secondary.opacity(0.4))
                PointMark(x: .value("Date", sel.date), y: .value("Weight", sel.weightKg))
                    .foregroundStyle(Theme.accent)
                    .symbolSize(120)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXSelection(value: $selectedDate)
        .chartYAxis { AxisMarks(position: .leading) }
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
            Text(samples.count == 1 ? "One reading so far" : "No weight data in this range")
                .font(.subheadline.weight(.medium))
            Text(samples.count == 1
                 ? "Weigh in again to start seeing your trend."
                 : "Step on the scale, or add weight in the Health app, and it'll appear here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(.vertical, 8)
    }

    /// Padded domain around the visible samples (never degenerate).
    private var yDomain: ClosedRange<Double> {
        let weights = samples.map(\.weightKg)
        guard let lo = weights.min(), let hi = weights.max() else { return 0...100 }
        let pad = max(1.0, (hi - lo) * 0.15)
        return (lo - pad)...(hi + pad)
    }
}
