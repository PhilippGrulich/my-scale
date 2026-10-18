import Foundation

/// Pure body-composition math. No I/O, no platform imports.
///
/// Formulas are the reverse-engineered Xiaomi regressions used by
/// lolouk44/`Xiaomi_Scale_Body_Metrics.py` and dckiller51/`bodymiscale`.
/// Constants flagged below are reverse-engineered and MUST be validated
/// against the Zepp/Mi Fitness readout before shipping (see plan §9).
public enum BodyCompositionCalculator {

    // MARK: - Public API

    /// Compute the four HealthKit-native metrics. `impedanceOhms` must be > 0
    /// (the scale's impedance-present frame); callers without impedance should
    /// use `partial(weightKg:profile:)` instead.
    public static func compute(weightKg w: Double,
                               impedanceOhms imp: Double,
                               profile: BodyProfile) -> BodyComposition {
        let lbm = lbmCoefficient(weightKg: w, impedanceOhms: imp, profile: profile)
        let fat = fatPercentage(lbm: lbm, weightKg: w, profile: profile)
        let lean = w * (1.0 - fat / 100.0)
        return BodyComposition(bodyMassKg: w,
                               bodyFatPercent: fat,
                               leanMassKg: lean,
                               bmi: bmi(weightKg: w, heightCm: profile.heightCm))
    }

    /// Composition for a manually entered weigh-in (no impedance): BMI from the
    /// height, and — only when the user typed a body-fat % — lean mass derived
    /// from it. Fat/lean are NaN otherwise, like `partial`.
    public static func manual(weightKg w: Double, bodyFatPercent fat: Double?, heightCm h: Double) -> BodyComposition {
        let validFat = fat.flatMap { (0...75).contains($0) ? $0 : nil }
        return BodyComposition(
            bodyMassKg: w,
            bodyFatPercent: validFat ?? .nan,
            leanMassKg: validFat.map { w * (1 - $0 / 100) } ?? .nan,
            bmi: bmi(weightKg: w, heightCm: h))
    }

    /// Weight-only composition for stabilized frames that carry no impedance:
    /// BMI is still well-defined; fat%/lean are left as NaN to signal "partial".
    public static func partial(weightKg w: Double, profile: BodyProfile) -> BodyComposition {
        BodyComposition(bodyMassKg: w,
                        bodyFatPercent: .nan,
                        leanMassKg: .nan,
                        bmi: bmi(weightKg: w, heightCm: profile.heightCm))
    }

    // MARK: - Components

    /// Body Mass Index, clamped to [10, 90].
    public static func bmi(weightKg w: Double, heightCm h: Double) -> Double {
        let meters = h / 100.0
        return clamp(w / (meters * meters), 10.0, 90.0)
    }

    /// Lean Body Mass regression coefficient (kg). h=cm, w=kg, imp=ohms, age=yr.
    public static func lbmCoefficient(weightKg w: Double,
                                      impedanceOhms imp: Double,
                                      profile p: BodyProfile) -> Double {
        let h = p.heightCm
        return (h * 9.058 / 100.0) * (h / 100.0)
            + w * 0.32
            + 12.226
            - imp * 0.0068
            - p.ageYears * 0.0542
    }

    /// Body fat percentage, clamped to [5, 75].
    /// fat = (1 − ((LBM − c) * k) / w) * 100
    public static func fatPercentage(lbm: Double,
                                     weightKg w: Double,
                                     profile p: BodyProfile) -> Double {
        let c = fatConstant(profile: p)
        let k = fatCoefficient(weightKg: w, profile: p)
        let fat = (1.0 - ((lbm - c) * k) / w) * 100.0
        return clamp(fat, 5.0, 75.0)
    }

    // MARK: - Reverse-engineered constants (⚠️ validate before shipping)

    /// Sex/age constant `c` in the fat-percentage formula.
    static func fatConstant(profile p: BodyProfile) -> Double {
        switch p.sex {
        case .male:
            return 0.8
        case .female:
            return p.ageYears <= 49 ? 9.25 : 7.25
        }
    }

    /// Sex/weight/height coefficient `k` in the fat-percentage formula.
    static func fatCoefficient(weightKg w: Double, profile p: BodyProfile) -> Double {
        switch p.sex {
        case .male:
            return w < 61 ? 0.98 : 1.0
        case .female:
            if w > 60 {
                return p.heightCm > 160 ? 0.96 * 1.03 : 0.96
            } else if w < 50 {
                return p.heightCm > 160 ? 1.02 * 1.03 : 1.02
            } else {
                return 1.0
            }
        }
    }

    // MARK: - Helpers

    static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(max(value, low), high)
    }
}
