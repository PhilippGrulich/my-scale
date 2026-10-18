import Foundation
import MyOpenScaleCore

/// The user's Mochi preferences (Settings → Mochi).
struct MochiSettings: Codable, Equatable {
    /// Master switch. Stays false until the user says yes in onboarding (or turns it on in Settings).
    var enabled = false
    var remindersEnabled = true
    var reminderMode: ReminderMode = .smart
    /// Reminder time for `.fixed`, minutes after midnight.
    var fixedMinuteOfDay = 8 * 60
    /// `.smart` normally uses the usual weigh-in time; this overrides it when set.
    var smartMinuteOverride: Int? = nil
    var haptics = true

    init() {}

    /// Tolerates missing keys so settings saved by an older build keep their values.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = MochiSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        remindersEnabled = try c.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? defaults.remindersEnabled
        reminderMode = try c.decodeIfPresent(ReminderMode.self, forKey: .reminderMode) ?? defaults.reminderMode
        fixedMinuteOfDay = try c.decodeIfPresent(Int.self, forKey: .fixedMinuteOfDay) ?? defaults.fixedMinuteOfDay
        smartMinuteOverride = try c.decodeIfPresent(Int.self, forKey: .smartMinuteOverride)
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? defaults.haptics
    }
}

/// What Mochi shows at one moment: a pose, a line, and the text on its tummy display.
struct MochiPresentation: Codable, Equatable {
    var pose: MochiPose
    var text: String
    /// Tummy display text, e.g. "80,1" or "– –".
    var display: String
}

/// Mochi's persisted state in `UserDefaults` (keys prefixed `myopenscale.mochi.`).
enum MochiStateStore {
    private static let prefix = "myopenscale.mochi."
    private static var defaults: UserDefaults { .standard }

    static var settings: MochiSettings {
        get { load(MochiSettings.self, "settings") ?? MochiSettings() }
        set { save(newValue, "settings") }
    }

    /// What Mochi already celebrated for the current goal. Nil before the first own weigh-in.
    static var progress: MochiProgressState? {
        get { load(MochiProgressState.self, "progress") }
        set { save(newValue, "progress") }
    }

    static var lineHistory: MochiLineHistory {
        get { load(MochiLineHistory.self, "lineHistory") ?? MochiLineHistory(used: [:]) }
        set { save(newValue, "lineHistory") }
    }

    /// When Mochi first looked at the app; recorded on the first read.
    static var firstLaunch: Date {
        let key = prefix + "firstLaunch"
        if let date = defaults.object(forKey: key) as? Date { return date }
        let now = Date()
        defaults.set(now, forKey: key)
        return now
    }

    /// A reaction to a background weigh-in, shown on the home screen next time the app opens.
    static var pendingHomeReaction: MochiPresentation? {
        get { load(MochiPresentation.self, "pendingHomeReaction") }
        set { save(newValue, "pendingHomeReaction") }
    }

    // MARK: - Private

    private static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = defaults.data(forKey: prefix + name) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ value: T?, _ name: String) {
        let key = prefix + name
        guard let value else { defaults.removeObject(forKey: key); return }
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
