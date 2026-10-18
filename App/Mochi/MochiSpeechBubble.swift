import SwiftUI

/// What Mochi says: a white rounded bubble whose tail points back toward Mochi on the leading side.
struct MochiSpeechBubble: View {
    let text: String
    var maxWidth: CGFloat = 220
    var lineLimit: Int? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let tail: CGFloat = 10

    var body: some View {
        Text(text)
            .font(.system(.subheadline, design: .rounded).weight(.medium))
            .foregroundStyle(MochiPalette.ink)
            .multilineTextAlignment(.leading)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 9)
            .padding(.trailing, 12)
            .padding(.leading, 12 + Self.tail)
            .background(
                MochiBubbleShape(tail: Self.tail)
                    .fill(Color.white)
                    .flipsForRightToLeftLayoutDirection(true)
                    // One outline, so the shadow traces bubble and tail together.
                    .compositingGroup()
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            )
            .frame(maxWidth: maxWidth, alignment: .leading)
            // Reduce Motion: a plain crossfade instead of the scale pop.
            .transition(reduceMotion ? .opacity : .scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
    }
}

/// Rounded rectangle with a small curved tail on its left edge (flipped for right-to-left layouts).
/// Bubble and tail are unioned into a single outline, so there is no seam or hole between them.
struct MochiBubbleShape: Shape {
    let tail: CGFloat

    func path(in rect: CGRect) -> Path {
        let box = CGRect(x: rect.minX + tail, y: rect.minY, width: rect.width - tail, height: rect.height)
        let bubble = Path(roundedRect: box, cornerSize: CGSize(width: 14, height: 14), style: .continuous)
        // A 12 pt base that starts well inside the box, curving out to the tip at the left edge.
        let cy = rect.minY + min(rect.height / 2, 20)
        let inset = box.minX + 8
        var tailPath = Path()
        tailPath.move(to: CGPoint(x: inset, y: cy - 7))
        tailPath.addQuadCurve(to: CGPoint(x: rect.minX, y: cy + 6), control: CGPoint(x: box.minX - tail * 0.1, y: cy - 1))
        tailPath.addQuadCurve(to: CGPoint(x: inset, y: cy + 5), control: CGPoint(x: box.minX + 1, y: cy + 6))
        tailPath.closeSubpath()
        return bubble.union(tailPath)
    }
}
