import SwiftUI
import Charts

extension HealthKitSink.MetricKind {
    var systemImage: String {
        switch self { case .bodyFat: return "drop.fill"; case .lean: return "figure.arms.open"; case .bmi: return "ruler.fill" }
    }
    var tint: Color {
        switch self { case .bodyFat: return .orange; case .lean: return Theme.accentSecondary; case .bmi: return Theme.accent }
    }
}

/// History chart for a single body metric (body fat / lean mass / BMI), read
/// from Apple Health on demand.
struct MetricDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let kind: HealthKitSink.MetricKind

    @State private var samples: [HealthKitSink.MetricSample] = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Group {
                if samples.count >= 2 {
                    chart
                } else {
                    ContentUnavailableView(
                        loaded ? "Not enough data yet" : "Loading…",
                        systemImage: kind.systemImage,
                        description: Text("\(kind.title) history needs at least two weigh-ins."))
                }
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task {
                model.readMetricHistory(kind) { result in
                    samples = result
                    loaded = true
                }
            }
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let latest = samples.last {
                Text(latest.value.formatted(1) + (kind.unitLabel.isEmpty ? "" : " " + kind.unitLabel))
                    .font(.largeTitle.weight(.bold).monospacedDigit())
                    .foregroundStyle(kind.tint)
            }
            Chart(samples) { s in
                LineMark(x: .value("Date", s.date), y: .value(kind.title, s.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(kind.tint)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                AreaMark(x: .value("Date", s.date), y: .value(kind.title, s.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(colors: [kind.tint.opacity(0.25), kind.tint.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 240)
        }
        .padding()
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
