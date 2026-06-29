import Foundation

/// Outcome of attributing a finalized weight to a configured user.
public enum UserResolution: Equatable, Sendable {
    case matched(UserProfile)
    case ambiguous([UserProfile])   // >1 configured range contains the weight
    case noMatch                    // 0 configured ranges contain the weight
}

/// A configuration problem detected among the users' weight ranges, surfaced in
/// the Settings UI. Runtime still defends with the hold-for-confirm path.
public struct RangeWarning: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case overlap   // two ranges intersect (or touch) → ambiguous weights
        case gap       // a weight band between two ranges matches nobody
    }
    public var kind: Kind
    public var profileIDs: [UUID]

    public init(kind: Kind, profileIDs: [UUID]) {
        self.kind = kind
        self.profileIDs = profileIDs
    }
}

/// Pure attribution logic. Only `.matched` proceeds to compute/write; the other
/// cases are held for manual confirmation (plan §6).
public enum UserResolver {

    public static func resolve(weightKg: Double, among profiles: [UserProfile]) -> UserResolution {
        let matches = profiles.filter { $0.weightRangeKg.contains(weightKg) }
        switch matches.count {
        case 0: return .noMatch
        case 1: return .matched(matches[0])
        default: return .ambiguous(matches)
        }
    }

    /// Detect overlapping (ambiguous) and gapped (unreachable) weight bands so
    /// the user can fix their configuration.
    public static func rangeWarnings(_ profiles: [UserProfile]) -> [RangeWarning] {
        guard profiles.count > 1 else { return [] }
        var warnings: [RangeWarning] = []

        // Overlaps across every pair (closed ranges, so a shared boundary counts).
        for i in 0..<profiles.count {
            for j in (i + 1)..<profiles.count {
                let a = profiles[i].weightRangeKg
                let b = profiles[j].weightRangeKg
                if a.lowerBound <= b.upperBound && b.lowerBound <= a.upperBound {
                    warnings.append(RangeWarning(kind: .overlap,
                                                 profileIDs: [profiles[i].id, profiles[j].id]))
                }
            }
        }

        // Gaps between consecutive ranges once sorted by lower bound.
        let sorted = profiles.sorted { $0.weightRangeKg.lowerBound < $1.weightRangeKg.lowerBound }
        for k in 1..<sorted.count {
            let prev = sorted[k - 1].weightRangeKg
            let next = sorted[k].weightRangeKg
            if prev.upperBound < next.lowerBound {
                warnings.append(RangeWarning(kind: .gap,
                                             profileIDs: [sorted[k - 1].id, sorted[k].id]))
            }
        }

        return warnings
    }
}
