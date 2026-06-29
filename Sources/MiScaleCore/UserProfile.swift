import Foundation

/// Canonical per-user profile, owned by the pure core.
///
/// Uses the core `BiologicalSex` (not `HKBiologicalSex`) so the resolver and
/// calculator stay platform-free; the app maps HealthKit's sex onto this at the
/// HealthKit boundary only.
public struct UserProfile: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var heightCm: Double
    public var dateOfBirth: Date
    public var sex: BiologicalSex
    /// Configurable weight band used to attribute a reading to this user.
    public var weightRangeKg: ClosedRange<Double>
    /// Exactly one profile should be the HealthKit owner (single-profile device).
    public var isHealthKitOwner: Bool

    public init(id: UUID,
                name: String,
                heightCm: Double,
                dateOfBirth: Date,
                sex: BiologicalSex,
                weightRangeKg: ClosedRange<Double>,
                isHealthKitOwner: Bool) {
        self.id = id
        self.name = name
        self.heightCm = heightCm
        self.dateOfBirth = dateOfBirth
        self.sex = sex
        self.weightRangeKg = weightRangeKg
        self.isHealthKitOwner = isHealthKitOwner
    }
}

public extension BodyProfile {
    /// Build the calculator input from a resolved user, aging the user to the
    /// reading's capture time (not "now").
    init(from profile: UserProfile, at date: Date) {
        self.init(heightCm: profile.heightCm,
                  ageYears: Double(DateMath.ageYears(dateOfBirth: profile.dateOfBirth, at: date)),
                  sex: profile.sex)
    }
}

/// Calendar math kept in one place and pinned to UTC so it is deterministic in
/// tests and unaffected by the device locale.
public enum DateMath {
    public static func ageYears(dateOfBirth: Date, at date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar.dateComponents([.year], from: dateOfBirth, to: date).year ?? 0
    }
}
