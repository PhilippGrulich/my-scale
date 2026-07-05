import XCTest
@testable import MyOpenScaleCore

final class AdvertisementParserTests: XCTestCase {

    // Stabilized + impedance, kg: 75.0 kg, 500 Ω, 2024-06-29 21:08:15.
    private let stableKg = "0222e807061d15080ff401983a"
    // Same weigh-in, early frame: no flags set, impedance 0.
    private let nonStabilized = "0200e807061d15080f0000983a"
    // Weight-removed frame (ctrl bit7 set).
    private let weightRemoved = "02a2e807061d15080ff401983a"
    // Pound unit (byte0 bit0 set): 165.3 lb, 480 Ω.
    private let stableLb = "0322e807061d15080fe0019240"
    // Stabilized + impedance flag, but impedance 4000 Ω is out of range.
    private let impedanceOutOfRange = "0222e807061d15080fa00f983a"

    func testParsesStabilizedKilogramFrame() throws {
        let adv = try XCTUnwrap(AdvertisementParser.parse(hexData(stableKg)))
        XCTAssertEqual(adv.unitRaw, 0x02)
        XCTAssertTrue(adv.isStabilized)
        XCTAssertTrue(adv.hasImpedance)
        XCTAssertFalse(adv.isWeightRemoved)
        XCTAssertEqual(adv.weightKg, 75.0, accuracy: 1e-9)
        XCTAssertEqual(adv.impedanceOhms, 500)
        XCTAssertTrue(adv.isFinalReading)
    }

    func testParsesEmbeddedTimestampInUTC() throws {
        let adv = try XCTUnwrap(AdvertisementParser.parse(hexData(stableKg)))
        let date = try XCTUnwrap(adv.deviceTimestamp)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        XCTAssertEqual(c.year, 2024)
        XCTAssertEqual(c.month, 6)
        XCTAssertEqual(c.day, 29)
        XCTAssertEqual(c.hour, 21)
        XCTAssertEqual(c.minute, 8)
        XCTAssertEqual(c.second, 15)
    }

    func testNonStabilizedFrameIsNotFinal() throws {
        let adv = try XCTUnwrap(AdvertisementParser.parse(hexData(nonStabilized)))
        XCTAssertFalse(adv.isStabilized)
        XCTAssertFalse(adv.hasImpedance)
        XCTAssertEqual(adv.impedanceOhms, 0)
        XCTAssertFalse(adv.isFinalReading)
    }

    func testWeightRemovedFrameIsNotFinal() throws {
        let adv = try XCTUnwrap(AdvertisementParser.parse(hexData(weightRemoved)))
        XCTAssertTrue(adv.isWeightRemoved)
        XCTAssertFalse(adv.isFinalReading)
    }

    func testPoundFrameNormalizesToKilograms() throws {
        let adv = try XCTUnwrap(AdvertisementParser.parse(hexData(stableLb)))
        XCTAssertEqual(adv.unitRaw, 0x03)
        // 165.3 lb -> kg
        XCTAssertEqual(adv.weightKg, 74.9788, accuracy: 1e-3)
        XCTAssertEqual(adv.impedanceOhms, 480)
        XCTAssertTrue(adv.isFinalReading)
    }

    func testImpedanceOutOfRangeIsNotFinal() throws {
        let adv = try XCTUnwrap(AdvertisementParser.parse(hexData(impedanceOutOfRange)))
        XCTAssertEqual(adv.impedanceOhms, 4000)
        XCTAssertTrue(adv.hasImpedance)
        XCTAssertFalse(adv.isFinalReading)
    }

    func testWrongLengthReturnsNil() {
        XCTAssertNil(AdvertisementParser.parse(hexData("0222e807061d15080ff40198"))) // 12 bytes
        XCTAssertNil(AdvertisementParser.parse(Data()))
    }

    // MARK: - Helper

    private func hexData(_ hex: String) -> Data {
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            data.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return data
    }
}
