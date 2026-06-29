import Foundation
import MiScaleCore

/// Per-sink delivery state for a stored reading.
enum SinkState: String, Codable, Equatable {
    case pending, written, failed, skipped
}

/// How a reading was attributed to a user.
enum ResolutionKind: String, Codable, Equatable {
    case matched, ambiguous, noMatch, manual
}

/// Codable, editable user profile persisted on device. Maps to the core
/// `UserProfile` (which the resolver/calculator consume).
struct StoredProfile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = ""
    var heightCm: Double = 170
    var dateOfBirth: Date = Date(timeIntervalSince1970: 0)
    var sex: BiologicalSex = .male
    var lowerKg: Double = 40
    var upperKg: Double = 200
    var isHealthKitOwner: Bool = false

    var core: UserProfile {
        UserProfile(id: id, name: name, heightCm: heightCm, dateOfBirth: dateOfBirth,
                    sex: sex, weightRangeKg: min(lowerKg, upperKg)...max(lowerKg, upperKg),
                    isHealthKitOwner: isHealthKitOwner)
    }
}

/// Durable record of one finalized weigh-in — the source of truth that drives
/// the HealthKit and Home Assistant sinks and survives restarts.
struct StoredMeasurement: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var capturedAt: Date
    var deviceTimestamp: Date?
    var weightKg: Double
    var impedanceOhms: Int
    var assignedUserID: UUID?
    var resolution: ResolutionKind
    var composition: BodyComposition?
    var healthKitState: SinkState = .pending
    var haState: SinkState = .pending
    var rawServiceDataHex: String
}

/// Home Assistant sink configuration. (Token belongs in Keychain — TODO before
/// shipping; stored here for the scaffold.)
struct HAConfig: Codable, Equatable {
    var enabled: Bool = false
    var endpoint: String = ""
    var token: String = ""
}

extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
