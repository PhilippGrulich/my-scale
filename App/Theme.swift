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
}

extension Double {
    /// "80.1" — value only, fixed fraction digits, em-dash for non-finite.
    func formatted(_ digits: Int) -> String {
        guard isFinite else { return "—" }
        return self.formatted(.number.precision(.fractionLength(digits)))
    }
}
