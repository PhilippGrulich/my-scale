import SwiftUI
import MyOpenScaleCore

/// Mochi, the app's chubby orange-and-white cat. Drawn from SwiftUI shapes in a 200×200 design
/// space (the mockup in `docs/superpowers/specs/assets/2026-10-18-mochi-mockup.html`) scaled to
/// `size`. Each pose loops its own animation; Reduce Motion holds a still frame and crossfades poses.
struct MochiView: View {
    let pose: MochiPose
    var display: String = ""
    var size: CGFloat = 160
    var onTap: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var taps = 0

    var body: some View {
        ZStack {
            MochiStage(pose: pose, display: shownDisplay, size: size, still: reduceMotion)
                .id(pose)
                .transition(.opacity)
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.35), value: pose)
        .keyframeAnimator(initialValue: MochiSquish(), trigger: taps) { content, squish in
            content.scaleEffect(x: squish.x, y: squish.y, anchor: MochiGeometry.feet)
        } keyframes: { _ in
            KeyframeTrack(\.x) {
                CubicKeyframe(1.12, duration: 0.09)
                SpringKeyframe(1, duration: 0.55, spring: .bouncy)
            }
            KeyframeTrack(\.y) {
                CubicKeyframe(0.86, duration: 0.09)
                SpringKeyframe(1, duration: 0.55, spring: .bouncy)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Mochi"))
        .accessibilityValue(display)
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
        .accessibilityAction { tap() }
    }

    /// The tummy text: the given one, else "hi!" while waving hello and "– –" otherwise.
    private var shownDisplay: String {
        guard display.isEmpty else { return display }
        return pose == .helloWave ? String(localized: "hi!") : "– –"
    }

    private func tap() {
        if !reduceMotion { taps += 1 }
        onTap?()
    }
}

private struct MochiSquish {
    var x: CGFloat = 1
    var y: CGFloat = 1
}

/// One pose's animation; recreated on every pose change so the animation starts from its beginning.
private struct MochiStage: View {
    let pose: MochiPose
    let display: String
    let size: CGFloat
    let still: Bool
    @State private var start = Date()

    var body: some View {
        // 30 fps is plenty for these loops; a still Mochi (Reduce Motion) doesn't redraw at all.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: still)) { context in
            MochiFigure(pose: pose, display: display, size: size,
                        time: max(0, context.date.timeIntervalSince(start)), still: still)
        }
    }
}

// MARK: - Shared drawing helpers

/// The cat's coat colours (from the mockup) and the props' party colours.
enum MochiPalette {
    // Coat.
    static let fur = hex(0xF5953A)
    static let stripe = hex(0xD9772A)
    static let white = hex(0xFFFFFF)
    static let ink = hex(0x3B2A20)
    static let innerEar = hex(0xF7B4B4)
    static let nose = hex(0xE77F8C)
    static let cheek = hex(0xF28B8B).opacity(0.45)
    static let mouth = hex(0x7A2E3A)
    static let tongue = hex(0xF28B8B)
    /// Faint outline around the white (and fur) parts so they don't melt into a white background.
    static let outline = Color(red: 59 / 255, green: 42 / 255, blue: 32 / 255).opacity(0.12)
    /// Outline width in design units.
    static let outlineWidth: CGFloat = 1.2
    static let shades = hex(0x1A1A1A)

    // Props.
    static let blush = hex(0xFF8FA3)
    static let bulb = hex(0xFFD166)
    static let sky = hex(0x2A8FD8)
    static let mint = hex(0x7DFCC9)
    static let lilac = hex(0xB79CFF)

    static func hex(_ rgb: UInt32) -> Color {
        Color(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
              blue: Double(rgb & 0xFF) / 255)
    }
}

enum MochiGeometry {
    /// Width and height of the design space every part is drawn in.
    static let design: CGFloat = 200
    /// Bottom centre of the body: the anchor for squash, stretch and tilt.
    static let feet = unit(100, 176)
    /// The neck: the head tilts around it.
    static let neck = unit(100, 112)
    /// Mirrors design-space x around the body's centre line.
    static let mirror = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: design, ty: 0)
    /// Shoulders (left, right) of the unsquashed body.
    static let shoulderL = pt(66, 114)
    static let shoulderR = pt(134, 114)

    static func unit(_ x: CGFloat, _ y: CGFloat) -> UnitPoint {
        UnitPoint(x: x / design, y: y / design)
    }

    /// Where a body point lands when the body scales by (`x`, `y`) around the feet.
    static func onBody(_ p: CGPoint, _ x: CGFloat, _ y: CGFloat) -> CGPoint {
        pt(100 + (p.x - 100) * x, 176 + (p.y - 176) * y)
    }
}

func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

func circleRect(_ c: CGPoint, _ r: CGFloat) -> CGRect {
    CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
}

/// A path built in design-space coordinates, scaled to whatever frame it is given.
struct MochiShape: Shape {
    let build: @Sendable (inout Path) -> Void

    init(_ build: @escaping @Sendable (inout Path) -> Void) { self.build = build }

    /// A fixed design-space path.
    init(path: Path) { self.build = { $0.addPath(path) } }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        build(&path)
        let k = rect.width / MochiGeometry.design
        return path.applying(CGAffineTransform(scaleX: k, y: rect.height / MochiGeometry.design)
            .translatedBy(x: rect.minX / k, y: rect.minY / k))
    }
}

/// A filled design-space path; `outline` adds the faint ink edge the white parts wear.
@ViewBuilder
func mochiFill(_ path: Path, _ color: Color, outline: Bool = false, s: CGFloat) -> some View {
    if outline {
        MochiShape(path: path).fill(color)
            .overlay(MochiShape(path: path).stroke(MochiPalette.outline, lineWidth: MochiPalette.outlineWidth * s))
    } else {
        MochiShape(path: path).fill(color)
    }
}

/// A round-capped stroke of a design-space path; `width` is in design units.
func mochiStroke(_ path: Path, _ color: Color, width: CGFloat, s: CGFloat) -> some View {
    MochiShape(path: path)
        .stroke(color, style: StrokeStyle(lineWidth: width * s, lineCap: .round, lineJoin: .round))
}

extension Path {
    static func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
    }

    static func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
        ellipse(cx, cy, r, r)
    }

    /// Parses the subset of SVG path data the mockup uses: absolute M, L, H, V, Q, C, Z.
    init(svg d: String) {
        self.init()
        enum Token { case command(Character), number(CGFloat) }
        var tokens: [Token] = []
        var numberText = ""
        func flush() {
            if !numberText.isEmpty, let v = Double(numberText) { tokens.append(.number(CGFloat(v))) }
            numberText = ""
        }
        for ch in d {
            if ch.isLetter {
                flush()
                tokens.append(.command(ch))
            } else if ch == "-" {
                flush()
                numberText = "-"
            } else if ch.isNumber || ch == "." {
                numberText.append(ch)
            } else {
                flush()
            }
        }
        flush()

        var i = 0
        var command: Character = "M"
        var current = CGPoint.zero
        var start = CGPoint.zero
        func number() -> CGFloat {
            guard i < tokens.count, case .number(let v) = tokens[i] else { return 0 }
            i += 1
            return v
        }
        func point() -> CGPoint {
            let x = number()
            return CGPoint(x: x, y: number())
        }
        while i < tokens.count {
            if case .command(let c) = tokens[i] {
                command = c
                i += 1
                if c == "Z" || c == "z" {
                    closeSubpath()
                    current = start
                }
                continue
            }
            switch command {
            case "M":
                current = point()
                start = current
                move(to: current)
                command = "L"
            case "L":
                current = point()
                addLine(to: current)
            case "H":
                current.x = number()
                addLine(to: current)
            case "V":
                current.y = number()
                addLine(to: current)
            case "Q":
                let control = point()
                current = point()
                addQuadCurve(to: current, control: control)
            case "C":
                let c1 = point()
                let c2 = point()
                current = point()
                addCurve(to: current, control1: c1, control2: c2)
            default:
                assertionFailure("Unsupported SVG path command \(command)")
                i += 1
            }
        }
    }
}

/// Keyframe maths shared by the pose animations.
enum MochiKeys {
    /// Position 0..<1 within a repeating cycle.
    static func phase(_ t: Double, _ period: Double, delay: Double = 0) -> Double {
        let x = (t - delay) / period
        return x - floor(x)
    }

    /// Eases through `(phase, value)` stops (phases ascending, 0...1).
    static func kf(_ p: Double, _ stops: [(Double, Double)]) -> Double {
        guard let first = stops.first, let last = stops.last else { return 0 }
        if p <= first.0 { return first.1 }
        for (a, b) in zip(stops, stops.dropFirst()) where p <= b.0 {
            let span = b.0 - a.0
            let u = span > 0 ? (p - a.0) / span : 1
            return a.1 + (b.1 - a.1) * u * u * (3 - 2 * u)
        }
        return last.1
    }

    /// Repeatable pseudo-random 0..<1 for slot `n`.
    static func noise(_ n: Double) -> Double {
        let x = sin(n * 12.9898) * 43758.5453
        return x - floor(x)
    }

    static func lerp(_ a: CGPoint, _ b: CGPoint, _ u: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u)
    }
}

// MARK: - Figure

private struct MochiFigure: View {
    let pose: MochiPose
    let display: String
    let size: CGFloat
    let time: Double
    let still: Bool

    var body: some View {
        let m = MochiMotion(pose: pose, time: time, still: still)
        let look = MochiLook(pose)
        let s = size / MochiGeometry.design
        // Shoulders ride the body's breathing and squeezing.
        let shoulderL = MochiGeometry.onBody(MochiGeometry.shoulderL, m.bellyX, m.bellyY)
        let shoulderR = MochiGeometry.onBody(MochiGeometry.shoulderR, m.bellyX, m.bellyY)
        let leftAngle = look.leftArm.angle + m.leftArm
        let rightAngle = look.rightArm.angle + m.rightArm
        let rightShoulder = pt(shoulderR.x - m.squeeze, shoulderR.y)
        // The head sits on the body, so it rises and sinks with it.
        let headY = m.headDrop - 62 * (m.bellyY - 1)

        ZStack {
            MochiGroundShadow(lift: m.lift)
            MochiBackProps(pose: pose, time: time, still: still)
            ZStack {
                MochiTail(s: s)
                    .rotationEffect(.degrees(m.tail), anchor: MochiGeometry.unit(150, 158))
                MochiTorso(text: display, s: s)
                    .scaleEffect(x: m.bellyX, y: m.bellyY, anchor: MochiGeometry.feet)
                ZStack {
                    MochiHead(look: look, eyeOpen: m.eyeOpen, glance: m.glance, s: s)
                    MochiHeadProps(pose: pose, time: time, still: still, s: s)
                }
                .rotationEffect(.degrees(m.headTilt), anchor: MochiGeometry.neck)
                .offset(y: headY * s)
                MochiArm(style: look.leftArm, side: .left, angle: leftAngle,
                         shoulder: pt(shoulderL.x + m.squeeze, shoulderL.y), thumbPop: m.thumbPop, s: s)
                MochiArm(style: look.rightArm, side: .right, angle: rightAngle,
                         shoulder: rightShoulder, thumbPop: m.thumbPop, s: s)
                MochiHeldProp(pose: pose, time: time, still: still,
                              paw: MochiArmStyle.paw(side: .right, angle: rightAngle, shoulder: rightShoulder), s: s)
            }
            .scaleEffect(x: m.squashX, y: m.squashY, anchor: MochiGeometry.feet)
            .rotationEffect(.degrees(m.tilt), anchor: MochiGeometry.feet)
            .offset(y: m.lift * s)
            MochiFrontProps(pose: pose, time: time, still: still, s: s)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Motion

/// Every moving value of one animation frame, in design units and degrees.
private struct MochiMotion {
    /// Whole cat: hop height (negative is up), squash and tilt around the feet.
    var lift: CGFloat = 0
    var squashX: CGFloat = 1
    var squashY: CGFloat = 1
    var tilt: Double = 0
    /// Body (belly, bib, feet, tummy text) scale around the feet: breathing, puffing, sucking in.
    var bellyX: CGFloat = 1
    var bellyY: CGFloat = 1
    /// Head tilt around the neck, and how far the head sinks (positive is down).
    var headTilt: Double = 0
    var headDrop: CGFloat = 0
    /// Tail rotation around its base.
    var tail: Double = 0
    /// Added to each arm's style angle; positive swings the paw outward and up.
    var leftArm: Double = 0
    var rightArm: Double = 0
    /// Shoulders pulled in toward the belly, in design units.
    var squeeze: CGFloat = 0
    var thumbPop: CGFloat = 1
    var eyeOpen: CGFloat = 1
    var glance: CGFloat = 0

    init(pose: MochiPose, time t: Double, still: Bool) {
        eyeOpen = Self.blink(t)
        if still { settle(pose) } else { animate(pose, t) }
    }

    /// Eyes close briefly every 3–6 s: one blink per 4.5 s slot, at a random point in its first 1.5 s.
    static func blink(_ t: Double) -> CGFloat {
        let slot = floor(t / 4.5)
        let at = slot * 4.5 + 1.2 + MochiKeys.noise(slot) * 1.5
        let u = (t - at) / 0.18
        guard u > 0, u < 1 else { return 1 }
        return CGFloat(abs(u * 2 - 1))
    }

    /// The tail's lazy swish, −6° ↔ +14°.
    private static func swish(_ t: Double, _ period: Double) -> Double {
        MochiKeys.kf(MochiKeys.phase(t, period), [(0, -6), (0.5, 14), (1, -6)])
    }

    /// Rest, look left, look right, rest.
    private static func lookAround(_ t: Double, _ period: Double, left: Double, right: Double) -> Double {
        MochiKeys.kf(MochiKeys.phase(t, period),
                     [(0, 0), (0.15, 0), (0.25, left), (0.45, left), (0.55, right), (0.8, right), (0.9, 0), (1, 0)])
    }

    /// Reduce Motion: a single readable frame of the pose.
    private mutating func settle(_ pose: MochiPose) {
        switch pose {
        case .doubleThumbs: bellyX = 1.04; bellyY = 1.07
        case .sadWave: squashX = 1.02; squashY = 0.97; headDrop = 3; headTilt = -4
        case .squishing: bellyX = 0.87; squeeze = 1.5; leftArm = -4; rightArm = -4
        case .waiting: headTilt = -5
        default: break
        }
    }

    private mutating func animate(_ pose: MochiPose, _ t: Double) {
        typealias K = MochiKeys
        let breath = K.kf(K.phase(t, 3), [(0, 0), (0.5, 1), (1, 0)])
        switch pose {
        case .idle:
            bellyX = 1 + 0.025 * breath; bellyY = 1 + 0.02 * breath
            leftArm = 2 * breath; rightArm = 2 * breath
            tail = Self.swish(t, 3.2)

        case .helloWave:
            let p = K.phase(t, 1.4)
            squashX = K.kf(p, [(0, 1), (0.3, 1.06), (0.55, 0.96), (0.8, 1.03), (1, 1)])
            squashY = K.kf(p, [(0, 1), (0.3, 0.93), (0.55, 1.05), (0.8, 0.97), (1, 1)])
            lift = K.kf(p, [(0, 0), (0.3, 0), (0.55, -10), (0.8, 0), (1, 0)])
            let w = K.phase(t, 1.0)
            rightArm = K.kf(w, [(0, -14), (0.5, 14), (1, -14)])
            headTilt = K.kf(w, [(0, -3), (0.5, 3), (1, -3)])
            tail = Self.swish(t, 1.2)

        case .thumbsUp:
            let p = K.phase(t, 2.2)
            squashX = K.kf(p, [(0, 1), (0.12, 1.12), (0.3, 0.93), (0.48, 1.06), (0.6, 1), (1, 1)])
            squashY = K.kf(p, [(0, 1), (0.12, 0.86), (0.3, 1.08), (0.48, 0.95), (0.6, 1), (1, 1)])
            lift = K.kf(p, [(0, 0), (0.12, 0), (0.3, -18), (0.48, 0), (1, 0)])
            tilt = K.kf(p, [(0, 0), (0.12, 0), (0.3, -4), (0.85, -4), (1, 0)])
            rightArm = K.kf(p, [(0, -30), (0.2, -30), (0.34, 10), (0.42, 0), (0.88, 0), (1, -30)])
            thumbPop = K.kf(p, [(0, 0.5), (0.2, 0.5), (0.38, 1.25), (0.5, 1), (0.88, 1), (1, 0.5)])
            tail = Self.swish(t, 1.1)

        case .doubleThumbs:
            // Shades drop on (props), chest puffs, both thumbs come up.
            let p = K.phase(t, 4)
            let puff = K.kf(p, [(0, 0), (0.15, 0), (0.3, 1), (0.85, 1), (1, 0)])
            bellyX = 1 + 0.04 * puff; bellyY = 1 + 0.07 * puff
            let arms = K.kf(p, [(0, -60), (0.2, -60), (0.32, 10), (0.38, 0), (0.86, 0), (1, -60)])
            leftArm = arms; rightArm = arms
            thumbPop = K.kf(p, [(0, 0.6), (0.24, 0.6), (0.36, 1.2), (0.44, 1), (0.86, 1), (1, 0.6)])
            tail = Self.swish(t, 2)

        case .confetti:
            // A big squishy jump with both arms up.
            let p = K.phase(t, 1.3)
            squashX = K.kf(p, [(0, 1.12), (0.15, 0.94), (0.45, 1), (0.75, 1), (0.85, 1.12), (1, 1.12)])
            squashY = K.kf(p, [(0, 0.86), (0.15, 1.08), (0.45, 1), (0.75, 1), (0.85, 0.86), (1, 0.86)])
            lift = K.kf(p, [(0, 0), (0.15, 0), (0.45, -30), (0.75, 0), (1, 0)])
            let cheer = K.kf(K.phase(t, 0.65), [(0, 0), (0.5, -18), (1, 0)])
            leftArm = cheer; rightArm = cheer
            tail = Self.swish(t, 0.65)

        case .selfHug:
            // Drums the sides of its round belly, which jiggles.
            leftArm = K.kf(K.phase(t, 0.8), [(0, 0), (0.4, -11), (1, 0)])
            rightArm = K.kf(K.phase(t, 0.8, delay: 0.4), [(0, 0), (0.4, -11), (1, 0)])
            let jiggle = K.kf(K.phase(t, 0.4), [(0, 0), (0.5, 1), (1, 0)])
            bellyX = 1 + 0.025 * jiggle; bellyY = 1 - 0.015 * jiggle
            tilt = K.kf(K.phase(t, 2.6), [(0, -2), (0.5, 2), (1, -2)])
            tail = Self.swish(t, 1.8)

        case .bellRing:
            let p = K.phase(t, 1.6)
            tilt = K.kf(p, [(0, 0), (0.25, -3), (0.75, 3), (1, 0)])
            headTilt = -tilt
            rightArm = K.kf(p, [(0, 0), (0.1, 6), (0.2, -4), (0.3, 6), (0.4, -4), (0.5, 0), (1, 0)])
            tail = Self.swish(t, 1.6)

        case .snoozing:
            let slow = K.kf(K.phase(t, 3.6), [(0, 0), (0.5, 1), (1, 0)])
            bellyX = 1 + 0.035 * slow; bellyY = 1 + 0.05 * slow
            headDrop = 4 * slow
            tail = K.kf(K.phase(t, 7), [(0, 0), (0.8, 0), (0.84, 10), (0.88, -2), (0.92, 8), (1, 0)])

        case .sadWave:
            let sway = K.kf(K.phase(t, 3.6), [(0, 0), (0.5, 1), (1, 0)])
            squashX = 1.02; squashY = 0.97
            headDrop = 3
            headTilt = -4 + 2 * sway
            leftArm = K.kf(K.phase(t, 1.8), [(0, 0), (0.3, 14), (0.6, -6), (1, 0)])
            tail = K.kf(K.phase(t, 4), [(0, -4), (0.5, 4), (1, -4)])

        case .waiting:
            bellyX = 1 + 0.02 * breath; bellyY = 1 + 0.015 * breath
            glance = CGFloat(Self.lookAround(t, 4.8, left: -3, right: 3))
            headTilt = Self.lookAround(t, 4.8, left: -9, right: 8)
            tail = Self.swish(t, 2.4)

        case .squishing:
            // Sucking it in: the belly squeezes narrower, the paws push it in, a little wobble.
            let hold = K.kf(K.phase(t, 3), [(0, 0), (0.3, 1), (0.75, 1), (1, 0)])
            let s = 0.35 + 0.65 * hold
            bellyX = 1 - 0.14 * CGFloat(s)
            squeeze = 1.5 * CGFloat(s)
            leftArm = -4 * s; rightArm = -4 * s
            tilt = 1.5 * sin(t * 2 * .pi * 1.7)
            tail = Self.swish(t, 1.2)

        case .birthday:
            let p = K.phase(t, 1.6)
            squashX = K.kf(p, [(0, 1), (0.3, 1.06), (0.5, 0.96), (0.7, 1.03), (1, 1)])
            squashY = K.kf(p, [(0, 1), (0.3, 0.92), (0.5, 1.05), (0.7, 0.97), (1, 1)])
            lift = K.kf(p, [(0, 0), (0.3, 0), (0.5, -10), (0.7, 0), (1, 0)])
            leftArm = K.kf(K.phase(t, 0.8), [(0, -8), (0.5, 10), (1, -8)])
            rightArm = K.kf(p, [(0, 0), (0.5, 4), (1, 0)])
            tail = Self.swish(t, 1.2)
        }
    }
}

// MARK: - Look

private enum MochiEyes { case open, wide, wink, smug, happy, closed, squeezed, sad }
private enum MochiMouth { case w, softSmile, openSmile, tongueGrin, bigGrin, smirk, oh, frown, wobbly }

/// What a pose looks like when standing still: expression, arm shapes, ears.
private struct MochiLook {
    var eyes = MochiEyes.open
    var mouth = MochiMouth.w
    var leftArm = MochiArmStyle.rest
    var rightArm = MochiArmStyle.rest
    /// Ears folded back (outward), in degrees.
    var earsBack: Double = 0
    var bigBlush = false

    init(_ pose: MochiPose) {
        switch pose {
        case .idle: break
        case .helloWave: mouth = .openSmile; rightArm = .wave
        case .thumbsUp: eyes = .wink; mouth = .tongueGrin; rightArm = .thumb
        case .doubleThumbs: eyes = .smug; mouth = .smirk; leftArm = .thumb; rightArm = .thumb
        case .confetti: eyes = .happy; mouth = .bigGrin; leftArm = .up; rightArm = .up
        case .selfHug: eyes = .happy; leftArm = .hug; rightArm = .hug; bigBlush = true
        case .bellRing: eyes = .wide; mouth = .oh; rightArm = .hold
        case .snoozing: eyes = .closed; leftArm = .tucked; rightArm = .tucked; earsBack = 4
        case .sadWave: eyes = .sad; mouth = .frown; leftArm = .smallWave; earsBack = 14
        case .waiting: mouth = .softSmile
        case .squishing: eyes = .squeezed; mouth = .wobbly; leftArm = .squeeze; rightArm = .squeeze; bigBlush = true
        case .birthday: eyes = .happy; mouth = .openSmile; leftArm = .cheer; rightArm = .hold
        }
    }
}

// MARK: - Body parts

private struct MochiGroundShadow: View {
    let lift: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // A dark shadow would vanish on a dark background; there it is a faint light patch.
        MochiShape { $0.addEllipse(in: CGRect(x: 34, y: 176, width: 132, height: 12)) }
            .fill(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.1))
            .scaleEffect(max(0.6, 1 + lift / 70), anchor: MochiGeometry.unit(100, 182))
    }
}

/// Paths from the mockup, in design space.
private enum MochiCat {
    static let tail = Path(svg: "M148 160 C182 160 190 128 174 110")
    static let tailTip = Path(svg: "M178 119 C177 115 176 112 174 110")
    static let body = Path.ellipse(100, 132, 60, 46)
    static let bodyStripes = Path(svg: "M44 128 Q52 126 56 132 Q50 134 44 132Z M156 128 Q148 126 144 132 Q150 134 156 132Z M46 144 Q54 142 58 148 Q51 150 47 148Z M154 144 Q146 142 142 148 Q149 150 153 148Z")
    static let bib = Path(svg: "M100 100 C78 100 62 118 63 142 C64 162 80 172 100 172 C120 172 136 162 137 142 C138 118 122 100 100 100Z")
    static let footL = Path.ellipse(80, 174, 13, 7.5)
    static let footR = Path.ellipse(120, 174, 13, 7.5)
    static let toes = Path(svg: "M76 172 L76 177 M84 172 L84 177 M116 172 L116 177 M124 172 L124 177")
    static let earL = Path(svg: "M64 62 L60 26 L92 46 Z")
    static let innerEarL = Path(svg: "M68 56 L66 36 L84 48 Z")
    static let earR = Path(svg: "M136 62 L140 26 L108 46 Z")
    static let innerEarR = Path(svg: "M132 56 L134 36 L116 48 Z")
    static let head = Path.ellipse(100, 80, 45, 37)
    static let cap = Path(svg: "M55.5 76 C56 54 74 43 100 43 C126 43 144 54 144.5 76 C138 70 130 69 124 71 C116 64 107 66 104 72 L100 80 L96 72 C93 66 84 64 76 71 C70 69 62 70 55.5 76Z")
    static let foreheadStripes = Path(svg: "M91 45 Q93 54 95 45Z M98 44 Q100 56 102 44Z M105 45 Q107 54 109 46Z")
    static let muzzle = Path(svg: "M100 66 C96 74 94 80 88 84 C78 86 74 94 80 100 C88 107 112 107 120 100 C126 94 122 86 112 84 C106 80 104 74 100 66Z")
    static let nose = Path(svg: "M96.5 87.5 L103.5 87.5 L100 91.5 Z")
    static let whiskers = Path(svg: "M70 88 L50 85 M70 93 L50 95 M130 88 L150 85 M130 93 L150 95")
}

private struct MochiTail: View {
    let s: CGFloat

    var body: some View {
        ZStack {
            mochiStroke(MochiCat.tail, MochiPalette.fur, width: 16, s: s)
            mochiStroke(MochiCat.tailTip, MochiPalette.outline, width: 16 + 2 * MochiPalette.outlineWidth, s: s)
            mochiStroke(MochiCat.tailTip, MochiPalette.white, width: 16, s: s)
        }
    }
}

/// The round body with its white bib, the tummy text, and the feet.
private struct MochiTorso: View {
    let text: String
    let s: CGFloat

    var body: some View {
        ZStack {
            mochiFill(MochiCat.body, MochiPalette.fur, outline: true, s: s)
            mochiFill(MochiCat.bodyStripes, MochiPalette.stripe, s: s)
            mochiFill(MochiCat.bib, MochiPalette.white, s: s)
            // 52 wide (x 74…126) keeps "188.8" clear of the paws in every pose.
            Text(verbatim: text)
                .font(.system(size: 22 * s, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(MochiPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: 52 * s)
                .position(x: 100 * s, y: 141 * s)
            mochiFill(MochiCat.footL, MochiPalette.white, outline: true, s: s)
            mochiFill(MochiCat.footR, MochiPalette.white, outline: true, s: s)
            mochiStroke(MochiCat.toes, MochiPalette.ink, width: 1.3, s: s).opacity(0.3)
        }
    }
}

private struct MochiHead: View {
    let look: MochiLook
    let eyeOpen: CGFloat
    let glance: CGFloat
    let s: CGFloat

    var body: some View {
        let blush: (CGFloat, CGFloat) = look.bigBlush ? (9, 6) : (6.5, 4)
        ZStack {
            ZStack {
                mochiFill(MochiCat.earL, MochiPalette.fur, s: s)
                mochiFill(MochiCat.innerEarL, MochiPalette.innerEar, s: s)
            }
            .rotationEffect(.degrees(-look.earsBack), anchor: MochiGeometry.unit(78, 54))
            ZStack {
                mochiFill(MochiCat.earR, MochiPalette.fur, s: s)
                mochiFill(MochiCat.innerEarR, MochiPalette.innerEar, s: s)
            }
            .rotationEffect(.degrees(look.earsBack), anchor: MochiGeometry.unit(122, 54))
            mochiFill(MochiCat.head, MochiPalette.fur, outline: true, s: s)
            mochiFill(MochiCat.cap, MochiPalette.fur, s: s)
            mochiFill(MochiCat.foreheadStripes, MochiPalette.white, s: s)
            mochiFill(MochiCat.muzzle, MochiPalette.white, s: s)
            mochiFill(.ellipse(76, 91, blush.0, blush.1), MochiPalette.cheek, s: s)
            mochiFill(.ellipse(124, 91, blush.0, blush.1), MochiPalette.cheek, s: s)
            ZStack {
                MochiEye(kind: look.eyes, x: 84, open: eyeOpen, s: s)
                MochiEye(kind: look.eyes, x: 116, open: eyeOpen, s: s)
            }
            .offset(x: glance * s)
            mochiFill(MochiCat.nose, MochiPalette.nose, s: s)
            MochiMouthView(kind: look.mouth, s: s)
            mochiStroke(MochiCat.whiskers, MochiPalette.ink, width: 1.3, s: s).opacity(0.5)
        }
    }
}

private struct MochiEye: View {
    let kind: MochiEyes
    let x: CGFloat
    let open: CGFloat
    let s: CGFloat

    private var ink: Color { MochiPalette.ink }

    var body: some View {
        switch kind {
        case .open: roundEye(rx: 6.6, ry: 8.4)
        case .wide: roundEye(rx: 8.4, ry: 9.8)
        case .wink:
            if x < 100 { happy } else { roundEye(rx: 6.6, ry: 8.4) }
        case .sad:
            ZStack {
                roundEye(rx: 6, ry: 7.6, y: 79.5)
                // Brows: the inner ends lifted.
                let d = x < 100 ? "M\(x - 7) 69 Q\(x - 1) 68 \(x + 6) 64.5" : "M\(x + 7) 69 Q\(x + 1) 68 \(x - 6) 64.5"
                mochiStroke(Path(svg: d), ink, width: 2.4, s: s)
            }
        case .happy: happy
        case .closed:
            mochiStroke(Path(svg: "M\(x - 7) 78 Q\(x) 84 \(x + 7) 78"), ink, width: 3.4, s: s)
        case .smug:
            // A lower half-disk under a heavy upper lid.
            let k: CGFloat = 7 * 0.5523
            ZStack {
                mochiFill(Path(svg: "M\(x - 7) 78 C\(x - 7) \(78 + k) \(x - k) 85 \(x) 85 C\(x + k) 85 \(x + 7) \(78 + k) \(x + 7) 78 Z"), ink, s: s)
                mochiStroke(Path(svg: "M\(x - 8) 77 L\(x + 8) 77.8"), ink, width: 3, s: s)
            }
        case .squeezed:
            let d = x < 100 ? "M\(x - 5) 72 L\(x + 5) 78 L\(x - 5) 84" : "M\(x + 5) 72 L\(x - 5) 78 L\(x + 5) 84"
            mochiStroke(Path(svg: d), ink, width: 3, s: s)
        }
    }

    private var happy: some View {
        mochiStroke(Path(svg: "M\(x - 7) 81 Q\(x) 70 \(x + 7) 81"), ink, width: 3.4, s: s)
    }

    /// A big glossy eye with two highlights; blinks around its centre.
    private func roundEye(rx: CGFloat, ry: CGFloat, y: CGFloat = 78) -> some View {
        ZStack {
            mochiFill(.ellipse(x, y, rx, ry), ink, s: s)
            mochiFill(.circle(x + 0.35 * rx, y - 0.38 * ry, 0.39 * rx), MochiPalette.white, s: s)
            mochiFill(.circle(x - 0.3 * rx, y + 0.42 * ry, 0.17 * rx), MochiPalette.white, s: s)
        }
        .scaleEffect(x: 1, y: max(0.1, open), anchor: MochiGeometry.unit(x, y))
    }
}

private struct MochiMouthView: View {
    let kind: MochiMouth
    let s: CGFloat

    private var ink: Color { MochiPalette.ink }

    var body: some View {
        switch kind {
        case .w: mochiStroke(Path(svg: "M93 93 Q96.5 98 100 93 Q103.5 98 107 93"), ink, width: 2.4, s: s)
        case .softSmile: mochiStroke(Path(svg: "M94.5 94 Q100 99 105.5 94"), ink, width: 2.4, s: s)
        case .frown: mochiStroke(Path(svg: "M95 98.5 Q100 94.5 105 98.5"), ink, width: 2.4, s: s)
        case .wobbly: mochiStroke(Path(svg: "M94 97 Q96 94 98 97 Q100 100 102 97 Q104 94 106 97"), ink, width: 2.4, s: s)
        case .smirk: mochiStroke(Path(svg: "M94 94 Q101 99 107 92"), ink, width: 2.4, s: s)
        case .oh: mochiFill(.ellipse(100, 98, 4.2, 5), MochiPalette.mouth, s: s)
        case .openSmile: open(Path(svg: "M92 93 Q100 107 108 93 Z"), tongue: .ellipse(100, 99, 4, 2.2))
        case .bigGrin: open(Path(svg: "M89 92 Q100 112 111 92 Z"), tongue: .ellipse(100, 101, 5.5, 3))
        case .tongueGrin:
            ZStack {
                open(Path(svg: "M90 92 Q100 108 110 92 Z"), tongue: nil)
                // The tongue sticks out over the lower lip.
                mochiFill(.ellipse(103, 101.5, 3.8, 4.8), MochiPalette.tongue, s: s)
                mochiStroke(Path(svg: "M103 99 L103 103.5"), MochiPalette.mouth, width: 1, s: s).opacity(0.5)
            }
        }
    }

    /// An open mouth with its tongue tucked inside.
    private func open(_ mouth: Path, tongue: Path?) -> some View {
        ZStack {
            mochiFill(mouth, MochiPalette.mouth, s: s)
            if let tongue {
                mochiFill(tongue, MochiPalette.tongue, s: s)
                    .clipShape(MochiShape(path: mouth))
            }
            mochiStroke(mouth, ink, width: 1.2, s: s)
        }
    }
}

// MARK: - Arms

enum MochiSide { case left, right }

/// Arm poses: a short arm hanging from the shoulder, its white paw at the end.
enum MochiArmStyle {
    case rest, tucked, squeeze, hug, wave, smallWave, up, cheer, thumb, hold

    /// How far the arm swings out from hanging straight down, in degrees (the same on both sides).
    var angle: Double {
        switch self {
        case .rest: return 12
        case .tucked: return 13
        case .squeeze: return 20
        case .hug: return 20
        case .wave: return 155
        case .smallWave: return 100
        case .up: return 160
        case .cheer: return 155
        case .thumb: return 120
        case .hold: return 116
        }
    }

    /// The shoulder, as a unit point of the design space.
    func pivot(_ side: MochiSide) -> UnitPoint {
        let s = side == .left ? MochiGeometry.shoulderL : MochiGeometry.shoulderR
        return MochiGeometry.unit(s.x, s.y)
    }

    /// Hangs an arm-local point (shoulder at the origin, hanging down +y) on the body.
    static func placement(side: MochiSide, angle: Double, shoulder: CGPoint) -> CGAffineTransform {
        let radians = (side == .left ? angle : -angle) * .pi / 180
        return CGAffineTransform(translationX: shoulder.x, y: shoulder.y).rotated(by: radians)
    }

    /// Centre of the paw for an arm at `angle`.
    static func paw(side: MochiSide, angle: Double, shoulder: CGPoint) -> CGPoint {
        CGPoint(x: 0, y: 33).applying(placement(side: side, angle: angle, shoulder: shoulder))
    }
}

private struct MochiArm: View {
    let style: MochiArmStyle
    let side: MochiSide
    let angle: Double
    let shoulder: CGPoint
    let thumbPop: CGFloat
    let s: CGFloat

    private static let arm = Path(svg: "M0 0 L0 30")
    private static let paw = Path.circle(0, 33, 9)
    private static let toes = Path(svg: "M-3 38 L-3 41 M3 38 L3 41")

    var body: some View {
        let place = MochiArmStyle.placement(side: side, angle: angle, shoulder: shoulder)
        let paw = MochiArmStyle.paw(side: side, angle: angle, shoulder: shoulder)
        ZStack {
            mochiStroke(Self.arm.applying(place), MochiPalette.fur, width: 15, s: s)
            mochiFill(Self.paw.applying(place), MochiPalette.white, outline: true, s: s)
            mochiStroke(Self.toes.applying(place), MochiPalette.ink, width: 1.2, s: s).opacity(0.35)
            if style == .thumb {
                // The thumb points straight up from the paw, leaning a little toward the body.
                let lean: CGFloat = side == .left ? 1.5 : -1.5
                mochiFill(.ellipse(paw.x + lean, paw.y - 10, 4.6, 7.5), MochiPalette.white, outline: true, s: s)
                    .scaleEffect(thumbPop, anchor: MochiGeometry.unit(paw.x, paw.y - 4))
            }
        }
    }
}
