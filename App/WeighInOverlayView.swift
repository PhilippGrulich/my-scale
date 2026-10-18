import SwiftUI
import UIKit

/// Full-screen takeover shown while a weigh-in is in progress and when it
/// finalizes. Driven entirely by `MeasurementPhase` so the real-scale path and
/// the simulate path share one view.
struct WeighInOverlayView: View {
    let phase: MeasurementPhase
    let startedAt: Date?
    let bleStatus: BLEStatus
    /// Mochi takes over the overlay when enabled; otherwise it is the plain overlay.
    var mochiEnabled = false
    var presentation: MochiPresentation? = nil
    let onAccept: () -> Void
    let onDismiss: () -> Void
    /// Escape hatch while waiting: no scale at hand / Bluetooth unavailable.
    var onEnterManually: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            Group {
                if mochiEnabled {
                    MochiWeighInView(phase: phase, startedAt: startedAt, bleStatus: bleStatus,
                                     presentation: presentation, onAccept: onAccept, onDismiss: onDismiss,
                                     onEnterManually: onEnterManually)
                } else {
                    content
                }
            }
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
            WaitingView(bleStatus: bleStatus, onCancel: onDismiss, onEnterManually: onEnterManually)
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

struct WaitingView: View {
    let bleStatus: BLEStatus
    var onCancel: (() -> Void)? = nil
    var onEnterManually: (() -> Void)? = nil

    /// Bluetooth is usable and we're actively listening.
    private var isListening: Bool { bleStatus == .scanning }

    var body: some View {
        VStack(spacing: 28) {
            WeightCircleFace(diameter: 240) {
                WeightCircleNumber(text: "– –")
                    .foregroundStyle(.tertiary)
            }

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

            VStack(spacing: 12) {
                if let onEnterManually {
                    let button = Button(action: onEnterManually) {
                        Label("Enter manually", systemImage: "square.and.pencil")
                            .font(.headline)
                    }
                    // The prominent choice once Bluetooth is clearly not working.
                    if isListening {
                        button.buttonStyle(.glass).tint(Theme.accent)
                    } else {
                        button.buttonStyle(.borderedProminent).tint(Theme.accent)
                    }
                }
                if let onCancel {
                    Button(action: onCancel) {
                        Text("Cancel").font(.headline)
                    }
                    .buttonStyle(.glass)
                    .tint(.secondary)
                }
            }
        }
        .animation(.snappy, value: isListening)
    }
}

// MARK: - Measuring

struct MeasuringView: View {
    let weightKg: Double
    let label: LocalizedStringKey
    let hint: LocalizedStringKey
    let startedAt: Date?
    let onAccept: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            // No real progress value exists while the reading settles: the ring runs.
            WeightCircleFace(diameter: 240, progress: .indeterminate) {
                WeightCircleNumber(text: weightKg.formatted(1), value: weightKg)
            }

            MeasuringStatusView(weightKg: weightKg, label: label, hint: hint,
                                startedAt: startedAt, onAccept: onAccept)
        }
        .animation(.snappy, value: weightKg)
        .animation(.snappy, value: label)
    }
}

/// Progress label, optional hint and the "save current weight" escape hatch shown
/// while measuring. Shared by the plain overlay and Mochi's.
struct MeasuringStatusView: View {
    let weightKg: Double
    let label: LocalizedStringKey
    var hint: LocalizedStringKey? = nil
    let startedAt: Date?
    let onAccept: () -> Void

    /// Reveal the manual "save now" escape hatch once stabilization is clearly
    /// taking a while (the finalizer normally settles well under this).
    private let acceptAfter: TimeInterval = 2.0

    var body: some View {
        TimelineView(.animation) { ctx in
            let elapsed = startedAt.map { max(0, ctx.date.timeIntervalSince($0)) } ?? 0
            VStack(spacing: 18) {
                HStack(spacing: 8) {
                    ProgressView().tint(Theme.accent)
                    Text(label).font(.headline).foregroundStyle(.secondary)
                }
                if let hint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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
}

// MARK: - Result

struct ResultView: View {
    let reading: LoggedReading
    /// The full-screen overlay closes on tap; the Add Measurement sheet has
    /// its own Done button instead.
    var showsDismissHint = true
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 24) {
            // The full ring says "done".
            WeightCircleFace(diameter: 240, progress: .fraction(1)) {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                        .symbolEffect(.bounce, value: appeared)
                    WeightCircleNumber(text: reading.weightKg.formatted(1), value: reading.weightKg)
                }
            }

            WeighInResultDetails(reading: reading, style: .chips)

            if showsDismissHint {
                Text("Tap anywhere to dismiss")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .scaleEffect(appeared ? 1 : 0.85)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(duration: 0.45), value: appeared)
        .onAppear {
            appeared = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

/// A result's mini metrics (body fat, lean, BMI) and Apple Health sync badge.
/// Shared by the plain overlay and Mochi's.
struct WeighInResultDetails: View {
    enum Style { case tiles, chips }

    let reading: LoggedReading
    /// Mochi's result keeps the glass tiles; the plain circle result uses small chips.
    var style: Style = .tiles

    var body: some View {
        VStack(spacing: 22) {
            if let c = reading.composition {
                switch style {
                case .tiles:
                    HStack(spacing: 12) {
                        miniMetric("Body fat", c.bodyFatPercent, "%")
                        miniMetric("Lean", c.leanMassKg, "kg")
                        miniMetric("BMI", c.bmi, "")
                    }
                case .chips:
                    let fat = chip("Body fat", c.bodyFatPercent, "%")
                    let lean = chip("Lean", c.leanMassKg, "kg")
                    let bmi = chip("BMI", c.bmi, "")
                    // One row when it fits, else two.
                    ViewThatFits {
                        HStack(spacing: 8) { fat; lean; bmi }
                        VStack(spacing: 8) {
                            HStack(spacing: 8) { fat; lean }
                            bmi
                        }
                    }
                }
            }

            syncLine
        }
    }

    private func chip(_ title: LocalizedStringKey, _ value: Double, _ unit: String) -> some View {
        HStack(spacing: 5) {
            Text(title).foregroundStyle(.secondary)
            Text(value.formatted(1) + (unit.isEmpty || !value.isFinite ? "" : " " + unit))
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.subheadline)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.circleFill, in: Capsule())
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
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
