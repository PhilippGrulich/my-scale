import SwiftUI
import MyOpenScaleCore

/// The weigh-in steps, driven by `WatchAppModel.phase`: searching → live weight
/// → saving → result (or error). Shown inside the Scale page (and the result
/// part on the Manual page). One centred layout for every step: Mochi (or the
/// number when Mochi is off) with a short line under it.
struct WatchWeighInView: View {
    /// What "Done" on the result does (the Scale page starts listening again).
    var onDone: () -> Void

    @EnvironmentObject var model: WatchAppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                switch model.phase {
                case .idle:
                    EmptyView()
                case .searching:
                    searching
                case .live(let weightKg):
                    live(weightKg)
                case .saving:
                    ProgressView().controlSize(.large).padding(.top, 30)
                case .saved(let result):
                    resultView(result)
                case .error(let message):
                    errorView(message)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
        }
    }

    // MARK: - States

    @ViewBuilder
    private var searching: some View {
        if model.mochiEnabled {
            WatchMochiRow(presentation: WatchMochi.waiting(isListening: model.bleStatus == .scanning), stacked: true)
        } else {
            ProgressView().controlSize(.large)
            Text("Step on your scale").font(.headline)
        }
        if model.bleStatus != .scanning {
            Text(model.bleStatus.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private func live(_ weightKg: Double) -> some View {
        if model.mochiEnabled {
            WatchMochiRow(presentation: WatchMochi.measuring(weightKg), stacked: true)
        } else {
            Text(weightKg.formatted(1))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .contentTransition(.numericText(value: weightKg))
            Text("Hold still…").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func resultView(_ result: WatchAppModel.WeighInResult) -> some View {
        VStack(spacing: 8) {
            if let mochi = result.mochi {
                WatchMochiRow(presentation: mochi, stacked: true)
            } else {
                Text("\(result.weightKg.formatted(1)) kg")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
            }

            HStack(spacing: 6) {
                if result.isFull {
                    chip("Body Fat", "\(result.composition.bodyFatPercent.formatted(1)) %")
                }
                chip("BMI", result.composition.bmi.formatted(1))
            }

            Label(result.savedToHealth ? "Saved to Health" : "Not saved to Health",
                  systemImage: result.savedToHealth ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(result.savedToHealth ? Theme.accent : .orange)

            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 10) {
            if model.mochiEnabled {
                MochiView(pose: .sadWave, display: "– –", size: 70)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.orange)
            }
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
            Button("Done", action: onDone)
                .buttonStyle(.bordered)
        }
    }

    private func chip(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(spacing: 0) {
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.footnote.weight(.bold).monospacedDigit())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 10))
    }
}
