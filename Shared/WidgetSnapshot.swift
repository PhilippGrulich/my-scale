import Foundation

/// One point on the widget's mini weight chart.
struct WidgetPoint: Codable, Equatable {
    var date: Date
    var weightKg: Double
}

/// Snapshot the app writes after each weigh-in so a Home/Lock-Screen widget can
/// render the latest weight (+ a small recent series for the large widget's
/// chart) without touching HealthKit itself.
struct WidgetSnapshot: Codable, Equatable {
    var weightKg: Double
    var date: Date
    var trendDeltaKg: Double?
    var goalKg: Double?
    var points: [WidgetPoint] = []
}

enum WidgetSnapshotStore {
    private static let key = "myopenscale.widget.snapshot.v1"

    // Shared via the App Group so the widget's separate process can read what the
    // app writes.
    private static var defaults: UserDefaults? { UserDefaults(suiteName: MeasurementHandoff.appGroup) }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: key)
    }

    static func read() -> WidgetSnapshot? {
        guard
            let data = defaults?.data(forKey: key),
            let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return nil }
        return snapshot
    }
}
