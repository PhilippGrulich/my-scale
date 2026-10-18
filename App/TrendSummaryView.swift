import SwiftUI
import MyOpenScaleCore

/// Compact pills under the hero: 30-day change, and (when a goal is set) the
/// distance to goal plus a trend-based ETA.
struct TrendSummaryView: View {
    let history: [WeightSample]
    let currentKg: Double?
    let goalKg: Double?

    // Trend-based so one water-heavy morning does not flip the arrow.
    private var monthChange: Double? { WeightHistory.trendChangeKg(history, lastDays: 30, now: Date()) }
    private var weeklyRate: Double? { WeightHistory.weeklyRateKg(history, lastDays: 30, now: Date()) }
    private var eta: Double? {
        guard let c = currentKg, let g = goalKg, let r = weeklyRate else { return nil }
        return WeightHistory.weeksToGoal(currentKg: c, goalKg: g, weeklyRateKg: r)
    }

    var body: some View {
        if monthChange != nil || (currentKg != nil && goalKg != nil) {
            HStack(spacing: 10) {
                if let m = monthChange {
                    pill(icon: m <= 0 ? "arrow.down.right" : "arrow.up.right",
                         text: "\(abs(m).formatted(1)) kg / 30d",
                         tint: m <= 0 ? Theme.accent : .orange)
                }
                if let c = currentKg, let g = goalKg {
                    pill(icon: "target",
                         text: "\(abs(g - c).formatted(1)) kg to goal",
                         tint: Theme.accentSecondary)
                    if let e = eta {
                        pill(icon: "calendar", text: "\(etaText(e))", tint: .secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func etaText(_ weeks: Double) -> String {
        if weeks < 8 { return String(localized: "~\(max(1, Int(weeks.rounded()))) wk") }
        return String(localized: "~\(Int((weeks / 4.345).rounded())) mo")
    }

    private func pill(icon: String, text: LocalizedStringKey, tint: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(in: .capsule)
    }
}
