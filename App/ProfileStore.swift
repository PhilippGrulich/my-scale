import Foundation
import MiScaleCore

/// Codable mirror of the core `UserProfile` (which is intentionally not Codable
/// to keep the pure core platform-free). Persisted to `UserDefaults` for v1;
/// swap for the durable `MeasurementStore` repository in M4.
struct StoredProfile: Codable, Equatable {
    var id: UUID
    var name: String
    var heightCm: Double
    var dateOfBirth: Date
    var sex: BiologicalSex
    var weightMinKg: Double
    var weightMaxKg: Double

    /// A sensible default so the app is usable on first launch without setup.
    static func makeDefault() -> StoredProfile {
        // ~30-year-old as a neutral starting point; user edits in the UI.
        let dob = Calendar(identifier: .gregorian)
            .date(byAdding: .year, value: -30, to: Date()) ?? Date(timeIntervalSince1970: 0)
        return StoredProfile(
            id: UUID(),
            name: "Me",
            heightCm: 175,
            dateOfBirth: dob,
            sex: .male,
            // Wide default range so any weigh-in attributes to this single user
            // during testing (tighten once a second user is added).
            weightMinKg: 30,
            weightMaxKg: 250
        )
    }

    /// Map to the pure-core profile. This is always the HealthKit owner in v1
    /// (single-profile-per-device, plan §5).
    var coreProfile: UserProfile {
        UserProfile(
            id: id,
            name: name,
            heightCm: heightCm,
            dateOfBirth: dateOfBirth,
            sex: sex,
            weightRangeKg: min(weightMinKg, weightMaxKg)...max(weightMinKg, weightMaxKg),
            isHealthKitOwner: true
        )
    }
}

/// Tiny persistence wrapper. Single-profile for v1.
enum ProfileStore {
    private static let key = "miscale.profile.v1"

    static func load() -> StoredProfile {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let profile = try? JSONDecoder().decode(StoredProfile.self, from: data)
        else {
            let fresh = StoredProfile.makeDefault()
            save(fresh)
            return fresh
        }
        return profile
    }

    static func save(_ profile: StoredProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
