import Foundation
import HealthKit
import MiScaleCore

/// Writes the four HealthKit-native body metrics. HealthKit is single-profile
/// per device, so only the owner user's readings reach here.
final class HealthKitSink {

    enum SinkError: Error { case unavailable }

    private let store = HKHealthStore()

    private var writeTypes: Set<HKSampleType> {
        [
            HKQuantityType(.bodyMass),
            HKQuantityType(.bodyFatPercentage),
            HKQuantityType(.leanBodyMass),
            HKQuantityType(.bodyMassIndex),
        ]
    }

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        guard Self.isAvailable else { throw SinkError.unavailable }
        let read: Set<HKObjectType> = [
            HKCharacteristicType(.dateOfBirth),
            HKCharacteristicType(.biologicalSex),
        ]
        try await store.requestAuthorization(toShare: writeTypes, read: read)
    }

    /// Save the available metrics as one batch. NaN metrics (no impedance) are
    /// skipped; weight and BMI are always written.
    func write(_ composition: BodyComposition, at date: Date, impedanceOhms: Int) async throws {
        guard Self.isAvailable else { throw SinkError.unavailable }

        let metadata: [String: Any] = [
            HKMetadataKeyWasUserEntered: false,
            "impedanceOhms": impedanceOhms,
        ]
        let kg = HKUnit.gramUnit(with: .kilo)
        var samples: [HKSample] = [
            HKQuantitySample(type: HKQuantityType(.bodyMass),
                             quantity: HKQuantity(unit: kg, doubleValue: composition.bodyMassKg),
                             start: date, end: date, metadata: metadata),
            HKQuantitySample(type: HKQuantityType(.bodyMassIndex),
                             quantity: HKQuantity(unit: .count(), doubleValue: composition.bmi),
                             start: date, end: date, metadata: metadata),
        ]
        if !composition.bodyFatPercent.isNaN {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.bodyFatPercentage),
                quantity: HKQuantity(unit: .percent(), doubleValue: composition.bodyFatPercent / 100.0),
                start: date, end: date, metadata: metadata))
        }
        if !composition.leanMassKg.isNaN {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.leanBodyMass),
                quantity: HKQuantity(unit: kg, doubleValue: composition.leanMassKg),
                start: date, end: date, metadata: metadata))
        }
        try await store.save(samples)
    }
}
