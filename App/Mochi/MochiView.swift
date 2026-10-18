import SwiftUI
import MyOpenScaleCore

/// Mochi, the app's soft talking-scale mascot. Drawn from SwiftUI shapes in a 200×200
/// design space (the sketches in `docs/superpowers/specs/mochi-sketches/`) scaled to `size`.
/// Each pose loops its own animation; Reduce Motion holds a still frame and crossfades poses.
struct MochiView: View {
    let pose: MochiPose
    var display: String = ""
    var size: CGFloat = 160
    var onTap: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var taps = 0

    var body: some View {
        ZStack {
            MochiStage(pose: pose, display: display, size: size, still: reduceMotion)
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
        TimelineView(.animation) { context in
            MochiFigure(pose: pose, display: display, size: size,
                        time: max(0, context.date.timeIntervalSince(start)), still: still)
        }
    }
}

// MARK: - Shared drawing helpers

/// Colours from the approved sketches.
enum MochiPalette {
    static let body = Theme.accent                      // #21B88C
    static let bodyLight = Color(red: 0.36, green: 0.84, blue: 0.68)
    static let bodyDeep = Color(red: 0.09, green: 0.62, blue: 0.47)
    static let crease = hex(0x178F6C)
    static let ink = hex(0x1D2B36)
    static let blush = hex(0xFF8FA3)
    static let bulb = hex(0xFFD166)
    static let bulbLit = hex(0xFFF3B0)
    static let screen = hex(0xF4FFFB)
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
    /// Mirrors design-space x around the body's centre line.
    static let mirror = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: design, ty: 0)

    static func unit(_ x: CGFloat, _ y: CGFloat) -> UnitPoint {
        UnitPoint(x: x / design, y: y / design)
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

    func path(in rect: CGRect) -> Path {
        var path = Path()
        build(&path)
        let k = rect.width / MochiGeometry.design
        return path.applying(CGAffineTransform(scaleX: k, y: rect.height / MochiGeometry.design)
            .translatedBy(x: rect.minX / k, y: rect.minY / k))
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
        let thumbAnchor = MochiGeometry.unit(178, 136)

        ZStack {
            MochiGroundShadow(lift: m.lift)
            MochiBackProps(pose: pose, time: time, still: still)
            ZStack {
                MochiAntenna(droop: look.droop, glow: m.glow, dim: look.dimBulb, s: s)
                    .rotationEffect(.degrees(m.antennaSway), anchor: MochiGeometry.unit(100, 64))
                MochiBody(s: s)
                MochiFace(eyes: look.eyes, mouth: look.mouth, eyeOpen: m.eyeOpen, glance: m.glance,
                          starPulse: m.starPulse, s: s)
                MochiDisplay(text: display, s: s)
                MochiHeadProps(pose: pose, time: time, still: still, s: s)
                MochiArm(style: look.leftArm, side: .left, angle: m.leftArm, s: s)
                MochiArm(style: look.rightArm, side: .right, angle: m.rightArm, s: s)
                    .scaleEffect(m.thumbPop, anchor: thumbAnchor)
                    .rotationEffect(.degrees(m.thumbTilt), anchor: thumbAnchor)
                MochiHeldProp(pose: pose, time: time, still: still)
                    .rotationEffect(.degrees(m.rightArm), anchor: look.rightArm.pivot(.right))
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
    var lift: CGFloat = 0
    var squashX: CGFloat = 1
    var squashY: CGFloat = 1
    var tilt: Double = 0
    var antennaSway: Double = 0
    var leftArm: Double = 0
    var rightArm: Double = 0
    var thumbPop: CGFloat = 1
    var thumbTilt: Double = 0
    var eyeOpen: CGFloat = 1
    var glance: CGFloat = 0
    var starPulse: CGFloat = 0
    var glow: Double = 0

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

    /// Reduce Motion: a single readable frame of the pose.
    private mutating func settle(_ pose: MochiPose) {
        switch pose {
        case .helloWave: leftArm = -12
        case .thumbsUp: thumbTilt = -4; glow = 0.6
        case .doubleThumbs, .confetti: glow = 0.6
        case .sadWave: leftArm = -8; squashX = 1.02; squashY = 0.97
        case .squishing: squashX = 1.1; squashY = 0.86; leftArm = 30; rightArm = -30
        default: break
        }
    }

    private mutating func animate(_ pose: MochiPose, _ t: Double) {
        typealias K = MochiKeys
        let breath = K.kf(K.phase(t, 3), [(0, 0), (0.5, 1), (1, 0)])
        switch pose {
        case .idle:
            squashX = 1 + 0.04 * breath; squashY = 1 - 0.03 * breath
            antennaSway = -2 + 4 * breath
            leftArm = 3 * breath; rightArm = -3 * breath

        case .helloWave:
            let p = K.phase(t, 1.4)
            squashX = K.kf(p, [(0, 1), (0.3, 1.08), (0.55, 0.95), (0.8, 1.04), (1, 1)])
            squashY = K.kf(p, [(0, 1), (0.3, 0.9), (0.55, 1.06), (0.8, 0.96), (1, 1)])
            lift = K.kf(p, [(0, 0), (0.3, 0), (0.55, -14), (0.8, 0), (1, 0)])
            antennaSway = K.kf(p, [(0, 0), (0.55, -8), (0.8, 6), (1, 0)])
            let w = K.phase(t, 0.9)
            leftArm = K.kf(w, [(0, 0), (0.25, -30), (0.75, 20), (1, 0)])
            tilt = K.kf(w, [(0, 0), (0.25, -3), (0.75, 2), (1, 0)])

        case .thumbsUp:
            let p = K.phase(t, 2.2)
            squashX = K.kf(p, [(0, 1), (0.12, 1.14), (0.3, 0.92), (0.48, 1.08), (0.6, 1), (1, 1)])
            squashY = K.kf(p, [(0, 1), (0.12, 0.82), (0.3, 1.1), (0.48, 0.93), (0.6, 1), (1, 1)])
            lift = K.kf(p, [(0, 0), (0.12, 0), (0.3, -22), (0.48, 0), (1, 0)])
            tilt = K.kf(p, [(0, 0), (0.12, 0), (0.3, -6), (0.85, -6), (1, 0)])
            antennaSway = K.kf(p, [(0, 0), (0.3, 7), (0.48, -6), (0.62, 0), (1, 0)])
            thumbPop = K.kf(p, [(0, 0.5), (0.2, 0.5), (0.38, 1.25), (0.5, 1), (0.88, 1), (1, 0.5)])
            thumbTilt = K.kf(p, [(0, 25), (0.2, 25), (0.38, -12), (0.5, -4), (0.88, -4), (1, 25)])
            glow = K.kf(p, [(0, 0), (0.3, 0), (0.4, 1), (0.6, 0.35), (0.9, 0.35), (1, 0)])

        case .doubleThumbs:
            let p = K.phase(t, 1.6)
            squashX = K.kf(p, [(0, 1), (0.2, 1.12), (0.4, 0.9), (0.6, 1.1), (0.75, 0.98), (0.88, 1.03), (1, 1)])
            squashY = K.kf(p, [(0, 1), (0.2, 0.86), (0.4, 1.12), (0.6, 0.9), (0.75, 1.04), (0.88, 0.97), (1, 1)])
            lift = K.kf(p, [(0, 0), (0.2, 0), (0.4, -26), (0.6, 0), (0.75, -8), (0.88, 0), (1, 0)])
            antennaSway = K.kf(p, [(0, 0), (0.4, -8), (0.6, 8), (0.88, -3), (1, 0)])
            let q = K.phase(t, 0.8)
            let pump = K.kf(q, [(0, 0), (0.4, 1), (0.6, 1), (1, 0)])
            leftArm = -16 * pump; rightArm = 16 * pump
            starPulse = CGFloat(K.kf(q, [(0, 0), (0.5, 1), (1, 0)]))
            glow = 0.5 + 0.5 * pump

        case .confetti:
            let p = K.phase(t, 1.6)
            squashX = K.kf(p, [(0, 1), (0.14, 1.16), (0.38, 0.88), (0.62, 1), (0.72, 1.12), (0.86, 0.98), (1, 1)])
            squashY = K.kf(p, [(0, 1), (0.14, 0.8), (0.38, 1.16), (0.62, 1), (0.72, 0.88), (0.86, 1.02), (1, 1)])
            lift = K.kf(p, [(0, 0), (0.14, 0), (0.4, -32), (0.66, 0), (1, 0)])
            antennaSway = K.kf(p, [(0, 0), (0.4, -10), (0.7, 8), (1, 0)])
            glow = K.kf(p, [(0, 0.3), (0.4, 1), (1, 0.3)])
            leftArm = K.kf(K.phase(t, 0.5), [(0, -8), (0.5, 10), (1, -8)])
            rightArm = -leftArm

        case .selfHug:
            tilt = K.kf(K.phase(t, 2.6), [(0, -3), (0.5, 3), (1, -3)])
            let squeeze = K.kf(K.phase(t, 1.3), [(0, 0), (0.5, 1), (1, 0)])
            squashX = 1 + 0.03 * squeeze; squashY = 1 - 0.025 * squeeze
            antennaSway = -tilt * 1.5
            leftArm = 4 * squeeze; rightArm = -4 * squeeze

        case .bellRing:
            let p = K.phase(t, 1.6)
            tilt = K.kf(p, [(0, 0), (0.25, -4), (0.75, 4), (1, 0)])
            antennaSway = -tilt * 2
            rightArm = K.kf(p, [(0, 0), (0.1, -6), (0.2, 4), (0.3, -6), (0.4, 4), (0.5, 0), (1, 0)])

        case .snoozing:
            let slow = K.kf(K.phase(t, 3.6), [(0, 0), (0.5, 1), (1, 0)])
            squashX = 1 + 0.035 * slow; squashY = 1 - 0.03 * slow
            antennaSway = 4 * slow

        case .sadWave:
            let sway = K.kf(K.phase(t, 3.6), [(0, 0), (0.5, 1), (1, 0)])
            squashX = 1.02; squashY = 0.97
            tilt = -2 + 3 * sway
            antennaSway = 4 * sway
            leftArm = K.kf(K.phase(t, 1.8), [(0, 0), (0.3, -14), (0.6, 6), (1, 0)])

        case .waiting:
            squashX = 1 + 0.03 * breath; squashY = 1 - 0.025 * breath
            glance = CGFloat(K.kf(K.phase(t, 3.4), [(0, 0), (0.1, -5), (0.4, -5), (0.5, 5), (0.8, 5), (0.9, 0), (1, 0)]))
            tilt = Double(glance) * 0.5
            antennaSway = Double(glance) * 1.2

        case .squishing:
            let wobble = sin(t * 2 * .pi * 3.2)
            let rock = sin(t * 2 * .pi * 1.7)
            squashX = 1.12 + 0.03 * wobble; squashY = 0.84 - 0.03 * wobble
            tilt = 1.8 * rock
            antennaSway = 6 * sin(t * 2 * .pi * 1.7 + 1)
            leftArm = 30 + 6 * wobble; rightArm = -leftArm

        case .birthday:
            let p = K.phase(t, 1.6)
            squashX = K.kf(p, [(0, 1), (0.3, 1.06), (0.5, 0.96), (0.7, 1.03), (1, 1)])
            squashY = K.kf(p, [(0, 1), (0.3, 0.92), (0.5, 1.05), (0.7, 0.97), (1, 1)])
            lift = K.kf(p, [(0, 0), (0.3, 0), (0.5, -10), (0.7, 0), (1, 0)])
            antennaSway = K.kf(p, [(0, 0), (0.5, -5), (0.75, 4), (1, 0)])
            leftArm = K.kf(K.phase(t, 0.8), [(0, -8), (0.5, 10), (1, -8)])
            rightArm = K.kf(p, [(0, 0), (0.5, -4), (1, 0)])
            glow = 0.4
        }
    }
}

// MARK: - Look

private enum MochiEyes { case open, wide, wink, stars, happy, sleepy, squeezed, sad }
private enum MochiMouth { case smile, openSmile, tongueGrin, bigGrin, cheer, softSmile, oh, snore, frown, wobbly }

/// What a pose looks like when standing still: expression, arm shapes, antenna.
private struct MochiLook {
    var eyes = MochiEyes.open
    var mouth = MochiMouth.smile
    var leftArm = MochiArmStyle.rest
    var rightArm = MochiArmStyle.rest
    var droop: CGFloat = 0
    var dimBulb = false

    init(_ pose: MochiPose) {
        switch pose {
        case .idle: break
        case .helloWave: mouth = .openSmile; leftArm = .wave
        case .thumbsUp: eyes = .wink; mouth = .tongueGrin; rightArm = .thumb
        case .doubleThumbs: eyes = .stars; mouth = .bigGrin; leftArm = .thumb; rightArm = .thumb
        case .confetti: eyes = .happy; mouth = .cheer; leftArm = .up; rightArm = .up
        case .selfHug: mouth = .softSmile; leftArm = .hug; rightArm = .hug
        case .bellRing: eyes = .wide; mouth = .oh; rightArm = .hold
        case .snoozing: eyes = .sleepy; mouth = .snore; droop = 0.45; dimBulb = true
        case .sadWave: eyes = .sad; mouth = .frown; leftArm = .smallWave; droop = 1; dimBulb = true
        case .waiting: mouth = .softSmile
        case .squishing: eyes = .squeezed; mouth = .wobbly
        case .birthday: eyes = .happy; mouth = .openSmile; leftArm = .up; rightArm = .hold
        }
    }
}

// MARK: - Body parts

private struct MochiGroundShadow: View {
    let lift: CGFloat

    var body: some View {
        MochiShape { $0.addEllipse(in: CGRect(x: 38, y: 177, width: 124, height: 14)) }
            .fill(Color.black.opacity(0.08))
            .scaleEffect(max(0.6, 1 + lift / 70), anchor: MochiGeometry.unit(100, 184))
    }
}

private struct MochiAntenna: View {
    let droop: CGFloat
    let glow: Double
    let dim: Bool
    let s: CGFloat

    var body: some View {
        let lerp = MochiKeys.lerp
        let tip = lerp(pt(110, 34), pt(119, 50), droop)
        let bend = lerp(pt(98, 40), pt(106, 36), droop)
        let bulb = lerp(pt(112, 32), pt(122, 55), droop)
        let radius = 8 * (1 + 0.5 * CGFloat(glow))
        let lit = MochiPalette.bulb.mix(with: MochiPalette.bulbLit, by: glow)

        ZStack {
            MochiShape { p in
                p.move(to: pt(100, 66))
                p.addQuadCurve(to: tip, control: bend)
            }
            .stroke(MochiPalette.body, style: StrokeStyle(lineWidth: 6 * s, lineCap: .round))
            if glow > 0.01 {
                MochiShape { $0.addEllipse(in: circleRect(bulb, 17)) }
                    .fill(MochiPalette.bulb.opacity(0.6 * glow))
                    .blur(radius: 5 * s)
            }
            MochiShape { $0.addEllipse(in: circleRect(bulb, radius)) }
                .fill(dim ? MochiPalette.bulb.mix(with: .gray, by: 0.35) : lit)
            MochiShape { $0.addEllipse(in: circleRect(pt(bulb.x - 2.5, bulb.y - 2.5), radius * 0.3)) }
                .fill(Color.white.opacity(0.7))
        }
    }
}

private struct MochiBody: View {
    let s: CGFloat

    var body: some View {
        ZStack {
            MochiShape { p in
                p.move(to: pt(30, 150))
                p.addQuadCurve(to: pt(100, 60), control: pt(22, 70))
                p.addQuadCurve(to: pt(170, 150), control: pt(178, 70))
                p.addQuadCurve(to: pt(100, 176), control: pt(168, 176))
                p.addQuadCurve(to: pt(30, 150), control: pt(32, 176))
                p.closeSubpath()
            }
            .fill(LinearGradient(colors: [MochiPalette.bodyLight, MochiPalette.body, MochiPalette.bodyDeep],
                                 startPoint: MochiGeometry.unit(100, 62), endPoint: MochiGeometry.unit(100, 176)))
            // Jelly shine.
            MochiShape { p in
                p.move(to: pt(48, 96))
                p.addQuadCurve(to: pt(100, 68), control: pt(70, 70))
            }
            .stroke(Color.white.opacity(0.32), style: StrokeStyle(lineWidth: 8 * s, lineCap: .round))
            MochiShape { $0.addEllipse(in: circleRect(pt(41, 112), 3.5)) }
                .fill(Color.white.opacity(0.3))
            // Blush.
            MochiShape { p in
                p.addEllipse(in: CGRect(x: 51, y: 123, width: 22, height: 12))
                p.addEllipse(in: CGRect(x: 127, y: 123, width: 22, height: 12))
            }
            .fill(MochiPalette.blush.opacity(0.8))
        }
    }
}

/// The little screen on Mochi's tummy.
private struct MochiDisplay: View {
    let text: String
    let s: CGFloat

    var body: some View {
        ZStack {
            MochiShape { $0.addRoundedRect(in: CGRect(x: 70, y: 148, width: 60, height: 16), cornerSize: CGSize(width: 8, height: 8)) }
                .fill(MochiPalette.screen.opacity(0.92))
            Text(verbatim: text)
                .font(.system(size: 12 * s, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(MochiPalette.crease)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: 54 * s)
                .position(x: 100 * s, y: 156 * s)
        }
    }
}

private struct MochiFace: View {
    let eyes: MochiEyes
    let mouth: MochiMouth
    let eyeOpen: CGFloat
    let glance: CGFloat
    let starPulse: CGFloat
    let s: CGFloat

    private var ink: Color { MochiPalette.ink }
    private func line(_ width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width * s, lineCap: .round, lineJoin: .round)
    }

    var body: some View {
        ZStack {
            eyesView.offset(x: glance * s)
            mouthView
        }
    }

    @ViewBuilder private var eyesView: some View {
        switch eyes {
        case .open: blinking(roundEyes(radius: 8))
        case .wide: blinking(roundEyes(radius: 9.5))
        case .sad:
            ZStack {
                blinking(roundEyes(radius: 8))
                MochiShape { p in
                    p.move(to: pt(68, 99)); p.addQuadCurve(to: pt(86, 93), control: pt(78, 98))
                    p.move(to: pt(132, 99)); p.addQuadCurve(to: pt(114, 93), control: pt(122, 98))
                }
                .stroke(ink, style: line(3.5))
            }
        case .wink:
            ZStack {
                MochiShape { p in
                    p.move(to: pt(66, 112)); p.addQuadCurve(to: pt(88, 112), control: pt(77, 98))
                }
                .stroke(ink, style: line(6))
                eye(at: pt(124, 106), radius: 11)
            }
        case .stars:
            ZStack {
                star(at: pt(78, 110))
                star(at: pt(122, 110))
            }
        case .happy:
            MochiShape { p in
                p.move(to: pt(69, 113)); p.addQuadCurve(to: pt(87, 113), control: pt(78, 101))
                p.move(to: pt(113, 113)); p.addQuadCurve(to: pt(131, 113), control: pt(122, 101))
            }
            .stroke(ink, style: line(5.5))
        case .sleepy:
            MochiShape { p in
                p.move(to: pt(70, 110)); p.addQuadCurve(to: pt(86, 110), control: pt(78, 117))
                p.move(to: pt(114, 110)); p.addQuadCurve(to: pt(130, 110), control: pt(122, 117))
            }
            .stroke(ink, style: line(5))
        case .squeezed:
            MochiShape { p in
                p.move(to: pt(71, 103)); p.addLine(to: pt(85, 110)); p.addLine(to: pt(71, 117))
                p.move(to: pt(129, 103)); p.addLine(to: pt(115, 110)); p.addLine(to: pt(129, 117))
            }
            .stroke(ink, style: line(5))
        }
    }

    private func blinking(_ eyes: some View) -> some View {
        eyes.scaleEffect(x: 1, y: max(0.08, eyeOpen), anchor: MochiGeometry.unit(100, 110))
    }

    private func roundEyes(radius r: CGFloat) -> some View {
        ZStack {
            eye(at: pt(78, 110), radius: r)
            eye(at: pt(122, 110), radius: r)
        }
    }

    /// A glossy dark eye with two highlights.
    private func eye(at c: CGPoint, radius r: CGFloat) -> some View {
        ZStack {
            MochiShape { $0.addEllipse(in: circleRect(c, r)) }.fill(ink)
            MochiShape { p in
                p.addEllipse(in: circleRect(pt(c.x + 0.34 * r, c.y - 0.4 * r), 0.36 * r))
                p.addEllipse(in: circleRect(pt(c.x - 0.36 * r, c.y + 0.38 * r), 0.17 * r))
            }
            .fill(Color.white)
        }
    }

    private func star(at c: CGPoint) -> some View {
        let points: [CGPoint] = [pt(0, -14), pt(4, -5), pt(14, -4), pt(6, 2), pt(9, 12),
                                 pt(0, 6), pt(-9, 12), pt(-6, 2), pt(-14, -4), pt(-4, -5)]
        let shape = MochiShape { p in
            p.addLines(points.map { pt(c.x + $0.x, c.y + $0.y) })
            p.closeSubpath()
        }
        return ZStack {
            shape.fill(ink)
            shape.stroke(ink, style: line(2.5))
        }
        .scaleEffect(1 + 0.3 * starPulse, anchor: MochiGeometry.unit(c.x, c.y))
        .rotationEffect(.degrees(25 * Double(starPulse)), anchor: MochiGeometry.unit(c.x, c.y))
    }

    @ViewBuilder private var mouthView: some View {
        switch mouth {
        case .smile:
            MochiShape { p in p.move(to: pt(88, 128)); p.addQuadCurve(to: pt(112, 128), control: pt(100, 140)) }
                .stroke(ink, style: line(5))
        case .softSmile:
            MochiShape { p in p.move(to: pt(91, 130)); p.addQuadCurve(to: pt(109, 130), control: pt(100, 137)) }
                .stroke(ink, style: line(4))
        case .frown:
            MochiShape { p in p.move(to: pt(90, 135)); p.addQuadCurve(to: pt(110, 135), control: pt(100, 127)) }
                .stroke(ink, style: line(4))
        case .wobbly:
            MochiShape { p in
                p.move(to: pt(88, 132))
                p.addQuadCurve(to: pt(100, 132), control: pt(94, 127))
                p.addQuadCurve(to: pt(112, 132), control: pt(106, 137))
            }
            .stroke(ink, style: line(4))
        case .oh:
            MochiShape { $0.addEllipse(in: CGRect(x: 94, y: 125, width: 12, height: 14)) }.fill(ink)
        case .snore:
            MochiShape { $0.addEllipse(in: CGRect(x: 95, y: 128, width: 10, height: 8)) }.fill(ink)
        case .openSmile:
            openMouth(from: pt(88, 127), to: pt(112, 127), depth: 144, tongue: nil)
        case .tongueGrin:
            openMouth(from: pt(80, 124), to: pt(122, 124), depth: 156,
                      tongue: (pt(90, 138), pt(112, 138), 150, 132))
        case .bigGrin:
            openMouth(from: pt(82, 128), to: pt(118, 128), depth: 154,
                      tongue: (pt(90, 141), pt(110, 141), 151, 136))
        case .cheer:
            openMouth(from: pt(86, 126), to: pt(114, 126), depth: 148,
                      tongue: (pt(92, 137), pt(108, 137), 145, 133))
        }
    }

    /// A "D"-shaped open mouth; `tongue` is (left, right, bottom control y, top control y).
    private func openMouth(from a: CGPoint, to b: CGPoint, depth: CGFloat,
                           tongue: (CGPoint, CGPoint, CGFloat, CGFloat)?) -> some View {
        let mouth = MochiShape { p in
            p.move(to: a)
            p.addQuadCurve(to: b, control: pt((a.x + b.x) / 2, depth))
            p.closeSubpath()
        }
        return ZStack {
            mouth.fill(ink)
            mouth.stroke(ink, style: line(2))
            if case let (l, r, bottom, top)? = tongue {
                MochiShape { p in
                    let mid = (l.x + r.x) / 2
                    p.move(to: l)
                    p.addQuadCurve(to: r, control: pt(mid, bottom))
                    p.addQuadCurve(to: l, control: pt(mid, top))
                    p.closeSubpath()
                }
                .fill(MochiPalette.blush)
            }
        }
    }
}

// MARK: - Arms

enum MochiSide { case left, right }

/// Arm shapes, drawn for the left side; the right side mirrors them.
enum MochiArmStyle {
    case rest, wave, smallWave, up, hug, thumb, hold

    /// (shoulder, control, hand) in left-side design coordinates.
    private var curve: (CGPoint, CGPoint, CGPoint) {
        switch self {
        case .rest: return (pt(32, 132), pt(18, 140), pt(20, 152))
        case .wave: return (pt(34, 120), pt(14, 104), pt(18, 84))
        case .smallWave: return (pt(34, 124), pt(20, 118), pt(18, 102))
        case .up: return (pt(34, 118), pt(16, 96), pt(22, 72))
        case .hug: return (pt(34, 120), pt(60, 146), pt(84, 139))
        case .thumb: return (pt(36, 132), pt(20, 126), pt(16, 110))
        case .hold: return (pt(34, 124), pt(18, 112), pt(20, 94))
        }
    }

    /// Waving and cheering hands get a little round mitten.
    var hasMitten: Bool { self == .wave || self == .smallWave || self == .up }

    func pivot(_ side: MochiSide) -> UnitPoint {
        let shoulder = curve.0
        return MochiGeometry.unit(side == .left ? shoulder.x : MochiGeometry.design - shoulder.x, shoulder.y)
    }

    func addArm(to p: inout Path) {
        let (shoulder, control, hand) = curve
        p.move(to: shoulder)
        p.addQuadCurve(to: hand, control: control)
    }

    func addMitten(to p: inout Path) {
        p.addEllipse(in: circleRect(curve.2, 8))
    }
}

private struct MochiArm: View {
    let style: MochiArmStyle
    let side: MochiSide
    let angle: Double
    let s: CGFloat

    var body: some View {
        let style = self.style
        let mirrored = side == .right
        ZStack {
            MochiShape { p in
                style.addArm(to: &p)
                if mirrored { p = p.applying(MochiGeometry.mirror) }
            }
            .stroke(style == .hug ? MochiPalette.crease : MochiPalette.body,
                    style: StrokeStyle(lineWidth: 13 * s, lineCap: .round))
            if style.hasMitten {
                MochiShape { p in
                    style.addMitten(to: &p)
                    if mirrored { p = p.applying(MochiGeometry.mirror) }
                }
                .fill(MochiPalette.body)
            }
            if style == .thumb {
                MochiThumbHand(side: side, s: s)
            }
        }
        .rotationEffect(.degrees(angle), anchor: style.pivot(side))
    }
}

/// Thumbs-up hand: a chunky mitten fist, the thumb up on its body-facing side, curled-finger creases.
/// Local coordinates come from the approved `thumbR` symbol in `thumbs-v2.html`.
private struct MochiThumbHand: View {
    let side: MochiSide
    let s: CGFloat

    var body: some View {
        let place = side == .right
            ? CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 170, ty: 96)
            : CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 30, ty: 96)
        ZStack {
            MochiShape { p in
                p.move(to: pt(3, 4))
                p.addQuadCurve(to: pt(12, -25), control: pt(-1, -23))
                p.addQuadCurve(to: pt(19, -10), control: pt(21, -25))
                p.addLine(to: pt(17, 4))
                p.closeSubpath()
                p.addRoundedRect(in: CGRect(x: 0, y: 0, width: 36, height: 28), cornerSize: CGSize(width: 12, height: 12))
                p = p.applying(place)
            }
            .fill(MochiPalette.body)
            MochiShape { p in
                p.move(to: pt(9, -18))
                p.addQuadCurve(to: pt(9, -4), control: pt(8, -10))
                p = p.applying(place)
            }
            .stroke(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 2.5 * s, lineCap: .round))
            MochiShape { p in
                for (y, end) in [(CGFloat(8), CGFloat(31)), (15, 32), (22, 30)] {
                    p.move(to: pt(18, y)); p.addLine(to: pt(end, y))
                }
                p = p.applying(place)
            }
            .stroke(MochiPalette.crease, style: StrokeStyle(lineWidth: 2.6 * s, lineCap: .round))
        }
    }
}
