import Foundation

/// What the user wants their weight to do.
public enum GoalType: String, Codable, Sendable, CaseIterable {
    case lose, gain, maintain
}

/// A weight goal plus the direction maths Mochi uses to react to weigh-ins.
public struct WeightGoal: Equatable, Sendable {
    /// Changes smaller than this (kg) are scale noise and count as flat.
    public static let noiseKg = 0.1

    public var type: GoalType
    public var targetKg: Double?
    public var startKg: Double?
    /// Half-width of the "on goal" band for `.maintain`.
    public var toleranceKg: Double

    public init(type: GoalType, targetKg: Double?, startKg: Double?, toleranceKg: Double = 1.0) {
        self.type = type
        self.targetKg = targetKg
        self.startKg = startKg
        self.toleranceKg = toleranceKg
    }

    /// Whether `kg` is within the maintain band. False for other goals or when no target is set.
    public func isInBand(_ kg: Double) -> Bool {
        guard type == .maintain, let target = targetKg else { return false }
        return abs(kg - target) <= toleranceKg
    }

    /// Whether a move from `fromKg` to `toKg` is in the goal's direction. Flat moves count as toward.
    public func isToward(fromKg: Double, toKg: Double) -> Bool {
        let delta = toKg - fromKg
        switch type {
        case .lose:
            return delta < Self.noiseKg
        case .gain:
            return delta > -Self.noiseKg
        case .maintain:
            guard let target = targetKg else { return true }
            func distanceToBand(_ kg: Double) -> Double { max(0, abs(kg - target) - toleranceKg) }
            return distanceToBand(toKg) < distanceToBand(fromKg) + Self.noiseKg
        }
    }

    /// Whether the goal is achieved at `kg`. False when no target is set.
    public func isReached(_ kg: Double) -> Bool {
        guard let target = targetKg else { return false }
        switch type {
        case .lose: return kg <= target
        case .gain: return kg >= target
        case .maintain: return isInBand(kg)
        }
    }

    /// Whether `kg` beats the previous best by more than noise. Never true for maintain.
    public func isBetter(_ kg: Double, than best: Double) -> Bool {
        switch type {
        case .lose: return kg < best - Self.noiseKg
        case .gain: return kg > best + Self.noiseKg
        case .maintain: return false
        }
    }

    /// Progress from start to target, clamped to 0...1. Nil for maintain or incomplete/degenerate goals.
    public func progressFraction(_ kg: Double) -> Double? {
        guard type != .maintain, let target = targetKg, let start = startKg, start != target else { return nil }
        return min(1, max(0, (kg - start) / (target - start)))
    }

    /// Stable string that changes whenever type, target or start change; used to reset progress state.
    public func signature() -> String {
        func text(_ v: Double?) -> String { v.map { String($0) } ?? "-" }
        return "\(type.rawValue)|\(text(targetKg))|\(text(startKg))"
    }
}
