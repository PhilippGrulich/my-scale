import AppIntents

/// "Start Weigh-In" — opens the app and arms a new measurement. Drives the
/// Control Center control, Siri, Spotlight, and the Shortcuts app. Runs in
/// whichever process invokes it (the control extension or the app), so it only
/// touches the shared `MeasurementHandoff`, never the app's view model.
struct StartMeasurementIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Weigh-In"
    static let description = IntentDescription("Opens Mochi and starts a new weight measurement.")

    /// Bring the app to the foreground after running so the weigh-in overlay shows.
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        MeasurementHandoff.requestStart()
        return .result()
    }
}
