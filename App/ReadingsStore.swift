import Foundation

/// Durable on-disk log of finalized weigh-ins (including pending "Was this you?"
/// items), so readings caught in the background survive an app restart — the
/// in-memory list was lost on termination. JSON file in Application Support.
enum ReadingsStore {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("myopenscale-readings.v1.json")
    }

    static func load() -> [LoggedReading] {
        guard
            let data = try? Data(contentsOf: url),
            let readings = try? JSONDecoder().decode([LoggedReading].self, from: data)
        else { return [] }
        return readings
    }

    static func save(_ readings: [LoggedReading]) {
        guard let data = try? JSONEncoder().encode(readings) else { return }
        var fileURL = url
        try? data.write(to: fileURL, options: .atomic)
        // Health-derived data shouldn't leave the device via iCloud/device backup.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? fileURL.setResourceValues(values)
    }
}
