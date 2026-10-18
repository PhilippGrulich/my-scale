import SwiftUI

/// The watch's copy of the app colours (the iOS `Theme` uses UIKit dynamic
/// colours that watchOS doesn't have). Mochi's shared drawing reads `Theme.accent`.
enum Theme {
    static let accent = Color(red: 0.13, green: 0.72, blue: 0.55)
    static let accentSecondary = Color(red: 0.20, green: 0.55, blue: 0.85)
}
