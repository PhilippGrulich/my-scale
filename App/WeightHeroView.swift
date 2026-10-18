import SwiftUI

/// Big current-weight number with a trend delta vs. the previous reading.
struct WeightHeroView: View {
    let weightKg: Double?
    let trendDeltaKg: Double?

    var body: some View {
        VStack(spacing: 4) {
            if let w = weightKg {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(w, format: .number.precision(.fractionLength(1)))
                        .font(.system(size: 68, weight: .bold, design: .rounded))
                        .contentTransition(.numericText(value: w))
                        .foregroundStyle(.primary)
                    Text("kg")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if let d = trendDeltaKg {
                    trendRow(d)
                } else {
                    Text("Your latest weight")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("—")
                    .font(.system(size: 68, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("No weigh-ins yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: weightKg)
        .animation(.snappy, value: trendDeltaKg)
    }

    @ViewBuilder
    private func trendRow(_ delta: Double) -> some View {
        let down = delta <= 0
        HStack(spacing: 4) {
            Image(systemName: down ? "arrow.down.right" : "arrow.up.right")
                .symbolEffect(.bounce, value: delta)
            Text("\(delta.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()))) kg")
                .contentTransition(.numericText(value: delta))
            Text("since last")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(down ? Color.green : Color.orange)
    }
}
