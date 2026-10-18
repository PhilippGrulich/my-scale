import Foundation
import MyOpenScaleCore

/// Codable mirror of the core `UserProfile` (which is intentionally not Codable
/// to keep the pure core platform-free). Persisted to `UserDefaults` for v1;
/// swap for the durable `MeasurementStore` repository in M4.
struct StoredProfile: Codable, Equatable {
    var id: UUID
    var name: String
    var heightCm: Double
    var dateOfBirth: Date
    /// True once the date of birth came from Apple Health or the user set it; the
    /// placeholder default is not a real birthday (Mochi only celebrates real ones).
    var dateOfBirthIsReal: Bool?
    var sex: BiologicalSex
    var weightMinKg: Double
    var weightMaxKg: Double
    /// Optional target weight for the goal/ETA UI. nil = no goal set.
    var goalWeightKg: Double?
    /// Direction of the goal. nil on profiles saved before goal types existed (treated as lose).
    var goalType: GoalType?
    /// Weight and date when the current goal was set — the 0 % point of the
    /// goal progress ring. Set by `AppModel.saveProfile` whenever the goal
    /// changes (optional, so older saved profiles still decode).
    var goalStartKg: Double?
    var goalSetAt: Date?
    /// Optional deadline for the goal (the "plan"); nil = just a forecast.
    var goalTargetDate: Date?
    /// Optional body-fat target in percent, and the value when it was set.
    var goalBodyFatPercent: Double?
    var goalBodyFatStartPercent: Double?
    /// How many milestones of the current goal were already celebrated.
    var goalMilestonesSeen: Int?

    /// A sensible default so the app is usable on first launch without setup.
    static func makeDefault() -> StoredProfile {
        // ~30-year-old as a neutral starting point; user edits in the UI.
        let dob = Calendar(identifier: .gregorian)
            .date(byAdding: .year, value: -30, to: Date()) ?? Date(timeIntervalSince1970: 0)
        return StoredProfile(
            id: UUID(),
            name: String(localized: "Me"),
            heightCm: 175,
            dateOfBirth: dob,
            sex: .male,
            // Wide default range so any weigh-in attributes to this single user
            // during testing (tighten once a second user is added).
            weightMinKg: 30,
            weightMaxKg: 250
        )
    }

    /// Return a copy with any non-nil Apple Health values applied. Used to
    /// pre-fill onboarding; fields Health can't supply (name) or didn't have are
    /// left untouched so the existing default stands and the user can edit.
    func applying(prefill: HealthKitSink.HealthPrefill) -> StoredProfile {
        var copy = self
        if let dob = prefill.dateOfBirth {
            copy.dateOfBirth = dob
            copy.dateOfBirthIsReal = true
        }
        if let sex = prefill.sex { copy.sex = sex }
        if let h = prefill.heightCm, h > 0 { copy.heightCm = h }
        return copy
    }

    /// The date of birth when it is real, else nil (see `dateOfBirthIsReal`).
    var knownDateOfBirth: Date? { dateOfBirthIsReal == true ? dateOfBirth : nil }

    /// The goal as Mochi and the trend colours understand it.
    var weightGoal: WeightGoal {
        WeightGoal(type: goalType ?? .lose, targetKg: goalWeightKg, startKg: goalStartKg)
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
    private static let key = "myopenscale.profile.v1"

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
