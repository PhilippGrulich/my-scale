import SwiftUI
import MyOpenScaleCore

/// Mochi with its speech bubble, sized for the watch. `stacked` puts the bubble
/// under a bigger Mochi (weigh-in and result screens); otherwise they sit side
/// by side (overview, setup).
struct WatchMochiRow: View {
    let presentation: MochiPresentation
    var stacked = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        if stacked {
            VStack(spacing: 4) {
                MochiView(pose: presentation.pose, display: presentation.display, size: 76, onTap: onTap)
                if !presentation.text.isEmpty {
                    bubble.frame(maxWidth: .infinity)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 2) {
                MochiView(pose: presentation.pose, display: presentation.display, size: 44, onTap: onTap)
                if !presentation.text.isEmpty {
                    bubble
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var bubble: some View {
        MochiSpeechBubble(text: presentation.text, maxWidth: stacked ? 180 : 150, lineLimit: stacked ? 4 : 3)
            .font(.footnote)
            .animation(.snappy, value: presentation.text)
    }
}
