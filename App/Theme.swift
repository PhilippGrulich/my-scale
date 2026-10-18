import SwiftUI

/// Shared visual language: a friendly health-green accent + soft background.
enum Theme {
    static let accent = Color(red: 0.13, green: 0.72, blue: 0.55)
    static let accentSecondary = Color(red: 0.20, green: 0.55, blue: 0.85)

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [accent.opacity(0.16), accentSecondary.opacity(0.06), Color(.systemBackground)],
            startPoint: .topLeading,
            endPoint: .center
        )
    }

    static var ringGradient: AngularGradient {
        AngularGradient(colors: [accent, accentSecondary, accent], center: .center)
    }

    /// The weight circle's face: white, or a raised grey in dark mode.
    static let circleFill = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .secondarySystemBackground : .white
    })

    /// The weight circle's soft mint inner ring (#e8f7f1 in light mode).
    static let circleRing = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.13, green: 0.72, blue: 0.55, alpha: 0.18)
            : UIColor(red: 0xe8 / 255, green: 0xf7 / 255, blue: 0xf1 / 255, alpha: 1)
    })
}

extension Double {
    /// "80.1" — value only, fixed fraction digits, em-dash for non-finite.
    func formatted(_ digits: Int) -> String {
        guard isFinite else { return "—" }
        return self.formatted(.number.precision(.fractionLength(digits)))
    }
}
