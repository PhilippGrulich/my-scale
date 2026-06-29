import SwiftUI

/// A single Liquid-Glass body-composition metric card.
struct MetricCardView: View {
    let title: String
    let systemImage: String
    let value: Double?
    let unit: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(valueText)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText(value: value ?? 0))
                if isFinite, !unit.isEmpty {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .padding(14)
        .glassEffect(in: .rect(cornerRadius: 22))
        .animation(.snappy, value: value)
    }

    private var isFinite: Bool { value?.isFinite == true }
    private var valueText: String { (value).map { $0.isFinite ? $0.formatted(1) : "—" } ?? "—" }
}
