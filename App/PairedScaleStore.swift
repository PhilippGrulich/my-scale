import Foundation

/// The user's remembered scale, identified by its CoreBluetooth
/// `peripheral.identifier` (a per-install stable UUID — NOT the BLE MAC, which
/// iOS does not expose). Once paired, `AppModel` only accepts weigh-ins from
/// this peripheral.
struct PairedScale: Codable, Equatable {
    var peripheralID: UUID
    var pairedAt: Date
    var lastSeenWeightKg: Double?
}

/// Tiny persistence wrapper, same UserDefaults pattern as `ProfileStore`. Unlike
/// `ProfileStore`, `load()` returns nil when nothing is paired (no default).
enum PairedScaleStore {
    private static let key = "myopenscale.pairedScale.v1"

    static func load() -> PairedScale? {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let scale = try? JSONDecoder().decode(PairedScale.self, from: data)
        else { return nil }
        return scale
    }

    static func save(_ scale: PairedScale) {
        guard let data = try? JSONEncoder().encode(scale) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
