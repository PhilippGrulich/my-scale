import Foundation

/// One point on the widget's mini weight chart.
struct WidgetPoint: Codable, Equatable {
    var date: Date
    var weightKg: Double
}

/// One value on the Progress widget, fully prepared by the app (localized
/// title, formatted value) so the widget only lays it out.
struct WidgetMetric: Codable, Equatable {
    var id: String
    var title: String
    var symbol: String
    var value: String
    var unit: String
    /// 30-day change, already formatted with sign and unit ("−0,8 kg").
    var change: String?
    /// Whether that change goes the healthy way (nil = neutral).
    var changeIsGood: Bool?
}

/// Snapshot the app writes after each weigh-in so a Home/Lock-Screen widget can
/// render the latest weight (+ a small recent series for the large widget's
/// chart) without touching HealthKit itself.
struct WidgetSnapshot: Codable, Equatable {
    var weightKg: Double
    var date: Date
    /// Change since the previous weigh-in (kept for older widget builds).
    var trendDeltaKg: Double?
    var goalKg: Double?
    /// Daily weigh-ins of the last 30 days (one dot per day).
    var points: [WidgetPoint] = []
    // Added later — optional so older snapshots still decode.
    /// Smoothed trend for the same window (the line).
    var trendPoints: [WidgetPoint]?
    /// Change of the smoothed trend over 30 days, like the app's "30-day trend".
    var monthTrendKg: Double?
    /// The app's calm chart axis, so widget and app scale the same way.
    var axisLowerKg: Double?
    var axisUpperKg: Double?
    /// Progress from goal start to goal, 0…1 (nil without a goal).
    var goalProgress: Double?
    /// Values for the Progress widget, most important first (weight, body
    /// fat, muscle, water, visceral fat — only those with data).
    var metrics: [WidgetMetric]?
    /// Plan status ("Im Plan", "0,6 kg voraus") or forecast text, localized.
    var goalStatus: String?
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
