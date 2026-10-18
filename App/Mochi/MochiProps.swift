import SwiftUI
import MyOpenScaleCore

// Pose props around Mochi: confetti, sparkles, z's, heart, party hat, sweat drop, bell, cupcake.
// Everything is drawn in Mochi's 200×200 design space (see `MochiView`).

/// Props behind the body (confetti falls behind Mochi).
struct MochiBackProps: View {
    let pose: MochiPose
    let time: Double
    let still: Bool

    var body: some View {
        if pose == .confetti && !still {
            MochiConfetti(time: time)
        }
    }
}

/// Props in front of the body that stay put while Mochi hops.
struct MochiFrontProps: View {
    let pose: MochiPose
    let time: Double
    let still: Bool
    let s: CGFloat

    var body: some View {
        switch pose {
        case .thumbsUp:
            MochiSparkles(spots: [.init(pt(184, 38), 11, MochiPalette.bulb, 0),
                                  .init(pt(156, 24), 7, MochiPalette.blush, 0.15),
                                  .init(pt(201, 66), 6, MochiPalette.sky, 0.3)],
                          style: .pop, period: 2.2, time: time, still: still)
        case .doubleThumbs:
            MochiSparkles(spots: [.init(pt(16, 44), 8, MochiPalette.bulb, 0),
                                  .init(pt(184, 44), 8, MochiPalette.bulb, 0.4),
                                  .init(pt(70, 30), 6, MochiPalette.blush, 0.2),
                                  .init(pt(150, 26), 6, MochiPalette.sky, 0.6)],
                          style: .twinkle, period: 0.8, time: time, still: still)
        case .confetti where still:
            MochiSparkles(spots: [.init(pt(40, 34), 9, MochiPalette.bulb, 0),
                                  .init(pt(162, 30), 9, MochiPalette.blush, 0),
                                  .init(pt(100, 14), 7, MochiPalette.sky, 0)],
                          style: .twinkle, period: 1, time: 0, still: true)
        case .snoozing:
            MochiZs(time: time, still: still, s: s)
        default:
            EmptyView()
        }
    }
}

/// Props that ride along with the body (heart, party hat, sweat drop).
struct MochiHeadProps: View {
    let pose: MochiPose
    let time: Double
    let still: Bool
    let s: CGFloat

    var body: some View {
        switch pose {
        case .selfHug: MochiHearts(time: time, still: still)
        case .birthday: MochiPartyHat(s: s)
        case .squishing: MochiSweatDrop(time: time, still: still)
        default: EmptyView()
        }
    }
}

/// Props held in Mochi's right hand; the caller rotates them with the right arm.
struct MochiHeldProp: View {
    let pose: MochiPose
    let time: Double
    let still: Bool

    var body: some View {
        switch pose {
        case .bellRing: MochiBell(time: time, still: still)
        case .birthday: MochiCupcake(time: time, still: still)
        default: EmptyView()
        }
    }
}

// MARK: - Confetti

private struct MochiConfetti: View {
    let time: Double

    private struct Piece {
        let x: CGFloat
        let delay: Double
        let color: Color
        let size: CGSize
        let spin: Double
    }

    private static let period = 1.8
    private static let pieces: [Piece] = {
        let colors = [MochiPalette.bulb, MochiPalette.blush, MochiPalette.sky, MochiPalette.mint, MochiPalette.lilac]
        let xs: [CGFloat] = [26, 50, 74, 98, 122, 146, 170, 186, 38, 86, 134, 160]
        return xs.enumerated().map { i, x in
            Piece(x: x, delay: Double(i) * period / Double(xs.count) * 1.7,
                  color: colors[i % colors.count],
                  size: i % 3 == 0 ? CGSize(width: 8, height: 8) : CGSize(width: 7, height: 12),
                  spin: i.isMultiple(of: 2) ? 280 : -240)
        }
    }()

    var body: some View {
        ZStack {
            ForEach(Self.pieces.indices, id: \.self) { i in
                piece(Self.pieces[i])
            }
        }
    }

    private func piece(_ c: Piece) -> some View {
        let p = MochiKeys.phase(time, Self.period, delay: c.delay)
        let y = -10 + 160 * CGFloat(p * (0.55 + 0.45 * p))
        let x = c.x + 7 * CGFloat(sin(p * 2 * .pi + c.delay))
        let rect = CGRect(x: x - c.size.width / 2, y: y - c.size.height / 2, width: c.size.width, height: c.size.height)
        return MochiShape { $0.addRoundedRect(in: rect, cornerSize: CGSize(width: 2, height: 2)) }
            .fill(c.color)
            .rotationEffect(.degrees(c.spin * p), anchor: MochiGeometry.unit(x, y))
            .opacity(MochiKeys.kf(p, [(0, 0), (0.06, 1), (0.7, 1), (1, 0)]))
    }
}

// MARK: - Sparkles

private struct MochiSparkles: View {
    struct Spot {
        let center: CGPoint
        let radius: CGFloat
        let color: Color
        let delay: Double
        init(_ center: CGPoint, _ radius: CGFloat, _ color: Color, _ delay: Double) {
            self.center = center; self.radius = radius; self.color = color; self.delay = delay
        }
    }

    enum Style { case pop, twinkle }

    let spots: [Spot]
    let style: Style
    let period: Double
    let time: Double
    let still: Bool

    var body: some View {
        ZStack {
            ForEach(spots.indices, id: \.self) { i in
                sparkle(spots[i])
            }
        }
    }

    private func sparkle(_ spot: Spot) -> some View {
        let p = MochiKeys.phase(time, period, delay: spot.delay)
        var opacity = 1.0, scale = 1.0, rise = 0.0
        if !still {
            switch style {
            case .pop:
                opacity = MochiKeys.kf(p, [(0, 0), (0.3, 0), (0.45, 1), (0.7, 0), (1, 0)])
                scale = MochiKeys.kf(p, [(0, 0.2), (0.3, 0.2), (0.45, 1.2), (0.7, 0.6), (1, 0.6)])
                rise = MochiKeys.kf(p, [(0, 0), (0.45, 0), (0.7, -8), (1, -8)])
            case .twinkle:
                scale = MochiKeys.kf(p, [(0, 0.5), (0.5, 1.15), (1, 0.5)])
                opacity = 0.4 + 0.6 * scale / 1.15
            }
        }
        let c = pt(spot.center.x, spot.center.y + CGFloat(rise))
        let r = spot.radius
        return MochiShape { p in
            let k = 0.28 * r
            p.addLines([pt(c.x, c.y - r), pt(c.x + k, c.y - k), pt(c.x + r, c.y), pt(c.x + k, c.y + k),
                        pt(c.x, c.y + r), pt(c.x - k, c.y + k), pt(c.x - r, c.y), pt(c.x - k, c.y - k)])
            p.closeSubpath()
        }
        .fill(spot.color)
        .scaleEffect(scale, anchor: MochiGeometry.unit(c.x, c.y))
        .opacity(opacity)
    }
}

// MARK: - Z's

private struct MochiZs: View {
    let time: Double
    let still: Bool
    let s: CGFloat

    private static let letters: [(x: CGFloat, y: CGFloat, size: CGFloat, delay: Double)] = [
        (140, 60, 26, 0), (156, 46, 20, 0.8), (170, 34, 15, 1.6),
    ]

    var body: some View {
        ZStack {
            ForEach(Self.letters.indices, id: \.self) { i in
                letter(Self.letters[i])
            }
        }
    }

    private func letter(_ z: (x: CGFloat, y: CGFloat, size: CGFloat, delay: Double)) -> some View {
        let p = still ? 0 : MochiKeys.phase(time, 2.4, delay: z.delay)
        let opacity = still ? 1 : MochiKeys.kf(p, [(0, 0), (0.3, 1), (1, 0)])
        return Text(verbatim: "z")
            .font(.system(size: z.size * s, weight: .heavy, design: .rounded))
            .foregroundStyle(MochiPalette.sky)
            .position(x: (z.x + 14 * CGFloat(p)) * s, y: (z.y - 26 * CGFloat(p)) * s)
            .opacity(opacity)
    }
}

// MARK: - Heart

private struct MochiHearts: View {
    let time: Double
    let still: Bool

    var body: some View {
        let pulse = still ? 1 : MochiKeys.kf(MochiKeys.phase(time, 1), [(0, 1), (0.5, 1.25), (1, 1)])
        ZStack {
            heart(at: pt(64, 40), scale: 1)
                .scaleEffect(pulse, anchor: MochiGeometry.unit(64, 40))
            if !still {
                floating(from: pt(46, 70), delay: 0)
                floating(from: pt(156, 66), delay: 1.2)
            }
        }
    }

    private func floating(from start: CGPoint, delay: Double) -> some View {
        let p = MochiKeys.phase(time, 2.4, delay: delay)
        let c = pt(start.x + 6 * CGFloat(sin(p * 2 * .pi)), start.y - 36 * CGFloat(p))
        return heart(at: c, scale: 0.42)
            .opacity(MochiKeys.kf(p, [(0, 0), (0.2, 0.9), (0.7, 0.9), (1, 0)]))
    }

    /// The sketch's heart (40 wide), centred on `c`.
    private func heart(at c: CGPoint, scale k: CGFloat) -> some View {
        MochiShape { p in
            func q(_ x: CGFloat, _ y: CGFloat) -> CGPoint { pt(c.x + x * k, c.y + y * k) }
            p.move(to: q(0, -4))
            p.addCurve(to: q(-12, 4), control1: q(-8, -14), control2: q(-20, -6))
            p.addLine(to: q(0, 14))
            p.addLine(to: q(12, 4))
            p.addCurve(to: q(0, -4), control1: q(20, -6), control2: q(8, -14))
            p.closeSubpath()
        }
        .fill(MochiPalette.blush)
    }
}

// MARK: - Party hat

private struct MochiPartyHat: View {
    let s: CGFloat

    private static let left = pt(58, 77), right = pt(96, 63), apex = pt(64, 26)

    var body: some View {
        let (l, r, a) = (Self.left, Self.right, Self.apex)
        ZStack {
            MochiShape { p in p.addLines([l, a, r]); p.closeSubpath() }
                .fill(MochiPalette.sky)
            MochiShape { p in
                for f in [CGFloat(0.28), 0.6] {
                    p.move(to: MochiKeys.lerp(l, a, f))
                    p.addLine(to: MochiKeys.lerp(r, a, f))
                }
            }
            .stroke(MochiPalette.bulb, style: StrokeStyle(lineWidth: 4.5 * s))
            MochiShape { p in p.move(to: l); p.addLine(to: r) }
                .stroke(MochiPalette.bulb, style: StrokeStyle(lineWidth: 4 * s, lineCap: .round))
            MochiShape { $0.addEllipse(in: circleRect(a, 6)) }
                .fill(MochiPalette.blush)
        }
    }
}

// MARK: - Sweat drop

private struct MochiSweatDrop: View {
    let time: Double
    let still: Bool

    var body: some View {
        let p = still ? 0.3 : MochiKeys.phase(time, 1.4)
        let top = pt(152, 78 + 8 * CGFloat(p))
        ZStack {
            MochiShape { path in
                path.move(to: top)
                path.addQuadCurve(to: pt(top.x + 6, top.y + 13), control: pt(top.x + 6, top.y + 6))
                path.addArc(center: pt(top.x, top.y + 13), radius: 6, startAngle: .degrees(0),
                            endAngle: .degrees(180), clockwise: false)
                path.addQuadCurve(to: top, control: pt(top.x - 6, top.y + 6))
                path.closeSubpath()
            }
            .fill(Color(red: 0.62, green: 0.85, blue: 1))
            MochiShape { $0.addEllipse(in: circleRect(pt(top.x - 2, top.y + 12), 1.8)) }
                .fill(Color.white.opacity(0.8))
        }
        .opacity(still ? 1 : MochiKeys.kf(p, [(0, 0), (0.2, 1), (0.75, 1), (1, 0)]))
    }
}

// MARK: - Bell

/// A ringing bell held up in the right hand (right-side coordinates).
private struct MochiBell: View {
    let time: Double
    let still: Bool

    var body: some View {
        let p = MochiKeys.phase(time, 1.6)
        let swing = still ? 0 : MochiKeys.kf(p, [(0, 0), (0.1, -18), (0.2, 18), (0.3, -18), (0.4, 18), (0.5, 0), (1, 0)])
        let ringing = still ? 0.8 : min(1, abs(swing) / 10)
        let gold = Color(red: 0.88, green: 0.66, blue: 0.12)
        ZStack {
            MochiShape { p in
                p.move(to: pt(160, 58)); p.addQuadCurve(to: pt(160, 76), control: pt(155, 67))
                p.move(to: pt(204, 58)); p.addQuadCurve(to: pt(204, 76), control: pt(209, 67))
            }
            .stroke(gold, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .opacity(ringing)
            ZStack {
                let bell = MochiShape { p in
                    p.move(to: pt(172, 70))
                    p.addQuadCurve(to: pt(182, 54), control: pt(172, 54))
                    p.addQuadCurve(to: pt(192, 70), control: pt(192, 54))
                    p.addLine(to: pt(195, 80))
                    p.addLine(to: pt(169, 80))
                    p.closeSubpath()
                }
                MochiShape { $0.addEllipse(in: circleRect(pt(182, 85), 3.8)) }.fill(gold)
                bell.fill(MochiPalette.bulb)
                bell.stroke(gold, lineWidth: 1.5)
                MochiShape { $0.addEllipse(in: circleRect(pt(182, 51), 3)) }.fill(gold)
                MochiShape { p in p.move(to: pt(177, 62)); p.addQuadCurve(to: pt(176, 74), control: pt(175, 67)) }
                    .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            .rotationEffect(.degrees(swing), anchor: MochiGeometry.unit(182, 51))
        }
    }
}

// MARK: - Cupcake

/// A birthday cupcake with a flickering candle, held up in the right hand (right-side coordinates).
private struct MochiCupcake: View {
    let time: Double
    let still: Bool

    var body: some View {
        let flicker = still ? 1 : MochiKeys.kf(MochiKeys.phase(time, 0.35), [(0, 0.85), (0.5, 1.15), (1, 0.85)])
        ZStack {
            MochiShape { p in p.addLines([pt(170, 78), pt(194, 78), pt(190, 95), pt(174, 95)]); p.closeSubpath() }
                .fill(MochiPalette.blush)
            MochiShape { p in
                for x in [CGFloat(178), 182, 186] { p.move(to: pt(x, 80)); p.addLine(to: pt(x, 93)) }
            }
            .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
            MochiShape { p in
                p.move(to: pt(167, 80))
                p.addQuadCurve(to: pt(182, 64), control: pt(166, 64))
                p.addQuadCurve(to: pt(197, 80), control: pt(198, 64))
                p.closeSubpath()
            }
            .fill(Color(red: 1, green: 0.96, blue: 0.9))
            MochiShape { $0.addRoundedRect(in: CGRect(x: 180, y: 52, width: 4, height: 13), cornerSize: CGSize(width: 1.5, height: 1.5)) }
                .fill(MochiPalette.sky)
            MochiShape { $0.addEllipse(in: CGRect(x: 179, y: 41, width: 6, height: 10)) }
                .fill(Color(red: 1, green: 0.62, blue: 0.2))
                .scaleEffect(x: 1, y: flicker, anchor: MochiGeometry.unit(182, 51))
        }
    }
}
