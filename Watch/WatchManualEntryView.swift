import SwiftUI
import MyOpenScaleCore

/// Type a weight with the Digital Crown (0.1 kg steps), starting from the last
/// one. Mochi shows the number on its tummy while you turn; saving goes to
/// Apple Health and shows the result screen with Mochi's reaction.
struct WatchManualEntryView: View {
    @EnvironmentObject var model: WatchAppModel
    @Environment(\.dismiss) private var dismiss

    @State private var weightKg: Double = 75
    @FocusState private var focused: Bool

    private var rounded: Double { (weightKg * 10).rounded() / 10 }

    var body: some View {
        VStack(spacing: 6) {
            if model.mochiEnabled {
                MochiView(pose: .waiting, display: rounded.formatted(1), size: 54)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(rounded.formatted(1))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .contentTransition(.numericText(value: rounded))
                    .monospacedDigit()
                Text("kg").font(.caption).foregroundStyle(.secondary)
            }
            .focusable()
            .focused($focused)
            .digitalCrownRotation($weightKg, from: 20, through: 300, by: 0.1,
                                  sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
            Text("Turn the Digital Crown")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button("Save") {
                model.saveManual(weightKg: rounded)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .navigationTitle("Add weight")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let last = model.currentWeightKg { weightKg = (last * 10).rounded() / 10 }
            focused = true
        }
    }
}
