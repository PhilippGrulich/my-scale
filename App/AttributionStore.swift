import Foundation
import MyOpenScaleCore

/// Persists the learned attribution model (owner signature + known others) in
/// UserDefaults, same lightweight pattern as `ProfileStore`.
enum AttributionStore {
    private static let key = "myopenscale.attribution.v1"

    static func load() -> AttributionModel {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let model = try? JSONDecoder().decode(AttributionModel.self, from: data)
        else { return AttributionModel() }
        return model
    }

    static func save(_ model: AttributionModel) {
        guard let data = try? JSONEncoder().encode(model) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
