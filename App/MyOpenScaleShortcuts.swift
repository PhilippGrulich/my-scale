import AppIntents

/// Exposes "Start Weigh-In" to Siri, Spotlight, and the Shortcuts app without
/// the user having to build a shortcut. The same intent backs the Control Center
/// control (see the MyOpenScaleControls extension).
struct MyOpenScaleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartMeasurementIntent(),
            phrases: [
                "Start a weigh-in with \(.applicationName)",
                "Weigh in with \(.applicationName)",
                "New measurement with \(.applicationName)"
            ],
            shortTitle: "Start Weigh-In",
            systemImageName: "scalemass"
        )
    }
}
