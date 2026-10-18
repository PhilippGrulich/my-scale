import XCTest
@testable import MyOpenScaleCore

final class BodyMetricsTests: XCTestCase {

    private let man = BodyProfile(heightCm: 175, ageYears: 30, sex: .male)
    private let woman = BodyProfile(heightCm: 165, ageYears: 45, sex: .female)

    func testTypicalManGetsPlausibleValues() {
        let v = BodyMetricsCalculator.compute(weightKg: 80, impedanceOhms: 500, profile: man)
        XCTAssertEqual(v.bodyFatPercent, BodyCompositionCalculator.compute(weightKg: 80, impedanceOhms: 500, profile: man).bodyFatPercent)
        XCTAssertTrue((45...65).contains(v.waterPercent), "water \(v.waterPercent)")
        XCTAssertTrue((2...4).contains(v.boneMassKg), "bone \(v.boneMassKg)")
        XCTAssertTrue((50...70).contains(v.muscleMassKg), "muscle \(v.muscleMassKg)")
        XCTAssertTrue((1...20).contains(v.visceralFat), "visceral \(v.visceralFat)")
        XCTAssertTrue((1600...2000).contains(v.bmrKcal), "bmr \(v.bmrKcal)")
        XCTAssertTrue((15...60).contains(v.metabolicAge), "metabolic age \(v.metabolicAge)")
        XCTAssertTrue((5...32).contains(v.proteinPercent), "protein \(v.proteinPercent)")
        // Fat + lean add up to the weight; muscle is lean minus bone.
        XCTAssertEqual(v.leanMassKg + 80 * v.bodyFatPercent / 100, 80, accuracy: 1e-6)
        XCTAssertEqual(v.muscleMassKg, v.leanMassKg - v.boneMassKg, accuracy: 1e-6)
    }

    func testTypicalWomanGetsPlausibleValues() {
        let v = BodyMetricsCalculator.compute(weightKg: 65, impedanceOhms: 550, profile: woman)
        XCTAssertTrue((40...60).contains(v.waterPercent), "water \(v.waterPercent)")
        XCTAssertTrue((1.5...3.5).contains(v.boneMassKg), "bone \(v.boneMassKg)")
        XCTAssertTrue((1100...1600).contains(v.bmrKcal), "bmr \(v.bmrKcal)")
    }

    func testHigherImpedanceMeansMoreFatAndLessWater() {
        let low = BodyMetricsCalculator.compute(weightKg: 80, impedanceOhms: 400, profile: man)
        let high = BodyMetricsCalculator.compute(weightKg: 80, impedanceOhms: 650, profile: man)
        XCTAssertGreaterThan(high.bodyFatPercent, low.bodyFatPercent)
        XCTAssertLessThan(high.waterPercent, low.waterPercent)
        XCTAssertLessThan(high.muscleMassKg, low.muscleMassKg)
        XCTAssertGreaterThan(high.metabolicAge, low.metabolicAge)
    }

    func testHeavierMeansHigherBMRAndVisceralFat() {
        let a = BodyMetricsCalculator.compute(weightKg: 75, impedanceOhms: 500, profile: man)
        let b = BodyMetricsCalculator.compute(weightKg: 95, impedanceOhms: 500, profile: man)
        XCTAssertGreaterThan(b.bmrKcal, a.bmrKcal)
        XCTAssertGreaterThan(b.visceralFat, a.visceralFat)
    }

    func testStatusAgainstReferenceRanges() {
        XCTAssertEqual(BodyMetricRanges.status(.bodyFat, value: 15, sex: .male, ageYears: 30), .normal)
        XCTAssertEqual(BodyMetricRanges.status(.bodyFat, value: 23, sex: .male, ageYears: 30), .high)
        XCTAssertEqual(BodyMetricRanges.status(.bodyFat, value: 28, sex: .male, ageYears: 30), .veryHigh)
        XCTAssertEqual(BodyMetricRanges.status(.bodyFat, value: 18, sex: .female, ageYears: 30), .low)
        XCTAssertEqual(BodyMetricRanges.status(.visceralFat, value: 8, sex: .male, ageYears: 30), .normal)
        XCTAssertEqual(BodyMetricRanges.status(.visceralFat, value: 12, sex: .male, ageYears: 30), .high)
        XCTAssertEqual(BodyMetricRanges.status(.visceralFat, value: 16, sex: .male, ageYears: 30), .veryHigh)
        XCTAssertEqual(BodyMetricRanges.status(.metabolicAge, value: 28, sex: .male, ageYears: 30), .normal)
        XCTAssertEqual(BodyMetricRanges.status(.metabolicAge, value: 35, sex: .male, ageYears: 30), .high)
        XCTAssertNil(BodyMetricRanges.status(.muscle, value: 60, sex: .male, ageYears: 30))
        XCTAssertEqual(BodyMetricRanges.normalRange(.water, sex: .female, ageYears: 40), 45...60)
    }
}
