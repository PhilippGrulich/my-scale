import WidgetKit
import SwiftUI
import Charts

// "Progress" widget: several values at once to follow progress — the goal
// ring with kg to go, weight and body values with their 30-day change
// (green when it moves the healthy way), and on the large size the plan
// status and the 30-day trend chart. Everything is prepared by the app in the
// shared `WidgetSnapshot`; values without data simply aren't there.

private let accent = Color(red: 0.13, green: 0.72, blue: 0.55)
private let accent2 = Color(red: 0.20, green: 0.55, blue: 0.85)

struct ProgressEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct ProgressProvider: TimelineProvider {
    private var sample: WidgetSnapshot {
        let now = Date()
        var pts: [WidgetPoint] = []
        for i in 0..<14 {
            let date = now.addingTimeInterval(Double(i - 13) * 2 * 86_400)
            pts.append(WidgetPoint(date: date, weightKg: 81 - Double(i) * 0.08))
        }
        let metrics = [
            WidgetMetric(id: "weight", title: String(localized: "Weight"), symbol: "scalemass.fill",
                         value: 79.9.formatted(.number.precision(.fractionLength(1))), unit: "kg",
                         change: "−1,0 kg", changeIsGood: true),
            WidgetMetric(id: "bodyFat", title: String(localized: "Body Fat"), symbol: "drop.fill",
                         value: 22.4.formatted(.number.precision(.fractionLength(1))), unit: "%",
                         change: "−0,6 %", changeIsGood: true),
            WidgetMetric(id: "muscle", title: String(localized: "Muscle mass"), symbol: "figure.strengthtraining.traditional",
                         value: 58.1.formatted(.number.precision(.fractionLength(1))), unit: "kg",
                         change: "+0,2 kg", changeIsGood: true),
            WidgetMetric(id: "water", title: String(localized: "Body water"), symbol: "drop.circle.fill",
                         value: 54.3.formatted(.number.precision(.fractionLength(1))), unit: "%",
                         change: "+0,3 %", changeIsGood: true),
            WidgetMetric(id: "visceralFat", title: String(localized: "Visceral fat"), symbol: "circle.circle.fill",
                         value: "11", unit: "", change: "−1", changeIsGood: true),
        ]
        return WidgetSnapshot(weightKg: 79.9, date: now, trendDeltaKg: -0.2, goalKg: 76, points: pts,
                              trendPoints: pts, monthTrendKg: -1.0, axisLowerKg: 79, axisUpperKg: 82,
                              goalProgress: 0.35, metrics: metrics, goalStatus: String(localized: "On plan"))
    }
    func placeholder(in context: Context) -> ProgressEntry { ProgressEntry(date: Date(), snapshot: sample) }
    func getSnapshot(in context: Context, completion: @escaping (ProgressEntry) -> Void) {
        let stored = WidgetSnapshotStore.read()
        completion(ProgressEntry(date: Date(), snapshot: stored?.metrics == nil ? sample : stored))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ProgressEntry>) -> Void) {
        let next = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400 + 60)
        completion(Timeline(entries: [ProgressEntry(date: Date(), snapshot: WidgetSnapshotStore.read())],
                            policy: .after(next)))
    }
}

struct ProgressWidgetView: View {
    var entry: ProgressEntry
    @Environment(\.widgetFamily) private var family

    private var s: WidgetSnapshot? { entry.snapshot }
    private var metrics: [WidgetMetric] { s?.metrics ?? [] }

    var body: some View {
        if let s {
            switch family {
            case .systemLarge: large(s)
            default: medium(s)
            }
        } else {
            Text("Weigh in to see your progress.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Sizes

    private func medium(_ s: WidgetSnapshot) -> some View {
        HStack(spacing: 14) {
            if s.goalKg != nil, s.goalProgress != nil {
                ring(s, size: 96, line: 10)
            }
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(metrics.prefix(3).enumerated()), id: \.offset) { _, m in
                    metricRow(m)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func large(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
            HStack(alignment: .center, spacing: 16) {
                if s.goalKg != nil, s.goalProgress != nil {
                    VStack(spacing: 6) {
                        ring(s, size: 104, line: 11)
                        if let status = s.goalStatus {
                            Text(status)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(accent)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(metrics.prefix(5).enumerated()), id: \.offset) { _, m in
                        metricRow(m)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            trendChart(s)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Pieces

    private func ring(_ s: WidgetSnapshot, size: CGFloat, line: CGFloat) -> some View {
        let progress = min(1, max(0, s.goalProgress ?? 0))
        let toGo = abs(s.weightKg - (s.goalKg ?? s.weightKg))
        return ZStack {
            Circle().stroke(accent.opacity(0.15), lineWidth: line)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(AngularGradient(colors: [accent2, accent], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360 * max(0.05, progress))),
                        style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(toGo.formatted(.number.precision(.fractionLength(1))))
                    .font(.system(size: size * 0.26, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .privacySensitive()
                Text("kg to go")
                    .font(.system(size: size * 0.1, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }

    private func metricRow(_ m: WidgetMetric) -> some View {
        HStack(spacing: 8) {
            Image(systemName: m.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(m.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(m.value).font(.subheadline.weight(.bold).monospacedDigit())
                    if !m.unit.isEmpty {
                        Text(m.unit).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .privacySensitive()
            }
            Spacer(minLength: 4)
            if let change = m.change {
                Text(change)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(m.changeIsGood == nil ? Color.secondary
                                     : (m.changeIsGood == true ? accent : .orange))
                    .lineLimit(1)
                    .privacySensitive()
            }
        }
    }

    @ViewBuilder
    private func trendChart(_ s: WidgetSnapshot) -> some View {
        let trend = s.trendPoints ?? []
        if trend.count >= 2, let lo = s.axisLowerKg, let hi = s.axisUpperKg, lo < hi {
            Chart {
                ForEach(trend, id: \.date) { p in
                    AreaMark(x: .value("Date", p.date), yStart: .value("Baseline", lo), yEnd: .value("Weight", p.weightKg))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [accent.opacity(0.25), accent.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Date", p.date), y: .value("Weight", p.weightKg))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
                if let goal = s.goalKg, (lo...hi).contains(goal) {
                    RuleMark(y: .value("Goal", goal))
                        .foregroundStyle(accent2.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
            }
            .chartYScale(domain: lo...hi)
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
            .frame(maxHeight: .infinity)
            .privacySensitive()
        }
    }
}

struct ProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.philippgrulich.myopenscale.progressWidget", provider: ProgressProvider()) { entry in
            ProgressWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Progress")
        .description("Goal progress with weight, body fat and muscle at a glance.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
