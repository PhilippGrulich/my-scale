import SwiftUI

/// Standalone watchOS app entry point. Owns the single `WatchAppModel` and shows
/// the dashboard; the weigh-in flow is presented from there.
@main
struct MyOpenScaleWatchApp: App {
    @StateObject private var model = WatchAppModel()

    var body: some Scene {
        WindowGroup {
            WatchDashboardView()
                .environmentObject(model)
        }
    }
}

/// Small watch-local formatting helper (the App target's `Double.formatted(_:)`
/// lives outside this target). Named to match the codebase idiom and avoid
/// shadowing the stdlib `Double.rounded()`.
extension Double {
    func formatted(_ places: Int) -> String {
        String(format: "%.\(places)f", self)
    }
}
