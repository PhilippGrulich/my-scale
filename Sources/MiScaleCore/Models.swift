import Foundation

/// Biological sex as required by the Xiaomi body-composition regressions.
/// The formulas are strictly binary; the app layer maps `HKBiologicalSex`
/// onto this and blocks computation for `.other` / `.notSet`.
public enum BiologicalSex: String, Codable, Sendable {
    case male
    case female
}

/// Static, per-user profile needed to turn a raw weight + impedance reading
/// into body composition. Kept free of any platform type so it is testable.
public struct BodyProfile: Equatable, Sendable {
    public var heightCm: Double
    public var ageYears: Double
    public var sex: BiologicalSex

    public init(heightCm: Double, ageYears: Double, sex: BiologicalSex) {
        self.heightCm = heightCm
        self.ageYears = ageYears
        self.sex = sex
    }
}

/// The four HealthKit-native metrics this app computes and writes in v1.
public struct BodyComposition: Equatable, Codable, Sendable {
    public var bodyMassKg: Double
    public var bodyFatPercent: Double
    public var leanMassKg: Double
    public var bmi: Double

    public init(bodyMassKg: Double, bodyFatPercent: Double, leanMassKg: Double, bmi: Double) {
        self.bodyMassKg = bodyMassKg
        self.bodyFatPercent = bodyFatPercent
        self.leanMassKg = leanMassKg
        self.bmi = bmi
    }
}
