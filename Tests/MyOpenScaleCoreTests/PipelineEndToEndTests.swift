import XCTest
@testable import MyOpenScaleCore

/// Exercises the full pure path with no hardware: finalize → resolve → compute.
final class PipelineEndToEndTests: XCTestCase {

    private func utc(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }

    private func finalFrame(_ w: Double, _ imp: Int) -> ParsedAdvertisement {
        ParsedAdvertisement(unitRaw: 0x02, isStabilized: true, hasImpedance: true,
                            isWeightRemoved: false, weightKg: w, impedanceOhms: imp,
                            deviceTimestamp: nil)
    }

    func testAgeIsComputedAtCaptureTime() {
        let dob = utc(1990, 6, 29)
        XCTAssertEqual(DateMath.ageYears(dateOfBirth: dob, at: utc(2020, 6, 29)), 30)
        XCTAssertEqual(DateMath.ageYears(dateOfBirth: dob, at: utc(2020, 6, 28)), 29) // day before birthday
    }

    func testFinalizeResolveComputeProducesGoldenVector() {
        let capturedAt = utc(2020, 6, 29)
        let owner = UserProfile(id: UUID(), name: "owner", heightCm: 175,
                                dateOfBirth: utc(1990, 6, 29), sex: .male,
                                weightRangeKg: 60...85, isHealthKitOwner: true)
        let partner = UserProfile(id: UUID(), name: "partner", heightCm: 165,
                                  dateOfBirth: utc(1992, 1, 1), sex: .female,
                                  weightRangeKg: 45...59, isHealthKitOwner: false)

        // 1) Finalize a weigh-in (75.0 kg, 500 Ω), capturedAt at the desired date.
        let finalizer = MeasurementFinalizer()
        _ = finalizer.ingest(finalFrame(75.0, 500), at: capturedAt.addingTimeInterval(-0.7))
        let reading = finalizer.ingest(finalFrame(75.0, 500), at: capturedAt)
        let unwrapped = try? XCTUnwrap(reading)
        XCTAssertEqual(unwrapped?.capturedAt, capturedAt)

        // 2) Resolve to a single user by weight range.
        guard case let .matched(user) = UserResolver.resolve(weightKg: 75.0, among: [owner, partner]) else {
            return XCTFail("expected single match")
        }
        XCTAssertEqual(user.name, "owner")

        // 3) Compute body composition for that user at the capture time.
        let bodyProfile = BodyProfile(from: user, at: capturedAt)
        let comp = BodyCompositionCalculator.compute(weightKg: 75.0,
                                                     impedanceOhms: 500,
                                                     profile: bodyProfile)
        XCTAssertEqual(comp.bmi, 24.4898, accuracy: 1e-2)
        XCTAssertEqual(comp.bodyFatPercent, 22.4798, accuracy: 1e-2)
        XCTAssertEqual(comp.leanMassKg, 58.1401, accuracy: 1e-2)
    }
}
