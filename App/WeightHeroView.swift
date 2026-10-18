import SwiftUI

/// Big current-weight number with when it was measured. The change figures
/// live in `TrendSummaryView` underneath.
struct WeightHeroView: View {
    let weightKg: Double?
    let measuredAt: Date?

    var body: some View {
        VStack(spacing: 2) {
            if let w = weightKg {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(w, format: .number.precision(.fractionLength(1)))
                        .font(.system(size: 76, weight: .bold, design: .rounded))
                        .contentTransition(.numericText(value: w))
                        .foregroundStyle(.primary)
                    Text("kg")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if let measuredAt {
                    Text("Measured \(measuredAt, format: .relative(presentation: .named))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Your latest weight")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("—")
                    .font(.system(size: 76, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("No weigh-ins yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: weightKg)
    }
}
