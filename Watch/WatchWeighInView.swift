import SwiftUI
import MyOpenScaleCore

/// The standalone weigh-in flow, driven entirely by `WatchAppModel.phase`:
/// searching → live weight → saving → result (or error). Presented as a sheet
/// from the dashboard.
struct WatchWeighInView: View {
    @EnvironmentObject var model: WatchAppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                switch model.phase {
                case .idle:
                    EmptyView()
                case .searching:
                    searching
                case .live(let weightKg):
                    live(weightKg)
                case .saving:
                    saving
                case .saved(let result):
                    resultView(result)
                case .error(let message):
                    errorView(message)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - States

    private var searching: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("Step on your scale")
                .font(.headline)
            Text(model.bleStatus.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            cancelButton
        }
        .padding(.top, 8)
    }

    private func live(_ weightKg: Double) -> some View {
        VStack(spacing: 6) {
            Text(weightKg.formatted(1))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .contentTransition(.numericText(value: weightKg))
                .animation(.snappy, value: weightKg)
            Text("kg")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Hold still…")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            cancelButton
        }
        .padding(.top, 8)
    }

    private var saving: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text("Saving to Health…")
                .font(.subheadline)
        }
        .padding(.top, 16)
    }

    private func resultView(_ result: WatchAppModel.WeighInResult) -> some View {
        VStack(spacing: 10) {
            Text(result.weightKg.formatted(1) + " kg")
                .font(.system(size: 36, weight: .bold, design: .rounded))

            if result.isFull {
                metricsGrid(result.composition)
            } else {
                metricRow("BMI", result.composition.bmi.formatted(1))
                Text("No body-fat estimate (no impedance).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Label(result.savedToHealth ? "Saved to Health" : "Not saved to Health",
                  systemImage: result.savedToHealth ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(result.savedToHealth ? .green : .orange)
                .padding(.top, 2)

            Button("Done") { model.done() }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .padding(.top, 4)
        }
        .padding(.top, 4)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
            Button("Done") { model.done() }
                .buttonStyle(.bordered)
        }
        .padding(.top, 12)
    }

    // MARK: - Pieces

    private func metricsGrid(_ c: BodyComposition) -> some View {
        VStack(spacing: 6) {
            metricRow("Body Fat", c.bodyFatPercent.formatted(1) + "%")
            metricRow("Lean", c.leanMassKg.formatted(1) + " kg")
            metricRow("BMI", c.bmi.formatted(1))
        }
    }

    private func metricRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.gray.opacity(0.15), in: .rect(cornerRadius: 8))
    }

    private var cancelButton: some View {
        Button("Cancel") { model.cancel() }
            .buttonStyle(.bordered)
            .tint(.secondary)
            .padding(.top, 8)
    }
}
