import XCTest
@testable import MyOpenScaleCore

final class BodyCompositionCalculatorTests: XCTestCase {

    // Hand-computed golden vector: male, 175 cm, 75 kg, 500 Ω, age 30.
    func testComputeMaleGoldenVector() {
        let profile = BodyProfile(heightCm: 175, ageYears: 30, sex: .male)
        let result = BodyCompositionCalculator.compute(weightKg: 75,
                                                       impedanceOhms: 500,
                                                       profile: profile)
        XCTAssertEqual(result.bodyMassKg, 75, accuracy: 1e-6)
        XCTAssertEqual(result.bmi, 24.4898, accuracy: 1e-2)
        XCTAssertEqual(result.bodyFatPercent, 22.4798, accuracy: 1e-2)
        XCTAssertEqual(result.leanMassKg, 58.1401, accuracy: 1e-2)
    }

    // Hand-computed golden vector: female, 165 cm, 62 kg, 550 Ω, age 40.
    func testComputeFemaleGoldenVector() {
        let profile = BodyProfile(heightCm: 165, ageYears: 40, sex: .female)
        let result = BodyCompositionCalculator.compute(weightKg: 62,
                                                       impedanceOhms: 550,
                                                       profile: profile)
        XCTAssertEqual(result.bmi, 22.7732, accuracy: 1e-2)
        XCTAssertEqual(result.bodyFatPercent, 33.7051, accuracy: 1e-2)
        XCTAssertEqual(result.leanMassKg, 41.1028, accuracy: 1e-2)
    }

    func testBMIIsClampedToRange() {
        // Absurdly light/tall and heavy/short inputs hit the [10, 90] clamp.
        XCTAssertEqual(BodyCompositionCalculator.bmi(weightKg: 1, heightCm: 200), 10, accuracy: 1e-9)
        XCTAssertEqual(BodyCompositionCalculator.bmi(weightKg: 300, heightCm: 150), 90, accuracy: 1e-9)
    }

    func testFatPercentIsClampedToRange() {
        // Force a large LBM so the raw fat% would underflow below 5%.
        let profile = BodyProfile(heightCm: 180, ageYears: 25, sex: .male)
        let fat = BodyCompositionCalculator.fatPercentage(lbm: 90, weightKg: 70, profile: profile)
        XCTAssertEqual(fat, 5, accuracy: 1e-9)
    }

    func testPartialLeavesFatAndLeanUndefinedButKeepsBMI() {
        let profile = BodyProfile(heightCm: 170, ageYears: 35, sex: .female)
        let result = BodyCompositionCalculator.partial(weightKg: 64, profile: profile)
        XCTAssertEqual(result.bodyMassKg, 64, accuracy: 1e-9)
        XCTAssertEqual(result.bmi, 22.1453, accuracy: 1e-2)
        XCTAssertTrue(result.bodyFatPercent.isNaN)
        XCTAssertTrue(result.leanMassKg.isNaN)
    }
}
