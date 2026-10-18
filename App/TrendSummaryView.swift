import SwiftUI
import MyOpenScaleCore

/// Stat strip under the hero: change since the previous weigh-in, the 30-day
/// trend, and (with a goal) the distance to it.
///
/// Day-to-day changes are mostly water, so "since last" stays neutral grey;
/// only the smoothed 30-day trend gets a colour — accent when it moves toward
/// the goal (or down without a goal), orange when it moves away.
struct TrendSummaryView: View {
    let history: [WeightSample]
    let currentKg: Double?
    let goalKg: Double?

    private var sorted: [WeightSample] { history.sorted { $0.date < $1.date } }
    private var previous: WeightSample? { sorted.count >= 2 ? sorted[sorted.count - 2] : nil }
    private var lastChange: Double? { WeightHistory.trendDeltaKg(history) }
    private var monthChange: Double? { WeightHistory.trendChangeKg(history, lastDays: 30, now: Date()) }
    private var weeklyRate: Double? { WeightHistory.weeklyRateKg(history, lastDays: 30, now: Date()) }
    private var eta: Double? {
        guard let c = currentKg, let g = goalKg, let r = weeklyRate else { return nil }
        return WeightHistory.weeksToGoal(currentKg: c, goalKg: g, weeklyRateKg: r)
    }

    var body: some View {
        if lastChange != nil || monthChange != nil || (currentKg != nil && goalKg != nil) {
            HStack(alignment: .top, spacing: 0) {
                if let d = lastChange, let prev = previous {
                    stat(title: "Since last",
                         value: signedKg(d),
                         icon: arrow(d),
                         tint: .primary,
                         detail: Text("since \(prev.date, format: .dateTime.day().month(.abbreviated))"))
                }
                if let m = monthChange {
                    divider
                    stat(title: "30-day trend",
                         value: signedKg(m),
                         icon: arrow(m),
                         tint: towardGoal(m) ? Theme.accent : .orange,
                         detail: weeklyRate.map { abs($0) < 0.05 ? Text("steady") : Text("\(signed($0)) kg/wk") })
                }
                if let c = currentKg, let g = goalKg {
                    divider
                    stat(title: "To goal",
                         value: "\(abs(g - c).formatted(1)) kg",
                         icon: "target",
                         tint: Theme.accentSecondary,
                         detail: eta.map { Text(etaText($0)) } ?? Text("Goal \(g.formatted(1)) kg"))
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .glassEffect(in: .rect(cornerRadius: 22))
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.secondary.opacity(0.25))
            .frame(width: 1, height: 44)
            .padding(.top, 4)
    }

    private func stat(title: LocalizedStringKey, value: String, icon: String,
                      tint: Color, detail: Text?) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                Text(value)
                    .font(.headline.monospacedDigit())
                    .contentTransition(.numericText())
            }
            .foregroundStyle(tint)
            if let detail {
                detail
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity)
    }

    // A change under 50 g is shown as flat rather than as an up/down arrow.
    private func arrow(_ d: Double) -> String {
        if abs(d) < 0.05 { return "arrow.right" }
        return d < 0 ? "arrow.down.right" : "arrow.up.right"
    }

    private func towardGoal(_ change: Double) -> Bool {
        guard let g = goalKg, let c = currentKg, abs(g - c) >= 0.1 else { return change <= 0.05 }
        return (g - c < 0) == (change < 0) || abs(change) < 0.05
    }

    private func signed(_ kg: Double) -> String {
        kg.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)))
    }

    private func signedKg(_ kg: Double) -> String { "\(signed(kg)) kg" }

    private func etaText(_ weeks: Double) -> String {
        if weeks < 8 { return String(localized: "~\(max(1, Int(weeks.rounded()))) wk") }
        return String(localized: "~\(Int((weeks / 4.345).rounded())) mo")
    }
}
