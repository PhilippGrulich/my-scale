import SwiftUI
import MyOpenScaleCore

/// The weigh-in overlay with Mochi as host: Mochi stays on screen through the phases
/// (looking around, squishing with the live number on its tummy, then its reaction),
/// talking through speech bubbles. Same phases and controls as the plain overlay.
struct MochiWeighInView: View {
    let phase: MeasurementPhase
    let startedAt: Date?
    let bleStatus: BLEStatus
    let presentation: MochiPresentation?
    let onAccept: () -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isListening: Bool { bleStatus == .scanning }

    var body: some View {
        VStack(spacing: 20) {
            // One Mochi across phases, so pose changes crossfade instead of popping.
            MochiView(pose: pose, display: display, size: size)
                .animation(reduceMotion ? nil : .snappy, value: size)

            if let bubble {
                MochiSpeechBubble(text: bubble)
                    .id(bubble)
            }

            details
        }
        .animation(.snappy, value: bubble)
    }

    // MARK: - Per phase

    private var pose: MochiPose {
        switch phase {
        case .idle, .waiting: return .waiting
        case .measuring, .finalizing: return .squishing
        case .result: return presentation?.pose ?? .idle
        }
    }

    private var display: String {
        switch phase {
        case .idle, .waiting: return "– –"
        case .measuring(let w), .finalizing(let w): return w.formatted(1)
        case .result(let r): return r.weightKg.formatted(1)
        }
    }

    private var size: CGFloat {
        if case .result = phase { return 240 }
        return 220
    }

    private var bubble: String? {
        switch phase {
        case .idle:
            return nil
        case .waiting:
            return isListening ? String(localized: "Step on your scale") : String(localized: "Can't reach Bluetooth")
        case .measuring:
            return String(localized: "Stay still on the scale.")
        case .finalizing:
            return String(localized: "Almost there — keep your feet on the scale.")
        case .result:
            guard let text = presentation?.text, !text.isEmpty else { return nil }
            return text
        }
    }

    @ViewBuilder
    private var details: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .waiting:
            VStack(spacing: 20) {
                Text(isListening
                     ? String(localized: "Waiting for your scale… stand still once you're on and the reading will start automatically.")
                     : bleStatus.label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                Button(action: onDismiss) {
                    Text("Cancel").font(.headline)
                }
                .buttonStyle(.glass)
                .tint(.secondary)
            }
        case .measuring(let w):
            MeasuringStatusView(weightKg: w, label: "Reading weight…", startedAt: startedAt, onAccept: onAccept)
        case .finalizing(let w):
            MeasuringStatusView(weightKg: w, label: "Measuring body composition…",
                                startedAt: startedAt, onAccept: onAccept)
        case .result(let r):
            VStack(spacing: 18) {
                WeighInResultDetails(reading: r)
                Text("Tap anywhere to dismiss")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
