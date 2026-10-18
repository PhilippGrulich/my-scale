import SwiftUI
import MyOpenScaleCore

/// Small Mochi in the dashboard's top-leading corner with a speech bubble to its right.
/// The bubble appears shortly after the view appears (or the line changes, or Mochi is
/// tapped) and stays until tapped away; Mochi gently bobs unless Reduce Motion is on.
struct MochiCornerView: View {
    let presentation: MochiPresentation?
    /// Tummy display: the latest weight.
    var display: String = "– –"
    let onTap: () -> Void
    /// Reports the corner's height (Mochi, or the wrapped bubble when taller) so the
    /// dashboard can reserve exactly that much room above the weight.
    var onHeightChange: (CGFloat) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bubbleVisible = false
    @State private var bubbleTrigger = 0
    @State private var bobbing = false

    static let size: CGFloat = 64
    private static let bubbleTop: CGFloat = 8
    private static let appearDelay: Duration = .milliseconds(600)

    private var text: String? {
        guard let text = presentation?.text, !text.isEmpty else { return nil }
        return text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            MochiView(pose: presentation?.pose ?? .idle, display: display, size: Self.size, onTap: tap)
                .offset(y: reduceMotion ? 0 : (bobbing ? -3 : 3))
            if let text {
                // The hidden copy holds the bubble's full wrapped size even while it is faded out,
                // so the reserved space only changes with the line, not with every fade.
                ZStack(alignment: .topLeading) {
                    MochiSpeechBubble(text: text, maxWidth: .infinity).hidden()
                    if bubbleVisible {
                        MochiSpeechBubble(text: text, maxWidth: .infinity)
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isButton)
                            // Tapping the bubble dismisses it; tapping Mochi asks for a new line.
                            .onTapGesture { dismissBubble() }
                            .accessibilityAction { dismissBubble() }
                    }
                }
                .padding(.top, Self.bubbleTop)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeightChange($0) }
        .onAppear { startBobbing() }
        .onChange(of: reduceMotion) { _, reduce in
            if reduce {
                // Stop the repeating bob without animating to rest.
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { bobbing = false }
            } else {
                startBobbing()
            }
        }
        .onChange(of: presentation) { _, _ in bubbleTrigger += 1 }
        .task(id: bubbleTrigger) {
            bubbleVisible = false
            try? await Task.sleep(for: Self.appearDelay)
            guard !Task.isCancelled else { return }
            // Stays until the user taps (Mochi: new line; bubble: dismiss) or the dashboard goes away.
            withAnimation(.easeOut(duration: 0.3)) { bubbleVisible = true }
        }
    }

    private func startBobbing() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { bobbing = true }
    }

    private func dismissBubble() {
        withAnimation(.easeIn(duration: 0.3)) { bubbleVisible = false }
    }

    private func tap() {
        onTap()
        bubbleTrigger += 1
    }
}

/// The corner as the dashboard uses it: observes the coordinator so the corner follows
/// `settings.enabled` and `homePresentation`, and is absent entirely while Mochi is off.
struct MochiHomeCorner: View {
    @ObservedObject var mochi: MochiCoordinator
    let display: String
    let onTap: () -> Void
    var onHeightChange: (CGFloat) -> Void = { _ in }

    var body: some View {
        if mochi.settings.enabled {
            MochiCornerView(presentation: mochi.homePresentation, display: display,
                            onTap: { mochi.playTapHaptic(); onTap() },
                            onHeightChange: onHeightChange)
        }
    }
}
