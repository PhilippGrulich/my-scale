import Foundation

/// A body value the app can show on the Overview and explain on a detail page.
public enum BodyMetric: String, CaseIterable, Sendable, Identifiable {
    case bodyFat, muscle, water, visceralFat, lean, bone, bmr, metabolicAge, protein
    public var id: String { rawValue }

    /// Whether the value needs an impedance (scale) reading; the rest can also
    /// come from other sources (manual body fat, other apps via Health).
    public var needsImpedance: Bool {
        switch self {
        case .bodyFat, .lean: return false
        default: return true
        }
    }
}

/// How a value compares with the reference range for the user's sex and age.
public enum MetricStatus: Equatable, Sendable {
    case low, normal, high, veryHigh
}

/// All estimates from one weigh-in with impedance. Values are the published
/// Xiaomi-style bioimpedance regressions (the same family as `BodyCompositionCalculator`):
/// population estimates, not measurements — the UI labels them as such.
public struct BodyMetricValues: Equatable, Sendable {
    public let bodyFatPercent: Double
    public let leanMassKg: Double
    public let muscleMassKg: Double
    public let waterPercent: Double
    public let boneMassKg: Double
    public let visceralFat: Double
    public let bmrKcal: Double
    public let metabolicAge: Double
    public let proteinPercent: Double

    public func value(_ metric: BodyMetric) -> Double {
        switch metric {
        case .bodyFat: return bodyFatPercent
        case .lean: return leanMassKg
        case .muscle: return muscleMassKg
        case .water: return waterPercent
        case .bone: return boneMassKg
        case .visceralFat: return visceralFat
        case .bmr: return bmrKcal
        case .metabolicAge: return metabolicAge
        case .protein: return proteinPercent
        }
    }
}

public enum BodyMetricsCalculator {

    /// Every estimate for one weigh-in. `impedanceOhms` must be > 0.
    public static func compute(weightKg w: Double, impedanceOhms imp: Double,
                               profile p: BodyProfile) -> BodyMetricValues {
        let base = BodyCompositionCalculator.compute(weightKg: w, impedanceOhms: imp, profile: p)
        let lbm = BodyCompositionCalculator.lbmCoefficient(weightKg: w, impedanceOhms: imp, profile: p)
        let fat = base.bodyFatPercent
        let water = waterPercent(fatPercent: fat)
        let bone = boneMassKg(lbm: lbm, sex: p.sex)
        let muscle = muscleMassKg(weightKg: w, fatPercent: fat, boneKg: bone, sex: p.sex)
        return BodyMetricValues(
            bodyFatPercent: fat,
            leanMassKg: base.leanMassKg,
            muscleMassKg: muscle,
            waterPercent: water,
            boneMassKg: bone,
            visceralFat: visceralFat(weightKg: w, profile: p),
            bmrKcal: bmrKcal(weightKg: w, profile: p),
            metabolicAge: metabolicAge(weightKg: w, impedanceOhms: imp, profile: p),
            proteinPercent: clamp(muscle / w * 100 - water, 5, 32))
    }

    /// Body water ≈ 70 % of fat-free mass, with the regression's correction.
    static func waterPercent(fatPercent fat: Double) -> Double {
        let raw = (100 - fat) * 0.7
        let corrected = raw * (raw <= 50 ? 1.02 : 0.98)
        return corrected >= 65 ? 75 : clamp(corrected, 35, 75)
    }

    static func boneMassKg(lbm: Double, sex: BiologicalSex) -> Double {
        let base = sex == .female ? 0.18016894 : 0.245691014
        var bone = (lbm - base) * 0.05158
        bone += bone > 2.2 ? 0.1 : -0.1
        if bone > (sex == .female ? 5.1 : 5.2) { bone = 8 }
        return clamp(bone, 0.5, 8)
    }

    static func muscleMassKg(weightKg w: Double, fatPercent fat: Double, boneKg: Double, sex: BiologicalSex) -> Double {
        var muscle = w - fat * 0.01 * w - boneKg
        if muscle >= (sex == .female ? 84 : 93.5) { muscle = 120 }
        return clamp(muscle, 10, 120)
    }

    /// Visceral-fat rating (1–50; 1–9 is the healthy band).
    static func visceralFat(weightKg w: Double, profile p: BodyProfile) -> Double {
        let h = p.heightCm, age = p.ageYears
        let v: Double
        switch p.sex {
        case .female:
            if w > (13 - h * 0.5) * -1 {
                let d = h * 1.45 + h * 0.1158 * h - 120
                v = w * 500 / d - 6 + age * 0.07
            } else {
                let c = 0.691 + h * -0.0024 + h * -0.0024
                v = (h * 0.027 - c * w) * -1 + age * 0.07 - age
            }
        case .male:
            if h < w * 1.6 {
                let c = (h * 0.4 - h * (h * 0.0826)) * -1
                v = w * 305 / (c + 48) - 2.9 + age * 0.15
            } else {
                let c = 0.765 + h * -0.0015
                v = (h * 0.143 - w * c) * -1 + age * 0.15 - 5
            }
        }
        return clamp(v, 1, 50)
    }

    /// Basal metabolic rate in kcal/day.
    static func bmrKcal(weightKg w: Double, profile p: BodyProfile) -> Double {
        let h = p.heightCm, age = p.ageYears
        switch p.sex {
        case .male:
            return clamp(877.8 + w * 14.916 - h * 0.726 - age * 8.976, 500, 10_000)
        case .female:
            return clamp(864.6 + w * 10.2036 - h * 0.39336 - age * 6.204, 500, 10_000)
        }
    }

    static func metabolicAge(weightKg w: Double, impedanceOhms imp: Double, profile p: BodyProfile) -> Double {
        let h = p.heightCm, age = p.ageYears
        let v: Double
        switch p.sex {
        case .male: v = h * -0.7471 + w * 0.9161 + age * 0.4184 + imp * 0.0517 + 54.2267
        case .female: v = h * -1.1165 + w * 1.5784 + age * 0.4615 + imp * 0.0415 + 83.2548
        }
        return clamp(v, 15, 80)
    }

    static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
}

/// Reference ranges used for the status labels and the shaded bands.
public enum BodyMetricRanges {

    /// The healthy band for the user, or nil when there is no meaningful one
    /// (muscle and bone mass depend too much on build; BMR is just a number).
    public static func normalRange(_ metric: BodyMetric, sex: BiologicalSex, ageYears age: Double) -> ClosedRange<Double>? {
        switch metric {
        case .bodyFat:
            // Adult reference bands by sex and age (Gallagher et al. 2000, rounded).
            switch (sex, age) {
            case (.male, ..<40): return 8...20
            case (.male, ..<60): return 11...22
            case (.male, _): return 13...25
            case (.female, ..<40): return 21...33
            case (.female, ..<60): return 23...34
            case (.female, _): return 24...36
            }
        case .water: return sex == .male ? 55...65 : 45...60
        case .visceralFat: return 1...9
        case .protein: return 16...20
        case .lean, .muscle, .bone, .bmr, .metabolicAge: return nil
        }
    }

    /// Status of a value. Metabolic age is judged against the real age (older
    /// than you = "high"); metrics without a band have no status.
    public static func status(_ metric: BodyMetric, value: Double, sex: BiologicalSex,
                              ageYears age: Double) -> MetricStatus? {
        if metric == .metabolicAge { return value <= age ? .normal : .high }
        if metric == .visceralFat { return value < 10 ? .normal : (value < 15 ? .high : .veryHigh) }
        guard let r = normalRange(metric, sex: sex, ageYears: age) else { return nil }
        if value < r.lowerBound { return .low }
        if value <= r.upperBound { return .normal }
        // Body fat more than 5 points over the band is "very high".
        if metric == .bodyFat, value > r.upperBound + 5 { return .veryHigh }
        return .high
    }
}
