import XCTest
@testable import MyOpenScaleCore

final class AttributionClassifierTests: XCTestCase {

    private let config = AttributionConfig()   // ±7 kg, ±80 Ω

    func testFirstReadingBootstrapsAsOwner() {
        let decision = AttributionClassifier.decide(weightKg: 80, impedanceOhms: 500,
                                                    model: AttributionModel(), config: config)
        XCTAssertEqual(decision, .me)
    }

    func testLearnMeSeedsThenMatchesNearbyReading() {
        var model = AttributionModel()
        model = AttributionClassifier.learnMe(model, weightKg: 80, impedanceOhms: 500, config: config)
        XCTAssertEqual(model.me?.sampleCount, 1)
        // Same person next day: small weight + impedance wobble → still me.
        let decision = AttributionClassifier.decide(weightKg: 81, impedanceOhms: 530,
                                                    model: model, config: config)
        XCTAssertEqual(decision, .me)
    }

    func testSimilarWeightDifferentImpedanceIsNotAutoMe() {
        var model = AttributionModel()
        model = AttributionClassifier.learnMe(model, weightKg: 80, impedanceOhms: 500, config: config)
        // Same weight, very different body composition (impedance) → not me.
        let decision = AttributionClassifier.decide(weightKg: 80, impedanceOhms: 750,
                                                    model: model, config: config)
        XCTAssertEqual(decision, .uncertain)
    }

    func testKnownOtherIsSilentlySkipped() {
        var model = AttributionModel()
        model = AttributionClassifier.learnMe(model, weightKg: 80, impedanceOhms: 500, config: config)
        // A housemate gets rejected once...
        model = AttributionClassifier.learnOther(model, weightKg: 62, impedanceOhms: 600, config: config)
        // ...so their next weigh-in is auto-skipped, no prompt.
        let decision = AttributionClassifier.decide(weightKg: 62.5, impedanceOhms: 590,
                                                    model: model, config: config)
        XCTAssertEqual(decision, .other)
    }

    func testUnknownBodyIsUncertain() {
        var model = AttributionModel()
        model = AttributionClassifier.learnMe(model, weightKg: 80, impedanceOhms: 500, config: config)
        let decision = AttributionClassifier.decide(weightKg: 55, impedanceOhms: 650,
                                                    model: model, config: config)
        XCTAssertEqual(decision, .uncertain)
    }

    func testEMATracksGradualWeightChange() {
        var model = AttributionModel()
        model = AttributionClassifier.learnMe(model, weightKg: 80, impedanceOhms: 500, config: config)
        // Lose weight gradually; each reading stays within tolerance and pulls the
        // signature down so far-future weights still classify as me.
        for w in stride(from: 79.0, through: 72.0, by: -1.0) {
            XCTAssertEqual(AttributionClassifier.decide(weightKg: w, impedanceOhms: 500,
                                                        model: model, config: config), .me)
            model = AttributionClassifier.learnMe(model, weightKg: w, impedanceOhms: 500, config: config)
        }
        XCTAssertLessThan(model.me!.weightKg, 76)   // signature followed the trend down
    }

    func testOthersAreCappedAtMaxOthers() {
        var model = AttributionModel()
        let cfg = AttributionConfig(maxOthers: 2)
        // Three well-separated others; only the most recent two are retained.
        model = AttributionClassifier.learnOther(model, weightKg: 50, impedanceOhms: 400, config: cfg)
        model = AttributionClassifier.learnOther(model, weightKg: 70, impedanceOhms: 550, config: cfg)
        model = AttributionClassifier.learnOther(model, weightKg: 95, impedanceOhms: 700, config: cfg)
        XCTAssertEqual(model.others.count, 2)
    }
}
