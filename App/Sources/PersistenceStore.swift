import Foundation

/// The full persisted state, written atomically to Application Support.
struct PersistedState: Codable, Equatable {
    var profiles: [StoredProfile] = []
    var measurements: [StoredMeasurement] = []
    var ha: HAConfig = HAConfig()
}

/// Lightweight JSON-file repository (iOS 16-friendly; no SwiftData dependency).
/// `StoredMeasurement` is the durable record so sinks can be retried after a
/// crash or restart.
final class PersistenceStore {
    private let url: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(filename: String = "myscale.json") {
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                in: .userDomainMask,
                                                appropriateFor: nil,
                                                create: true)) ?? FileManager.default.temporaryDirectory
        url = dir.appendingPathComponent(filename)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> PersistedState {
        guard let data = try? Data(contentsOf: url),
              let state = try? decoder.decode(PersistedState.self, from: data) else {
            return PersistedState()
        }
        return state
    }

    func save(_ state: PersistedState) {
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}
