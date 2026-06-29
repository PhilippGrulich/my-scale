import XCTest
@testable import MiScaleCore

final class MeasurementFinalizerTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private func finalFrame(_ weight: Double, _ impedance: Int) -> ParsedAdvertisement {
        ParsedAdvertisement(unitRaw: 0x02, isStabilized: true, hasImpedance: true,
                            isWeightRemoved: false, weightKg: weight,
                            impedanceOhms: impedance, deviceTimestamp: nil)
    }

    private func nonStableFrame(_ weight: Double) -> ParsedAdvertisement {
        ParsedAdvertisement(unitRaw: 0x02, isStabilized: false, hasImpedance: false,
                            isWeightRemoved: false, weightKg: weight,
                            impedanceOhms: 0, deviceTimestamp: nil)
    }

    private func removedFrame() -> ParsedAdvertisement {
        ParsedAdvertisement(unitRaw: 0x02, isStabilized: true, hasImpedance: false,
                            isWeightRemoved: true, weightKg: 0, impedanceOhms: 0,
                            deviceTimestamp: nil)
    }

    func testNormalWeighInEmitsExactlyOneReading() {
        let f = MeasurementFinalizer()
        var emissions: [FinalizedReading] = []

        emissions.appendIfPresent(f.ingest(finalFrame(75.0, 500), at: at(0)))
        emissions.appendIfPresent(f.ingest(finalFrame(75.0, 500), at: at(0.3)))
        emissions.appendIfPresent(f.ingest(finalFrame(75.0, 500), at: at(0.7)))  // settle elapsed
        emissions.appendIfPresent(f.ingest(finalFrame(75.0, 500), at: at(1.0)))  // cooldown

        XCTAssertEqual(emissions.count, 1)
        XCTAssertEqual(emissions[0].weightKg, 75.0, accuracy: 1e-9)
        XCTAssertEqual(emissions[0].impedanceOhms, 500)
        XCTAssertEqual(emissions[0].capturedAt, at(0.7))
        XCTAssertEqual(f.state, .cooldown)
    }

    func testTickFinalizesWhenAdvertsPause() {
        let f = MeasurementFinalizer()
        XCTAssertNil(f.ingest(finalFrame(80.0, 520), at: at(0)))
        // No further adverts, but settle elapses; a tick finalizes it.
        let reading = f.tick(at: at(0.65))
        XCTAssertEqual(reading?.weightKg, 80.0)
        XCTAssertEqual(reading?.capturedAt, at(0.65))
    }

    func testStepOffEarlyNeverFinalizes() {
        let f = MeasurementFinalizer()
        for s in stride(from: 0.0, through: 2.0, by: 0.25) {
            XCTAssertNil(f.ingest(nonStableFrame(40 + s), at: at(s)))
        }
        XCTAssertNil(f.tick(at: at(10)))
        XCTAssertEqual(f.state, .idle)
    }

    func testRepeatBurstAndRemovedEventAreDeduped() {
        let f = MeasurementFinalizer()
        var count = 0
        count += f.ingest(finalFrame(62.0, 480), at: at(0)) != nil ? 1 : 0
        count += f.ingest(finalFrame(62.0, 480), at: at(0.7)) != nil ? 1 : 0   // emit
        // Repeat burst + trailing removed event, all within cooldown:
        count += f.ingest(finalFrame(62.0, 480), at: at(1.0)) != nil ? 1 : 0
        count += f.ingest(finalFrame(62.0, 480), at: at(2.0)) != nil ? 1 : 0
        count += f.ingest(removedFrame(), at: at(3.0)) != nil ? 1 : 0
        XCTAssertEqual(count, 1)
    }

    func testWeightShiftMidSettleRestartsWindow() {
        let f = MeasurementFinalizer()
        XCTAssertNil(f.ingest(finalFrame(75.0, 500), at: at(0)))
        XCTAssertNil(f.ingest(finalFrame(80.0, 510), at: at(0.3)))  // restart on 80
        XCTAssertNil(f.ingest(finalFrame(80.0, 510), at: at(0.5)))  // only 0.2 since restart
        let reading = f.ingest(finalFrame(80.0, 510), at: at(1.0))  // 0.7 since restart -> emit
        XCTAssertEqual(reading?.weightKg, 80.0)
        XCTAssertEqual(reading?.impedanceOhms, 510)
    }

    func testWeightRemovedFinalizesImmediately() {
        let f = MeasurementFinalizer()
        XCTAssertNil(f.ingest(finalFrame(70.0, 450), at: at(0)))
        let reading = f.ingest(removedFrame(), at: at(0.2))  // before settle, but load lifted
        XCTAssertEqual(reading?.weightKg, 70.0)
        XCTAssertEqual(reading?.impedanceOhms, 450)
        XCTAssertEqual(reading?.capturedAt, at(0.2))
    }

    func testStaleTimeoutResetsToIdle() {
        let f = MeasurementFinalizer()
        XCTAssertNil(f.ingest(finalFrame(75.0, 500), at: at(0)))
        XCTAssertEqual(f.state, .measuring)
        XCTAssertNil(f.tick(at: at(6)))  // > staleTimeout (5)
        XCTAssertEqual(f.state, .idle)
    }

    func testNewWeighInAfterCooldownEmitsAgain() {
        let f = MeasurementFinalizer()
        XCTAssertNil(f.ingest(finalFrame(75.0, 500), at: at(0)))
        XCTAssertNotNil(f.ingest(finalFrame(75.0, 500), at: at(0.7)))  // first emit
        // After cooldown (10s) a fresh weigh-in emits again.
        XCTAssertNil(f.ingest(finalFrame(90.0, 600), at: at(12)))
        let second = f.ingest(finalFrame(90.0, 600), at: at(12.7))
        XCTAssertEqual(second?.weightKg, 90.0)
    }
}

private extension Array where Element == FinalizedReading {
    mutating func appendIfPresent(_ reading: FinalizedReading?) {
        if let reading { append(reading) }
    }
}
