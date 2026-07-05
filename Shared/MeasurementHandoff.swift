import Foundation

/// Handoff for the "Start Weigh-In" action. `StartMeasurementIntent` (run from
/// Siri / Spotlight / the Shortcuts app, in the app's own process) sets a
/// timestamped flag; the app consumes it on activation and arms a measurement.
///
/// The timestamp guards against a stale request arming a weigh-in much later
/// (e.g. the app wasn't opened until the next day).
///
/// Shared via the App Group so the Control Center control (a separate extension
/// process) and the app see the same flag.
enum MeasurementHandoff {
    static let appGroup = "group.com.philippgrulich.myopenscale"
    private static let key = "pendingStartMeasurementAt"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// Record a request to start a measurement (called from the intent).
    static func requestStart() {
        defaults?.set(Date().timeIntervalSince1970, forKey: key)
    }

    /// Returns true once if a fresh request is pending, clearing it. Stale
    /// requests (older than `maxAge`) are discarded without arming.
    static func consumePending(maxAge: TimeInterval = 30) -> Bool {
        guard let ts = defaults?.object(forKey: key) as? Double else { return false }
        defaults?.removeObject(forKey: key)
        return Date().timeIntervalSince1970 - ts <= maxAge
    }
}
