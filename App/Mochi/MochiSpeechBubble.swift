import SwiftUI

/// What Mochi says: a white rounded bubble whose tail points back toward Mochi on the leading side.
struct MochiSpeechBubble: View {
    let text: String

    private static let tail: CGFloat = 10

    var body: some View {
        Text(text)
            .font(.system(.subheadline, design: .rounded).weight(.medium))
            .foregroundStyle(MochiPalette.ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 9)
            .padding(.trailing, 12)
            .padding(.leading, 12 + Self.tail)
            .background(
                MochiBubbleShape(tail: Self.tail)
                    .fill(Color.white)
                    .flipsForRightToLeftLayoutDirection(true)
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            )
            .frame(maxWidth: 220, alignment: .leading)
            .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
    }
}

/// Rounded rectangle with a small curved tail on its left edge (flipped for right-to-left layouts).
private struct MochiBubbleShape: Shape {
    let tail: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let box = CGRect(x: rect.minX + tail, y: rect.minY, width: rect.width - tail, height: rect.height)
        p.addRoundedRect(in: box, cornerSize: CGSize(width: 14, height: 14), style: .continuous)
        let cy = rect.minY + min(rect.height / 2, 20)
        p.move(to: CGPoint(x: box.minX + 6, y: cy - 8))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: cy + 6), control: CGPoint(x: box.minX - tail * 0.2, y: cy - 2))
        p.addQuadCurve(to: CGPoint(x: box.minX + 6, y: cy + 5), control: CGPoint(x: box.minX, y: cy + 6))
        p.closeSubpath()
        return p
    }
}
