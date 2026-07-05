import Foundation

/// Tunable timing for the finalize/debounce/dedupe state machine.
/// Defaults are starting points; tune in the M9 field soak.
public struct FinalizerConfig: Equatable, Sendable {
    /// Hold a consistent qualifying weight at least this long before emitting.
    public var settle: TimeInterval
    /// Reserved. The post-emit lock is now released by a step-off (weight-removed
    /// frame) or by adverts going stale, not by a fixed timer — so the user
    /// staying on the scale never auto-starts a second weigh-in.
    public var cooldown: TimeInterval
    /// Drop a half-finished weigh-in if no advert arrives for this long.
    public var staleTimeout: TimeInterval
    /// Two weights within this band count as "the same" while settling.
    public var weightToleranceKg: Double

    public init(settle: TimeInterval = 0.6,
                cooldown: TimeInterval = 10,
                staleTimeout: TimeInterval = 5,
                weightToleranceKg: Double = 0.1) {
        self.settle = settle
        self.cooldown = cooldown
        self.staleTimeout = staleTimeout
        self.weightToleranceKg = weightToleranceKg
    }
}

/// A single finalized weigh-in, ready to be attributed to a user and computed.
public struct FinalizedReading: Equatable, Sendable {
    public var weightKg: Double
    public var impedanceOhms: Int
    public var capturedAt: Date
    public var deviceTimestamp: Date?

    public init(weightKg: Double, impedanceOhms: Int, capturedAt: Date, deviceTimestamp: Date?) {
        self.weightKg = weightKg
        self.impedanceOhms = impedanceOhms
        self.capturedAt = capturedAt
        self.deviceTimestamp = deviceTimestamp
    }
}

/// Deterministic, hardware-free core of the BLE state machine (§3a). One
/// instance per peripheral. Time is injected on every call so the settle /
/// cooldown / stale windows are fully testable without a real clock.
///
/// The CoreBluetooth wrapper (M3b) forwards `didDiscover` payloads into
/// `ingest(_:at:)` and runs a timer calling `tick(at:)`.
public final class MeasurementFinalizer {

    public enum State: Equatable { case idle, measuring, cooldown }

    public private(set) var state: State = .idle
    private let config: FinalizerConfig

    // Candidate being settled.
    private var candidateWeightKg = 0.0
    private var candidateImpedance = 0
    private var candidateDeviceTimestamp: Date?
    private var firstStableAt = Date.distantPast
    private var lastAdvAt = Date.distantPast

    public init(config: FinalizerConfig = FinalizerConfig()) {
        self.config = config
    }

    /// Feed a parsed advertisement observed at host time `now`.
    /// Returns a reading exactly when this frame completes a weigh-in.
    @discardableResult
    public func ingest(_ adv: ParsedAdvertisement, at now: Date) -> FinalizedReading? {
        switch state {
        case .idle:
            guard adv.isFinalReading else { return nil }
            beginMeasuring(adv, at: now)
            return finalizeIfSettled(at: now)

        case .measuring:
            lastAdvAt = now
            if adv.isWeightRemoved {
                // Load lifted after a stable reading: finalize the held candidate.
                return finalize(at: now)
            }
            guard adv.isFinalReading else {
                // Lost stabilization momentarily; keep waiting (stale timer guards).
                return nil
            }
            if abs(adv.weightKg - candidateWeightKg) <= config.weightToleranceKg {
                // Same body still on the scale; refresh impedance/timestamp.
                candidateImpedance = adv.impedanceOhms
                candidateDeviceTimestamp = adv.deviceTimestamp ?? candidateDeviceTimestamp
                return finalizeIfSettled(at: now)
            } else {
                // Weight shifted: restart the settle window on the new value.
                beginMeasuring(adv, at: now)
                return nil
            }

        case .cooldown:
            // Stay locked after a finalized reading until the load is lifted, so
            // a fresh weigh-in does NOT auto-start while the user simply keeps
            // standing on the scale. A weight-removed frame (step-off) clears it.
            lastAdvAt = now
            if adv.isWeightRemoved { state = .idle }
            return nil
        }
    }

    /// Advance time when no advert arrives (settle elapsed, weigh-in went stale,
    /// or cooldown finished). Returns a reading if settle completes here.
    @discardableResult
    public func tick(at now: Date) -> FinalizedReading? {
        switch state {
        case .measuring:
            if now.timeIntervalSince(lastAdvAt) >= config.staleTimeout {
                state = .idle
                return nil
            }
            return finalizeIfSettled(at: now)
        case .cooldown:
            // Stepped off without a clean weight-removed frame (some firmwares):
            // clear once adverts stop so a later weigh-in can register.
            if now.timeIntervalSince(lastAdvAt) >= config.staleTimeout { state = .idle }
            return nil
        case .idle:
            return nil
        }
    }

    // MARK: - Internals

    private func beginMeasuring(_ adv: ParsedAdvertisement, at now: Date) {
        state = .measuring
        candidateWeightKg = adv.weightKg
        candidateImpedance = adv.impedanceOhms
        candidateDeviceTimestamp = adv.deviceTimestamp
        firstStableAt = now
        lastAdvAt = now
    }

    private func finalizeIfSettled(at now: Date) -> FinalizedReading? {
        guard now.timeIntervalSince(firstStableAt) >= config.settle else { return nil }
        return finalize(at: now)
    }

    private func finalize(at now: Date) -> FinalizedReading {
        let reading = FinalizedReading(weightKg: candidateWeightKg,
                                       impedanceOhms: candidateImpedance,
                                       capturedAt: now,
                                       deviceTimestamp: candidateDeviceTimestamp)
        state = .cooldown
        return reading
    }
}
