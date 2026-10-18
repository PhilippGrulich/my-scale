import SwiftUI
import MyOpenScaleCore

/// Small Mochi in the dashboard's top-leading corner with a speech bubble to its right.
/// The bubble appears shortly after the view appears (or the line changes, or Mochi is
/// tapped), stays a few seconds, then fades; Mochi gently bobs unless Reduce Motion is on.
struct MochiCornerView: View {
    let presentation: MochiPresentation?
    /// Tummy display: the latest weight.
    var display: String = "– –"
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bubbleVisible = false
    @State private var bubbleTrigger = 0
    @State private var bobbing = false

    private static let size: CGFloat = 64
    private static let appearDelay: Duration = .milliseconds(600)
    private static let visibleFor: Duration = .seconds(5)

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            MochiView(pose: presentation?.pose ?? .idle, display: display, size: Self.size, onTap: tap)
                .offset(y: reduceMotion ? 0 : (bobbing ? -3 : 3))
            if bubbleVisible, let text = presentation?.text, !text.isEmpty {
                MochiSpeechBubble(text: text, maxWidth: 200, lineLimit: 2)
                    .padding(.top, 8)
                    .accessibilityElement(children: .combine)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { bobbing = true }
        }
        .onChange(of: presentation) { _, _ in bubbleTrigger += 1 }
        .task(id: bubbleTrigger) {
            bubbleVisible = false
            try? await Task.sleep(for: Self.appearDelay)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { bubbleVisible = true }
            try? await Task.sleep(for: Self.visibleFor)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.4)) { bubbleVisible = false }
        }
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

    var body: some View {
        if mochi.settings.enabled {
            MochiCornerView(presentation: mochi.homePresentation, display: display, onTap: onTap)
        }
    }
}
