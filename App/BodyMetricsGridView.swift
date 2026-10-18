import SwiftUI
import MyOpenScaleCore

/// Overview "Body" section: a two-column grid of tiles, one per metric that
/// has a value. Without a scale reading only BMI (and body fat / lean mass
/// from Health, if any) appear — nothing is shown as an empty placeholder.
struct BodyMetricsGridView: View {
    @EnvironmentObject var model: AppModel
    let onSelect: (BodyMetric) -> Void
    let onSelectBMI: () -> Void

    /// Most telling first.
    private static let order: [BodyMetric] = [.bodyFat, .muscle, .water, .visceralFat,
                                               .bmr, .metabolicAge, .lean, .bone, .protein]

    private var bmi: Double? {
        model.currentWeightKg.map { BodyCompositionCalculator.bmi(weightKg: $0, heightCm: model.profile.heightCm) }
    }

    private var available: [(BodyMetric, AppModel.MetricPoint)] {
        Self.order.compactMap { m in model.latestMetric(m).map { (m, $0) } }
    }

    /// When the newest scale-based values are from (shown if not today).
    private var measuredAt: Date? { available.map(\.1.date).max() }

    var body: some View {
        if bmi != nil || !available.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Body", systemImage: "figure.stand").font(.headline)
                    Spacer()
                    if let measuredAt, !Calendar.current.isDateInToday(measuredAt) {
                        Text("Measured \(measuredAt, format: .dateTime.day().month(.abbreviated))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)

                // Plain rows (at most ten tiles): a lazy grid inside the glass
                // container left whole rows blank.
                let tiles = allTiles
                VStack(spacing: 12) {
                    ForEach(Array(stride(from: 0, to: tiles.count, by: 2)), id: \.self) { i in
                        HStack(spacing: 12) {
                            tiles[i].view
                            if i + 1 < tiles.count {
                                tiles[i + 1].view
                            } else {
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
        }
    }

    private struct Tile { let id: String; let view: AnyView }

    private var allTiles: [Tile] {
        var tiles: [Tile] = []
        if let bmi {
            tiles.append(Tile(id: "bmi", view: AnyView(
                Button(action: onSelectBMI) { bmiTile(bmi) }.buttonStyle(.plain))))
        }
        for (metric, point) in available {
            tiles.append(Tile(id: metric.rawValue, view: AnyView(
                Button { onSelect(metric) } label: { tile(metric, point) }.buttonStyle(.plain))))
        }
        return tiles
    }

    private func bmiTile(_ bmi: Double) -> some View {
        let category = BMICategory(bmi: bmi)
        return tileBody(icon: "ruler.fill", tint: Theme.accent, title: "BMI",
                        value: bmi.formatted(1), unit: "",
                        footer: Text(category.title).foregroundStyle(category.color))
    }

    private func tile(_ metric: BodyMetric, _ point: AppModel.MetricPoint) -> some View {
        let status = BodyMetricRanges.status(metric, value: point.value,
                                             sex: model.profile.sex, ageYears: model.ageYears)
        let footer: Text = {
            if let status { return Text(status.title(for: metric)).foregroundStyle(status.color) }
            if let delta = monthDelta(metric) {
                if metric.format(abs(delta)) == metric.format(0) {
                    return Text("steady").foregroundStyle(.secondary)
                }
                return Text("\(signed(delta, metric)) / 30d").foregroundStyle(.secondary)
            }
            return Text(verbatim: " ")
        }()
        return tileBody(icon: metric.systemImage, tint: metric.tint, title: metric.title,
                        value: metric.format(point.value), unit: metric.unit, footer: footer)
    }

    private func tileBody(icon: String, tint: Color, title: String, value: String,
                          unit: String, footer: Text) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .contentTransition(.numericText())
                if !unit.isEmpty {
                    Text(unit).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            footer
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 20))
        .contentShape(Rectangle())
    }

    /// Change against the value closest to 30 days ago (nil without history).
    private func monthDelta(_ metric: BodyMetric) -> Double? {
        let history = model.metricHistory(metric)
        guard let last = history.last else { return nil }
        let target = Date().addingTimeInterval(-30 * 86_400)
        guard let then = history.filter({ $0.date <= target }).last ?? history.first,
              then.date < last.date else { return nil }
        return last.value - then.value
    }

    private func signed(_ v: Double, _ metric: BodyMetric) -> String {
        let s = metric.format(abs(v))
        return (v >= 0 ? "+" : "−") + s + (metric.unit.isEmpty ? "" : " \(metric.unit)")
    }
}
