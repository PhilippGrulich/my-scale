import Foundation

/// A learned weight + impedance "fingerprint" for one body. Impedance adds a
/// second, body-composition dimension that separates people of similar weight
/// far more reliably than weight alone.
public struct UserSignature: Codable, Equatable, Sendable {
    public var weightKg: Double
    public var impedanceOhms: Double   // 0 = not yet known
    public var sampleCount: Int

    public init(weightKg: Double, impedanceOhms: Double, sampleCount: Int) {
        self.weightKg = weightKg
        self.impedanceOhms = impedanceOhms
        self.sampleCount = sampleCount
    }
}

/// The owner's signature plus learned "other" clusters. Others are used to
/// silently skip household members' weigh-ins so only the owner's data is kept.
public struct AttributionModel: Codable, Equatable, Sendable {
    public var me: UserSignature?
    public var others: [UserSignature]

    public init(me: UserSignature? = nil, others: [UserSignature] = []) {
        self.me = me
        self.others = others
    }
}

public struct AttributionConfig: Equatable, Sendable {
    /// Day-to-day weight wobble + gradual drift allowance.
    public var weightToleranceKg: Double
    /// Hydration / time-of-day impedance spread for one body.
    public var impedanceToleranceOhms: Double
    /// EMA weight for folding a new reading into a signature (0…1).
    public var learningRate: Double
    /// Cap on remembered "other" clusters.
    public var maxOthers: Int

    public init(weightToleranceKg: Double = 7,
                impedanceToleranceOhms: Double = 80,
                learningRate: Double = 0.3,
                maxOthers: Int = 4) {
        self.weightToleranceKg = weightToleranceKg
        self.impedanceToleranceOhms = impedanceToleranceOhms
        self.learningRate = learningRate
        self.maxOthers = maxOthers
    }
}

public enum Attribution: Equatable, Sendable {
    case me          // confidently the owner — auto-keep
    case other       // matches a known other body — silently skip
    case uncertain   // unclear — ask the user
}

/// Pure, testable "is this the owner?" classifier over (weight, impedance).
public enum AttributionClassifier {

    /// Squared normalized distance from a reading to a signature. Impedance is
    /// only used when both the reading and the signature carry it (an ellipse in
    /// (weight, impedance) space; ≤ 1 means inside).
    static func distanceSquared(weightKg: Double, impedanceOhms: Int,
                                to sig: UserSignature, config: AttributionConfig) -> Double {
        let dw = (weightKg - sig.weightKg) / config.weightToleranceKg
        if (1...3000).contains(impedanceOhms), sig.impedanceOhms > 0 {
            let di = (Double(impedanceOhms) - sig.impedanceOhms) / config.impedanceToleranceOhms
            return dw * dw + di * di
        }
        return dw * dw
    }

    static func matches(weightKg: Double, impedanceOhms: Int,
                        _ sig: UserSignature, _ config: AttributionConfig) -> Bool {
        distanceSquared(weightKg: weightKg, impedanceOhms: impedanceOhms, to: sig, config: config) <= 1.0
    }

    /// Classify a reading. With no owner signature yet, the first reading defines
    /// the owner (bootstrap → `.me`).
    public static func decide(weightKg: Double, impedanceOhms: Int,
                              model: AttributionModel,
                              config: AttributionConfig = .init()) -> Attribution {
        guard let me = model.me else { return .me }
        if matches(weightKg: weightKg, impedanceOhms: impedanceOhms, me, config) { return .me }
        if model.others.contains(where: { matches(weightKg: weightKg, impedanceOhms: impedanceOhms, $0, config) }) {
            return .other
        }
        return .uncertain
    }

    /// Fold a confirmed owner reading into `me` (EMA, or seed if empty).
    public static func learnMe(_ model: AttributionModel, weightKg: Double, impedanceOhms: Int,
                               config: AttributionConfig = .init()) -> AttributionModel {
        var m = model
        m.me = folded(m.me, weightKg: weightKg, impedanceOhms: impedanceOhms, rate: config.learningRate)
        return m
    }

    /// Record a rejected reading as an "other": fold into the nearest matching
    /// cluster, or add a new one (capped, dropping the oldest).
    public static func learnOther(_ model: AttributionModel, weightKg: Double, impedanceOhms: Int,
                                  config: AttributionConfig = .init()) -> AttributionModel {
        var m = model
        if let idx = m.others.firstIndex(where: { matches(weightKg: weightKg, impedanceOhms: impedanceOhms, $0, config) }) {
            m.others[idx] = folded(m.others[idx], weightKg: weightKg, impedanceOhms: impedanceOhms, rate: config.learningRate)
        } else {
            m.others.append(folded(nil, weightKg: weightKg, impedanceOhms: impedanceOhms, rate: config.learningRate))
            if m.others.count > config.maxOthers {
                m.others.removeFirst(m.others.count - config.maxOthers)
            }
        }
        return m
    }

    private static func folded(_ sig: UserSignature?, weightKg: Double, impedanceOhms: Int, rate: Double) -> UserSignature {
        let hasImp = (1...3000).contains(impedanceOhms)
        guard let sig, sig.sampleCount > 0 else {
            return UserSignature(weightKg: weightKg,
                                 impedanceOhms: hasImp ? Double(impedanceOhms) : 0,
                                 sampleCount: 1)
        }
        let w = rate * weightKg + (1 - rate) * sig.weightKg
        let imp: Double
        if hasImp {
            imp = sig.impedanceOhms > 0 ? rate * Double(impedanceOhms) + (1 - rate) * sig.impedanceOhms
                                        : Double(impedanceOhms)
        } else {
            imp = sig.impedanceOhms
        }
        return UserSignature(weightKg: w, impedanceOhms: imp, sampleCount: sig.sampleCount + 1)
    }
}
