import Foundation

/// Decoded view of one MiScale 2 advertisement (service UUID 0x181B service
/// data). Pure value type — no CoreBluetooth import — so it is testable from
/// captured hex payloads with no hardware.
public struct ParsedAdvertisement: Equatable, Sendable {
    /// Raw unit/measurement byte (offset 0): 0x02 = kg, 0x03 = lb.
    public var unitRaw: UInt8
    /// Control byte bit 5 — measurement is stable/complete.
    public var isStabilized: Bool
    /// Control byte bit 1 — impedance is present in this frame.
    public var hasImpedance: Bool
    /// Control byte bit 7 — load lifted off the scale.
    public var isWeightRemoved: Bool
    /// Weight normalized to kilograms (lb / catty converted).
    public var weightKg: Double
    /// Decoded impedance in ohms (raw little-endian uint16; validate separately).
    public var impedanceOhms: Int
    /// Scale's embedded timestamp (informational — the RTC drifts/resets, so the
    /// pipeline trusts the host clock instead). Nil if the bytes don't form a date.
    public var deviceTimestamp: Date?

    public init(unitRaw: UInt8,
                isStabilized: Bool,
                hasImpedance: Bool,
                isWeightRemoved: Bool,
                weightKg: Double,
                impedanceOhms: Int,
                deviceTimestamp: Date?) {
        self.unitRaw = unitRaw
        self.isStabilized = isStabilized
        self.hasImpedance = hasImpedance
        self.isWeightRemoved = isWeightRemoved
        self.weightKg = weightKg
        self.impedanceOhms = impedanceOhms
        self.deviceTimestamp = deviceTimestamp
    }

    /// True when this frame represents a complete, usable body-composition
    /// reading: stabilized, impedance present, load still on, impedance in range.
    public var isFinalReading: Bool {
        isStabilized && hasImpedance && !isWeightRemoved && (1...3000).contains(impedanceOhms)
    }
}

/// Parser for the MiScale 2 (MIBFS) 13-byte 0x181B service-data payload.
///
/// Byte/bit layout verified against ESPHome `xiaomi_miscale` and openScale
/// `BluetoothMiScale2.java`:
///
///   0      unit byte (bit0 = lb, bit6 = catty/jin; 0x02 = kg)
///   1      control flags (bit1 impedance, bit5 stabilized, bit7 weight-removed)
///   2..3   year   (uint16 LE)
///   4      month
///   5      day
///   6      hour
///   7      minute
///   8      second
///   9..10  impedance (uint16 LE, ohms)
///   11..12 weight    (uint16 LE; ÷200 kg, ÷100 lb/catty)
public enum AdvertisementParser {

    public static let expectedLength = 13

    /// Pound → kilogram. Catty (Chinese jin) → kilogram is treated as 0.5 kg/jin
    /// and is UNVERIFIED; the scale should be set to kg (see plan).
    private static let lbToKg = 0.45359237
    private static let cattyToKg = 0.5

    /// Parse raw service-data bytes. Returns nil for the wrong length.
    public static func parse(_ data: Data) -> ParsedAdvertisement? {
        guard data.count == expectedLength else { return nil }
        let b = [UInt8](data)

        let unit = b[0]
        let ctrl = b[1]
        let isStabilized = (ctrl & 0x20) != 0
        let hasImpedance = (ctrl & 0x02) != 0
        let isWeightRemoved = (ctrl & 0x80) != 0

        let rawWeight = le16(b, 11)
        let weightKg: Double
        if (unit & 0x01) != 0 {                // lb
            weightKg = Double(rawWeight) / 100.0 * lbToKg
        } else if (unit & 0x40) != 0 {         // catty / jin
            weightKg = Double(rawWeight) / 100.0 * cattyToKg
        } else {                               // kg
            weightKg = Double(rawWeight) / 200.0
        }

        let impedance = Int(le16(b, 9))
        let timestamp = decodeTimestamp(b)

        return ParsedAdvertisement(unitRaw: unit,
                                   isStabilized: isStabilized,
                                   hasImpedance: hasImpedance,
                                   isWeightRemoved: isWeightRemoved,
                                   weightKg: weightKg,
                                   impedanceOhms: impedance,
                                   deviceTimestamp: timestamp)
    }

    // MARK: - Helpers

    private static func le16(_ b: [UInt8], _ i: Int) -> UInt16 {
        UInt16(b[i]) | (UInt16(b[i + 1]) << 8)
    }

    /// Build a Date from bytes 2..8. Interpreted in UTC; informational only.
    private static func decodeTimestamp(_ b: [UInt8]) -> Date? {
        var comps = DateComponents()
        comps.year = Int(le16(b, 2))
        comps.month = Int(b[4])
        comps.day = Int(b[5])
        comps.hour = Int(b[6])
        comps.minute = Int(b[7])
        comps.second = Int(b[8])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let date = calendar.date(from: comps), calendar.isDateValid(comps) else { return nil }
        return date
    }
}

private extension Calendar {
    /// Reject obviously-empty/zero timestamps (month/day must be in range).
    func isDateValid(_ comps: DateComponents) -> Bool {
        guard let m = comps.month, let d = comps.day, let y = comps.year else { return false }
        return (1...12).contains(m) && (1...31).contains(d) && y >= 2015
    }
}
