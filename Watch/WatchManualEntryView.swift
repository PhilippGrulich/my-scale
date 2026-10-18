import SwiftUI
import MyOpenScaleCore

/// The Manual page: type a weight (0.1 kg steps, starting from the last one)
/// and save it to Apple Health; the result with Mochi's reaction then shows on
/// the page itself. On these vertical pages the Digital Crown scrolls between
/// pages, so it only edits the weight after the number is tapped; the − / +
/// buttons always work.
struct WatchManualEntryView: View {
    @EnvironmentObject var model: WatchAppModel

    @State private var weightKg: Double = 75
    @State private var loaded = false
    @FocusState private var focused: Bool

    private var rounded: Double { (weightKg * 10).rounded() / 10 }

    /// This page's own save is in progress or done.
    private var showingResult: Bool {
        guard model.source == .manual else { return false }
        switch model.phase {
        case .saving, .saved, .error: return true
        default: return false
        }
    }

    var body: some View {
        Group {
            if showingResult {
                WatchWeighInView(onDone: { model.done() })
            } else {
                entry
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let last = model.currentWeightKg { weightKg = (last * 10).rounded() / 10 }
        }
        .onChange(of: model.currentWeightKg) { _, new in
            // After a save the page starts from the new weight.
            if let new, !focused { weightKg = (new * 10).rounded() / 10 }
        }
    }

    private var entry: some View {
        VStack(spacing: 6) {
            if model.mochiEnabled {
                MochiView(pose: .waiting, display: rounded.formatted(1), size: 46)
            }
            HStack(spacing: 6) {
                step(-0.1, "minus")
                Text(rounded.formatted(1))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .contentTransition(.numericText(value: rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 4)
                    .overlay(alignment: .bottom) {
                        // Shows that the Crown now edits the weight.
                        Capsule().fill(Theme.accent).frame(height: 2).opacity(focused ? 1 : 0)
                    }
                    .focusable()
                    .focused($focused)
                    .digitalCrownRotation($weightKg, from: 20, through: 300, by: 0.1,
                                          sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                    .onTapGesture { focused = true }
                step(0.1, "plus")
            }
            Text(focused ? "Turn the Digital Crown" : "Tap the number to use the Crown")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Save") {
                focused = false
                model.saveManual(weightKg: rounded)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func step(_ delta: Double, _ icon: String) -> some View {
        Button {
            weightKg = min(300, max(20, rounded + delta))
        } label: {
            Image(systemName: icon).font(.footnote.weight(.bold))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .frame(width: 34, height: 34)
        .accessibilityLabel(delta > 0 ? "Increase" : "Decrease")
    }
}
