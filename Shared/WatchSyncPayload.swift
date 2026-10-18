import Foundation

/// What the phone tells the watch (WatchConnectivity application context):
/// the bits of the iPhone profile the watch can't read from Apple Health —
/// the goal, the user's name for Mochi, and whether Mochi is switched on.
/// App Groups don't cross the phone↔watch boundary, hence this.
struct WatchSyncPayload: Codable, Equatable {
    var name: String?
    var goalKg: Double?
    var goalType: String?
    var goalStartKg: Double?
    var mochiEnabled: Bool

    private static let key = "payload"

    var dictionary: [String: Any] {
        guard let data = try? JSONEncoder().encode(self) else { return [:] }
        return [Self.key: data]
    }

    init(name: String?, goalKg: Double?, goalType: String?, goalStartKg: Double?, mochiEnabled: Bool) {
        self.name = name
        self.goalKg = goalKg
        self.goalType = goalType
        self.goalStartKg = goalStartKg
        self.mochiEnabled = mochiEnabled
    }

    init?(dictionary: [String: Any]) {
        guard let data = dictionary[Self.key] as? Data,
              let decoded = try? JSONDecoder().decode(WatchSyncPayload.self, from: data) else { return nil }
        self = decoded
    }
}
