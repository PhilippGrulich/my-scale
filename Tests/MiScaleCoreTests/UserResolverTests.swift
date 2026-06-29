import XCTest
@testable import MiScaleCore

final class UserResolverTests: XCTestCase {

    private func profile(_ name: String,
                         _ range: ClosedRange<Double>,
                         sex: BiologicalSex = .male) -> UserProfile {
        UserProfile(id: UUID(), name: name, heightCm: 175,
                    dateOfBirth: Date(timeIntervalSince1970: 0), sex: sex,
                    weightRangeKg: range, isHealthKitOwner: name == "owner")
    }

    func testSingleMatch() {
        let users = [profile("a", 45...60), profile("owner", 60.01...95)]
        guard case let .matched(u) = UserResolver.resolve(weightKg: 75, among: users) else {
            return XCTFail("expected match")
        }
        XCTAssertEqual(u.name, "owner")
    }

    func testNoMatch() {
        let users = [profile("a", 45...60), profile("b", 90...120)]
        XCTAssertEqual(UserResolver.resolve(weightKg: 75, among: users), .noMatch)
    }

    func testAmbiguousWhenRangesOverlap() {
        let users = [profile("a", 60...80), profile("b", 70...95)]
        guard case let .ambiguous(matches) = UserResolver.resolve(weightKg: 75, among: users) else {
            return XCTFail("expected ambiguous")
        }
        XCTAssertEqual(matches.count, 2)
    }

    func testBoundaryIsInclusive() {
        let users = [profile("a", 60...80)]
        guard case .matched = UserResolver.resolve(weightKg: 80, among: users) else {
            return XCTFail("upper bound should match (closed range)")
        }
    }

    func testRangeWarningsFlagOverlap() {
        let warnings = UserResolver.rangeWarnings([profile("a", 60...80), profile("b", 75...95)])
        XCTAssertEqual(warnings.filter { $0.kind == .overlap }.count, 1)
        XCTAssertTrue(warnings.allSatisfy { $0.kind != .gap })
    }

    func testRangeWarningsFlagGap() {
        let warnings = UserResolver.rangeWarnings([profile("a", 50...60), profile("b", 70...80)])
        XCTAssertEqual(warnings.filter { $0.kind == .gap }.count, 1)
        XCTAssertTrue(warnings.allSatisfy { $0.kind != .overlap })
    }

    func testTouchingRangesAreOverlapNotGap() {
        // Shared boundary 60 matches both → genuinely ambiguous.
        let warnings = UserResolver.rangeWarnings([profile("a", 50...60), profile("b", 60...80)])
        XCTAssertEqual(warnings.filter { $0.kind == .overlap }.count, 1)
        XCTAssertEqual(warnings.filter { $0.kind == .gap }.count, 0)
    }

    func testSingleProfileHasNoWarnings() {
        XCTAssertTrue(UserResolver.rangeWarnings([profile("a", 50...90)]).isEmpty)
    }
}
