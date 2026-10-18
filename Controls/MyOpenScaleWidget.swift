import WidgetKit
import SwiftUI
import Charts

// Home / Lock Screen widget showing the latest weight + trend (small / accessory)
// and a weight chart (large). Reads the snapshot the app writes via
// `WidgetSnapshotStore` (Shared).

private let widgetAccent = Color(red: 0.13, green: 0.72, blue: 0.55)
private let widgetAccent2 = Color(red: 0.20, green: 0.55, blue: 0.85)

struct WeightEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct WeightProvider: TimelineProvider {
    private var sample: WidgetSnapshot {
        let now = Date()
        let pts = (0..<12).map { i in
            WidgetPoint(date: now.addingTimeInterval(Double(i - 11) * 86_400),
                        weightKg: 81 - Double(i) * 0.1)
        }
        return WidgetSnapshot(weightKg: 79.8, date: now, trendDeltaKg: -0.3, goalKg: 76, points: pts)
    }
    func placeholder(in context: Context) -> WeightEntry { WeightEntry(date: Date(), snapshot: sample) }
    func getSnapshot(in context: Context, completion: @escaping (WeightEntry) -> Void) {
        completion(WeightEntry(date: Date(), snapshot: WidgetSnapshotStore.read() ?? sample))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WeightEntry>) -> Void) {
        // The app pushes refreshes via WidgetCenter on each weigh-in, so one entry
        // with no auto-refresh policy is enough.
        completion(Timeline(entries: [WeightEntry(date: Date(), snapshot: WidgetSnapshotStore.read())], policy: .never))
    }
}

struct MyOpenScaleWidgetView: View {
    var entry: WeightEntry
    @Environment(\.widgetFamily) private var family

    private var weightText: String {
        guard let s = entry.snapshot else { return "—" }
        return s.weightKg.formatted(.number.precision(.fractionLength(1)))
    }
    private var trendText: String? {
        guard let d = entry.snapshot?.trendDeltaKg else { return nil }
        return "\(d <= 0 ? "▼" : "▲") \(abs(d).formatted(.number.precision(.fractionLength(1)))) kg"
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("\(weightText) kg", systemImage: "scalemass")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Weight").font(.caption2).foregroundStyle(.secondary)
                Text("\(weightText) kg").font(.title3.weight(.semibold))
                if let trendText { Text(trendText).font(.caption2) }
            }
        case .systemLarge:
            largeBody
        default:
            smallBody
        }
    }

    private var header: some View {
        Label("Weight", systemImage: "scalemass.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(widgetAccent)
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            Spacer()
            Text("\(weightText) kg")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.7)
            if let trendText {
                Text(trendText).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var largeBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                header
                Spacer()
                if let trendText {
                    Text(trendText).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("\(weightText) kg")
                .font(.system(size: 40, weight: .bold, design: .rounded))
            chart
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var chart: some View {
        let points = entry.snapshot?.points ?? []
        if points.count >= 2 {
            Chart {
                ForEach(points, id: \.date) { p in
                    AreaMark(x: .value("Date", p.date), y: .value("Weight", p.weightKg))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(LinearGradient(colors: [widgetAccent.opacity(0.30), widgetAccent.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Date", p.date), y: .value("Weight", p.weightKg))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(widgetAccent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
                if let goal = entry.snapshot?.goalKg {
                    RuleMark(y: .value("Goal", goal))
                        .foregroundStyle(widgetAccent2.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
            }
            .chartYScale(domain: yDomain(points))
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text("Weigh in to see your trend.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func yDomain(_ points: [WidgetPoint]) -> ClosedRange<Double> {
        var ws = points.map(\.weightKg)
        if let g = entry.snapshot?.goalKg { ws.append(g) }
        guard let lo = ws.min(), let hi = ws.max() else { return 0...100 }
        let pad = max(0.5, (hi - lo) * 0.15)
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
        .supportedFamilies([.systemSmall, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}
