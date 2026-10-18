import SwiftUI
import Charts
import MyOpenScaleCore

/// Detail page for one body metric (pushed from the Overview grid): today's
/// value and status, its history over the healthy band, the 30-day change,
/// the reference range for the user's sex and age, and what the value means.
struct BodyMetricDetailView: View {
    let metric: BodyMetric
    @EnvironmentObject var model: AppModel
    @State private var range: ChartRange = .m6
    /// Body fat / lean mass from Apple Health when there are no scale readings.
    @State private var healthHistory: [AppModel.MetricPoint] = []

    private var history: [AppModel.MetricPoint] {
        let scale = model.metricHistory(metric)
        return scale.isEmpty ? healthHistory : scale
    }

    private var latest: AppModel.MetricPoint? { model.latestMetric(metric) }
    private var normal: ClosedRange<Double>? {
        BodyMetricRanges.normalRange(metric, sex: model.profile.sex, ageYears: model.ageYears)
    }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 16) {
                VStack(spacing: 16) {
                    if let latest {
                        hero(latest)
                        historyCard
                        if let change = monthChange { changeCard(change) }
                        referenceCard(latest)
                        explanationCard
                    } else {
                        ContentUnavailableView(LocalizedStringKey(metric.title), systemImage: metric.systemImage,
                                               description: Text("Weigh in on your scale to see this value."))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadHealthFallback() }
    }

    // MARK: - Hero

    private func hero(_ p: AppModel.MetricPoint) -> some View {
        let status = BodyMetricRanges.status(metric, value: p.value, sex: model.profile.sex, ageYears: model.ageYears)
        return VStack(spacing: 4) {
            Image(systemName: metric.systemImage)
                .font(.title2)
                .foregroundStyle(metric.tint)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(metric.format(p.value))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                if !metric.unit.isEmpty {
                    Text(metric.unit).font(.title2.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            if let status {
                Text(status.title(for: metric))
                    .font(.headline)
                    .foregroundStyle(status.color)
            }
            Text("Measured \(p.date, format: .relative(presentation: .named))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - History

    private var visible: [AppModel.MetricPoint] {
        let cutoff = Date().addingTimeInterval(-Double(range.days) * 86_400)
        return history.filter { $0.date >= cutoff }
    }

    private var historyCard: some View {
        let points = visible
        let values = points.map(\.value) + (normal.map { [$0.lowerBound, $0.upperBound] } ?? [])
        let spread = (values.max() ?? 1) - (values.min() ?? 0)
        let pad = max(spread * 0.15, metric == .bmr ? 30 : 0.5)
        let lo = (values.min() ?? 0) - pad, hi = (values.max() ?? 1) + pad
        return card(title: "History", icon: "chart.xyaxis.line") {
            VStack(spacing: 12) {
                if points.count >= 2, let first = points.first, let last = points.last {
                    Chart {
                        if let normal {
                            RectangleMark(xStart: .value("Date", first.date), xEnd: .value("Date", last.date),
                                          yStart: .value("Value", max(lo, normal.lowerBound)),
                                          yEnd: .value("Value", min(hi, normal.upperBound)))
                                .foregroundStyle(Theme.accent.opacity(0.1))
                        }
                        ForEach(points) { p in
                            LineMark(x: .value("Date", p.date), y: .value("Value", p.value))
                                .interpolationMethod(.monotone)
                                .foregroundStyle(metric.tint)
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            PointMark(x: .value("Date", p.date), y: .value("Value", p.value))
                                .foregroundStyle(metric.tint)
                                .symbolSize(points.count > 40 ? 8 : 24)
                        }
                    }
                    .chartYScale(domain: lo...hi)
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: 190)
                    if normal != nil {
                        Label {
                            Text("Shaded: healthy range for you")
                        } icon: {
                            Image(systemName: "square.fill").foregroundStyle(Theme.accent.opacity(0.35))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Weigh in again to see how this value develops.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
                Picker("Range", selection: $range) {
                    ForEach(ChartRange.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: - Change

    private var monthChange: Double? {
        guard let last = history.last else { return nil }
        let target = Date().addingTimeInterval(-30 * 86_400)
        guard let then = history.filter({ $0.date <= target }).last ?? history.first,
              then.date < last.date else { return nil }
        return last.value - then.value
    }

    private func changeCard(_ change: Double) -> some View {
        card(title: "Last 30 days", icon: "arrow.up.arrow.down") {
            HStack(alignment: .firstTextBaseline) {
                Group {
                    if metric.format(abs(change)) == metric.format(0) {
                        Text("Unchanged")
                    } else {
                        Text((change >= 0 ? "+" : "−") + metric.formatWithUnit(abs(change)))
                    }
                }
                .font(.title3.weight(.semibold).monospacedDigit())
                Spacer()
                if let first = history.first {
                    Text("\(history.count) readings since \(first.date, format: .dateTime.day().month(.abbreviated).year())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Reference

    @ViewBuilder
    private func referenceCard(_ p: AppModel.MetricPoint) -> some View {
        let sexText = model.profile.sex == .male ? String(localized: "men") : String(localized: "women")
        card(title: "Reference", icon: "checkmark.shield") {
            VStack(alignment: .leading, spacing: 6) {
                switch metric {
                case .metabolicAge:
                    Text("Your real age is \(Int(model.ageYears)). A metabolic age below it is favourable.")
                case .visceralFat:
                    Text("1–9 healthy · 10–14 high · 15 and above very high")
                        .font(.subheadline.weight(.semibold))
                default:
                    if let normal {
                        Text("Healthy for \(sexText) aged \(Int(model.ageYears)): \(metric.format(normal.lowerBound))–\(metric.formatWithUnit(normal.upperBound))")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text("There is no general healthy range for this value — it depends on your height, build and training. Watch how it changes over time instead.")
                    }
                }
                if metric == .bmr {
                    Text("Your total daily calorie need is roughly 1.2× this when sitting most of the day, up to 1.7× when very active.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Explanation

    private var explanationCard: some View {
        card(title: "What is this?", icon: "info.circle") {
            VStack(alignment: .leading, spacing: 8) {
                Text(metric.explanation)
                Text("Estimated from your weight, the scale's electrical resistance measurement, height, age and sex. Good for following trends, not a medical measurement.")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func loadHealthFallback() async {
        guard model.metricHistory(metric).isEmpty else { return }
        let kind: HealthKitSink.MetricKind? = metric == .bodyFat ? .bodyFat : (metric == .lean ? .lean : nil)
        guard let kind else { return }
        let samples = await withCheckedContinuation { continuation in
            model.readMetricHistory(kind) { continuation.resume(returning: $0) }
        }
        healthHistory = samples.map { AppModel.MetricPoint(date: $0.date, value: $0.value) }
    }

    private func card<Content: View>(title: LocalizedStringKey, icon: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.headline)
            content()
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 22))
    }
}
