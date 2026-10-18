import SwiftUI
import UIKit

/// Full-screen takeover shown while a weigh-in is in progress and when it
/// finalizes. Driven entirely by `MeasurementPhase` so the real-scale path and
/// the simulate path share one view.
struct WeighInOverlayView: View {
    let phase: MeasurementPhase
    let startedAt: Date?
    let bleStatus: BLEStatus
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            content
                .padding(28)
        }
        .contentShape(Rectangle())
        .onTapGesture { if isResult { onDismiss() } }
    }

    private var isResult: Bool { if case .result = phase { return true }; return false }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            Color.clear
        case .waiting:
            WaitingView(bleStatus: bleStatus, onCancel: onDismiss)
        case .measuring(let w):
            MeasuringView(weightKg: w, label: "Reading weight…",
                          hint: "Stay still on the scale.",
                          startedAt: startedAt, onAccept: onAccept)
        case .finalizing(let w):
            MeasuringView(weightKg: w, label: "Measuring body composition…",
                          hint: "Almost there — keep your feet on the scale.",
                          startedAt: startedAt, onAccept: onAccept)
        case .result(let r):
            ResultView(reading: r)
        }
    }
}

// MARK: - Waiting (armed, no adverts yet)

private struct WaitingView: View {
    let bleStatus: BLEStatus
    let onCancel: () -> Void

    /// Bluetooth is usable and we're actively listening.
    private var isListening: Bool { bleStatus == .scanning }

    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                PulsingRing()
                Image(systemName: isListening ? "figure.stand" : "dot.radiowaves.left.and.right")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.pulse, isActive: isListening)
            }
            .frame(width: 260, height: 260)

            VStack(spacing: 12) {
                Text(isListening ? "Step on your scale" : "Can't reach Bluetooth")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(isListening
                     ? String(localized: "Waiting for your scale… stand still once you're on and the reading will start automatically.")
                     : bleStatus.label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            Button(action: onCancel) {
                Text("Cancel").font(.headline)
            }
            .buttonStyle(.glass)
            .tint(.secondary)
        }
        .animation(.snappy, value: isListening)
    }
}

// MARK: - Measuring

private struct MeasuringView: View {
    let weightKg: Double
    let label: LocalizedStringKey
    let hint: LocalizedStringKey
    let startedAt: Date?
    let onAccept: () -> Void

    /// Reveal the manual "save now" escape hatch once stabilization is clearly
    /// taking a while (the finalizer normally settles well under this).
    private let acceptAfter: TimeInterval = 2.0

    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                PulsingRing()
                VStack(spacing: 0) {
                    Text(weightKg, format: .number.precision(.fractionLength(1)))
                        .font(.system(size: 66, weight: .bold, design: .rounded))
                        .contentTransition(.numericText(value: weightKg))
                        .monospacedDigit()
                    Text("kg")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 260, height: 260)

            TimelineView(.animation) { ctx in
                let elapsed = startedAt.map { max(0, ctx.date.timeIntervalSince($0)) } ?? 0
                VStack(spacing: 18) {
                    HStack(spacing: 8) {
                        ProgressView().tint(Theme.accent)
                        Text(label).font(.headline).foregroundStyle(.secondary)
                    }
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if elapsed >= acceptAfter {
                        VStack(spacing: 8) {
                            Button(action: onAccept) {
                                Label("Save \(weightKg, format: .number.precision(.fractionLength(1))) kg now",
                                      systemImage: "checkmark.circle.fill")
                                    .font(.headline)
                            }
                            .buttonStyle(.glass)
                            .tint(Theme.accent)
                            Text("Saves weight + BMI without body composition.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .animation(.snappy, value: elapsed >= acceptAfter)
            }
        }
        .animation(.snappy, value: weightKg)
        .animation(.snappy, value: label)
    }
}

/// Continuously breathing concentric rings (iOS 17+ `PhaseAnimator`).
private struct PulsingRing: View {
    var body: some View {
        PhaseAnimator([0.0, 1.0]) { p in
            ZStack {
                Circle()
                    .stroke(Theme.ringGradient, lineWidth: 12)
                    .scaleEffect(1.0 + p * 0.06)
                    .opacity(1.0 - p * 0.15)
                Circle()
                    .stroke(Theme.accent.opacity(0.3), lineWidth: 2)
                    .scaleEffect(1.0 + p * 0.28)
                    .opacity(0.55 - p * 0.55)
            }
        } animation: { _ in .easeInOut(duration: 1.1) }
    }
}

// MARK: - Result

private struct ResultView: View {
    let reading: LoggedReading
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(Theme.accent)
                .symbolEffect(.bounce, value: appeared)

            VStack(spacing: 0) {
                Text(reading.weightKg, format: .number.precision(.fractionLength(1)))
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("kg").font(.title3.weight(.medium)).foregroundStyle(.secondary)
            }

            if let c = reading.composition {
                HStack(spacing: 12) {
                    miniMetric("Body fat", c.bodyFatPercent, "%")
                    miniMetric("Lean", c.leanMassKg, "kg")
                    miniMetric("BMI", c.bmi, "")
                }
            }

            syncLine

            Text("Tap anywhere to dismiss")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .scaleEffect(appeared ? 1 : 0.85)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(duration: 0.45), value: appeared)
        .onAppear {
            appeared = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func miniMetric(_ title: LocalizedStringKey, _ value: Double, _ unit: String) -> some View {
        VStack(spacing: 4) {
            Text(value.formatted(1) + (unit.isEmpty || !value.isFinite ? "" : unit))
                .font(.headline.monospacedDigit())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glassEffect(in: .rect(cornerRadius: 18))
    }

    @ViewBuilder
    private var syncLine: some View {
        let status = reading.healthKitStatus
        Label {
            Text(status.label)
        } icon: {
            Image(systemName: icon(for: status))
                .symbolEffect(.pulse, isActive: status == .pending)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(color(for: status))
        .padding(.horizontal, 16).padding(.vertical, 9)
        .glassEffect(in: .capsule)
    }

    private func icon(for status: LoggedReading.SinkStatus) -> String {
        switch status {
        case .written: return "checkmark.heart.fill"
        case .pending: return "heart.fill"
        case .failed: return "exclamationmark.heart.fill"
        case .skipped: return "minus.circle"
        }
    }

    private func color(for status: LoggedReading.SinkStatus) -> Color {
        switch status {
        case .written: return Theme.accent
        case .pending: return .secondary
        case .failed: return .red
        case .skipped: return .secondary
        }
    }
}
