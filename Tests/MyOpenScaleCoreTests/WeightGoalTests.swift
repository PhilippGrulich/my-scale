import XCTest
@testable import MyOpenScaleCore

final class WeightGoalTests: XCTestCase {

    func testLoseDirection() {
        let g = WeightGoal(type: .lose, targetKg: 70, startKg: 80)
        XCTAssertTrue(g.isToward(fromKg: 75, toKg: 74.5))
        XCTAssertFalse(g.isToward(fromKg: 75, toKg: 75.4))
        XCTAssertTrue(g.isToward(fromKg: 75, toKg: 75.05))   // flat counts as toward
        XCTAssertTrue(g.isReached(70)); XCTAssertFalse(g.isReached(70.2))
        XCTAssertEqual(g.progressFraction(75)!, 0.5, accuracy: 1e-9)
        XCTAssertEqual(g.progressFraction(90)!, 0)            // clamped
        XCTAssertTrue(g.isBetter(74.8, than: 75)); XCTAssertFalse(g.isBetter(74.95, than: 75))
    }

    func testGainDirection() {
        let g = WeightGoal(type: .gain, targetKg: 70, startKg: 60)
        XCTAssertTrue(g.isToward(fromKg: 62, toKg: 62.4))
        XCTAssertFalse(g.isToward(fromKg: 62, toKg: 61.5))
        XCTAssertTrue(g.isReached(70.1))
        XCTAssertEqual(g.progressFraction(65)!, 0.5, accuracy: 1e-9)
        XCTAssertTrue(g.isBetter(62.2, than: 62))
    }

    func testMaintainBandAndDirection() {
        let g = WeightGoal(type: .maintain, targetKg: 70, startKg: nil)   // tolerance defaults to 1.0
        XCTAssertTrue(g.isInBand(70.9)); XCTAssertFalse(g.isInBand(71.2))
        XCTAssertTrue(g.isToward(fromKg: 72, toKg: 71.5))    // outside band, moving back
        XCTAssertFalse(g.isToward(fromKg: 72, toKg: 72.5))
        XCTAssertTrue(g.isToward(fromKg: 70.2, toKg: 70.8))  // inside band = on goal
        XCTAssertNil(g.progressFraction(70.5))
        XCTAssertFalse(g.isBetter(69, than: 70))
    }

    func testNoTargetBehavesAsDirectionOnly() {
        let g = WeightGoal(type: .lose, targetKg: nil, startKg: nil)
        XCTAssertTrue(g.isToward(fromKg: 80, toKg: 79.5))
        XCTAssertFalse(g.isReached(10))
        XCTAssertNil(g.progressFraction(79))
    }

    func testSignatureChangesWithGoal() {
        let a = WeightGoal(type: .lose, targetKg: 70, startKg: 80)
        XCTAssertNotEqual(a.signature(), WeightGoal(type: .lose, targetKg: 69, startKg: 80).signature())
        XCTAssertNotEqual(a.signature(), WeightGoal(type: .gain, targetKg: 70, startKg: 80).signature())
    }
}
