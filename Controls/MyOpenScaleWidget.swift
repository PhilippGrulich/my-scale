import WidgetKit
import SwiftUI
import Charts

// Home / Lock Screen widget: latest weight, 30-day trend, when it was measured,
// a chart in the same style as the app (daily dots + smoothed trend on the
// app's calm axis), and goal progress on the round Lock Screen widget. Reads
// the snapshot the app writes via `WidgetSnapshotStore` (Shared); the app does
// all the maths so this extension stays small. Weight is health data, so it's
// marked privacy-sensitive and redacted while the device is locked.

private let widgetAccent = Color(red: 0.13, green: 0.72, blue: 0.55)
private let widgetAccent2 = Color(red: 0.20, green: 0.55, blue: 0.85)

struct WeightEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct WeightProvider: TimelineProvider {
    private var sample: WidgetSnapshot {
        let now = Date()
        var pts: [WidgetPoint] = []
        var trend: [WidgetPoint] = []
        for i in 0..<14 {
            let date = now.addingTimeInterval(Double(i - 13) * 2 * 86_400)
            let base: Double = 81 - Double(i) * 0.08
            let noise: Double = i % 3 == 0 ? 0.3 : -0.1
            pts.append(WidgetPoint(date: date, weightKg: base + noise))
            trend.append(WidgetPoint(date: date, weightKg: base))
        }
        return WidgetSnapshot(weightKg: 79.9, date: now, trendDeltaKg: -0.2, goalKg: 76, points: pts,
                              trendPoints: trend, monthTrendKg: -1.0, axisLowerKg: 79, axisUpperKg: 82,
                              goalProgress: 0.35)
    }
    func placeholder(in context: Context) -> WeightEntry { WeightEntry(date: Date(), snapshot: sample) }
    func getSnapshot(in context: Context, completion: @escaping (WeightEntry) -> Void) {
        completion(WeightEntry(date: Date(), snapshot: WidgetSnapshotStore.read() ?? sample))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WeightEntry>) -> Void) {
        // The app pushes refreshes via WidgetCenter on each weigh-in / goal
        // change. A daily refresh keeps the "measured …" text honest anyway.
        let next = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400 + 60)
        completion(Timeline(entries: [WeightEntry(date: Date(), snapshot: WidgetSnapshotStore.read())],
                            policy: .after(next)))
    }
}

struct MyOpenScaleWidgetView: View {
    var entry: WeightEntry
    @Environment(\.widgetFamily) private var family

    private var s: WidgetSnapshot? { entry.snapshot }

    private var weightText: String {
        guard let s else { return "—" }
        return s.weightKg.formatted(.number.precision(.fractionLength(1)))
    }

    /// The 30-day trend (falls back to the change since the last weigh-in for
    /// snapshots written by an older app build).
    private var change: Double? { s?.monthTrendKg ?? s?.trendDeltaKg }

    @ViewBuilder
    private var changeLabel: some View {
        if let d = change {
            let flat = abs(d) < 0.05
            Label {
                Text("\(abs(d).formatted(.number.precision(.fractionLength(1)))) kg / 30d")
            } icon: {
                Image(systemName: flat ? "arrow.right" : (d < 0 ? "arrow.down.right" : "arrow.up.right"))
            }
            .privacySensitive()
        }
    }

    @ViewBuilder
    private var measuredLabel: some View {
        if let s {
            if Calendar.current.isDateInToday(s.date) {
                Text("Today")
            } else {
                Text(s.date, format: .relative(presentation: .named))
            }
        }
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label {
                Text("\(weightText) kg").privacySensitive()
            } icon: {
                Image(systemName: "scalemass")
            }
        case .accessoryCircular:
            circularBody
        case .accessoryRectangular:
            rectangularBody
        case .systemMedium:
            mediumBody
        case .systemLarge:
            largeBody
        default:
            smallBody
        }
    }

    // MARK: - Lock Screen

    private var rectangularBody: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("Weight", systemImage: "scalemass").font(.caption2.weight(.semibold))
            Text("\(weightText) kg")
                .font(.title3.weight(.bold))
                .privacySensitive()
            changeLabel.font(.caption2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Goal progress ring with the kilos to go; without a goal just the weight.
    @ViewBuilder
    private var circularBody: some View {
        if let s, let goal = s.goalKg, let progress = s.goalProgress {
            Gauge(value: progress) {
                Image(systemName: "target")
            } currentValueLabel: {
                Text(abs(s.weightKg - goal).formatted(.number.precision(.fractionLength(1))))
                    .privacySensitive()
            }
            .gaugeStyle(.accessoryCircularCapacity)
        } else {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text(weightText).font(.headline).minimumScaleFactor(0.6).privacySensitive()
                    Text("kg").font(.caption2)
                }
            }
        }
    }

    // MARK: - Home Screen

    private var header: some View {
        Label("Weight", systemImage: "scalemass.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(widgetAccent)
    }

    private var bigWeight: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(weightText)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .privacySensitive()
            Text("kg").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
        }
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            Spacer(minLength: 0)
            bigWeight
            changeLabel
                .font(.caption.weight(.medium))
                .foregroundStyle(widgetAccent)
            measuredLabel
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var mediumBody: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                header
                Spacer(minLength: 0)
                bigWeight
                changeLabel
                    .font(.caption.weight(.medium))
                    .foregroundStyle(widgetAccent)
                measuredLabel
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxHeight: .infinity, alignment: .leading)
            chart(showAxis: false)
        }
    }

    private var largeBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                header
                Spacer()
                measuredLabel
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            bigWeight
            changeLabel
                .font(.subheadline.weight(.medium))
                .foregroundStyle(widgetAccent)
            chart(showAxis: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - Chart

    @ViewBuilder
    private func chart(showAxis: Bool) -> some View {
        let points = s?.points ?? []
        let trend = s?.trendPoints ?? []
        if points.count >= 2 {
            let domain = yDomain(points + trend)
            Chart {
                ForEach(trend, id: \.date) { p in
                    AreaMark(x: .value("Date", p.date),
                             yStart: .value("Baseline", domain.lowerBound),
                             yEnd: .value("Weight", p.weightKg))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [widgetAccent.opacity(0.25), widgetAccent.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Date", p.date), y: .value("Weight", p.weightKg))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(widgetAccent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
                ForEach(points, id: \.date) { p in
                    PointMark(x: .value("Date", p.date), y: .value("Weight", p.weightKg))
                        .foregroundStyle(widgetAccent.opacity(0.45))
                        .symbolSize(14)
                }
                if let goal = s?.goalKg, domain.contains(goal) {
                    RuleMark(y: .value("Goal", goal))
                        .foregroundStyle(widgetAccent2.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
            }
            .chartYScale(domain: domain)
            .chartXAxis(showAxis ? .automatic : .hidden)
            .chartYAxis(showAxis ? .automatic : .hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .privacySensitive()
        } else {
            Text("Weigh in to see your trend.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    /// The app's axis when the snapshot has it; otherwise a padded fallback.
    /// The goal never stretches the axis (a far goal would flatten the curve).
    private func yDomain(_ points: [WidgetPoint]) -> ClosedRange<Double> {
        if let lo = s?.axisLowerKg, let hi = s?.axisUpperKg, lo < hi { return lo...hi }
        let ws = points.map(\.weightKg)
        guard let lo = ws.min(), let hi = ws.max() else { return 0...100 }
        let pad = max(1.5, (hi - lo) * 0.15)
        return (lo - pad)...(hi + pad)
    }
}

struct MyOpenScaleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.philippgrulich.myopenscale.weightWidget", provider: WeightProvider()) { entry in
            MyOpenScaleWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Weight")
        .description("Your latest weight, trend, and chart.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}
