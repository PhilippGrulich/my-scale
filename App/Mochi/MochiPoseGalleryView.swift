#if DEBUG
import SwiftUI
import MyOpenScaleCore

/// Developer screen showing every Mochi pose, at full size (140) and home-screen size (64).
/// `-mochiGallery YES` opens it at launch; `-mochiGalleryScroll <id>` (a pose name, `small` or
/// `bubble`) scrolls to a section, for simulator screenshots.
struct MochiPoseGalleryView: View {
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        ForEach(MochiPose.allCases, id: \.self) { pose in
                            VStack(spacing: 6) {
                                MochiView(pose: pose, display: Self.sampleDisplay(pose), size: 140)
                                Text(verbatim: pose.rawValue)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
                            .id(pose.rawValue)
                        }
                    }

                    Text(verbatim: "Home size (64)").font(.headline).id("small")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 14) {
                        ForEach(MochiPose.allCases, id: \.self) { pose in
                            VStack(spacing: 4) {
                                MochiView(pose: pose, display: Self.sampleDisplay(pose), size: 64)
                                Text(verbatim: pose.rawValue)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                    }

                    Text(verbatim: "Speech bubble").font(.headline).id("bubble")
                    HStack(alignment: .top, spacing: 4) {
                        MochiView(pose: .idle, display: "72.4", size: 64)
                        MochiSpeechBubble(text: "Morning! 3 days in a row. Keep it up!")
                    }
                    HStack(alignment: .top, spacing: 4) {
                        MochiView(pose: .selfHug, display: "72.8", size: 64)
                        MochiSpeechBubble(text: "Up a little. Totally normal wobble, the trend is what counts.")
                    }
                }
                .padding()
            }
            .onAppear {
                if let id = UserDefaults.standard.string(forKey: "mochiGalleryScroll") {
                    proxy.scrollTo(id, anchor: .top)
                }
            }
        }
        .background(Theme.backgroundGradient)
        .navigationTitle(Text(verbatim: "Mochi poses"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func sampleDisplay(_ pose: MochiPose) -> String {
        switch pose {
        case .helloWave: return "hi!"
        case .confetti: return "\u{2212}0.6"
        case .doubleThumbs: return "71.9"
        case .bellRing, .sadWave, .waiting: return "\u{2013} \u{2013}"
        case .squishing: return "72.6"
        default: return "72.4"
        }
    }
}
#endif
