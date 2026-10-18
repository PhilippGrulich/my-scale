import SwiftUI
import HealthKit

/// Names and symbols for the workout types people actually log; anything else
/// shows as a generic workout.
extension HKWorkoutActivityType {
    var title: String {
        switch self {
        case .running: return String(localized: "Running")
        case .walking: return String(localized: "Walking")
        case .hiking: return String(localized: "Hiking")
        case .cycling: return String(localized: "Cycling")
        case .swimming: return String(localized: "Swimming")
        case .rowing: return String(localized: "Rowing")
        case .elliptical: return String(localized: "Elliptical")
        case .stairClimbing: return String(localized: "Stairs")
        case .traditionalStrengthTraining, .functionalStrengthTraining: return String(localized: "Strength training")
        case .highIntensityIntervalTraining: return String(localized: "HIIT")
        case .yoga: return String(localized: "Yoga")
        case .pilates: return String(localized: "Pilates")
        case .dance: return String(localized: "Dance")
        case .soccer: return String(localized: "Football")
        case .tennis: return String(localized: "Tennis")
        case .crossTraining: return String(localized: "Cross training")
        case .coreTraining: return String(localized: "Core training")
        case .mindAndBody: return String(localized: "Mind & body")
        default: return String(localized: "Workout")
        }
    }

    var systemImage: String {
        switch self {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .hiking: return "figure.hiking"
        case .cycling: return "figure.outdoor.cycle"
        case .swimming: return "figure.pool.swim"
        case .rowing: return "figure.rower"
        case .elliptical: return "figure.elliptical"
        case .stairClimbing: return "figure.stairs"
        case .traditionalStrengthTraining: return "figure.strengthtraining.traditional"
        case .functionalStrengthTraining: return "figure.strengthtraining.functional"
        case .highIntensityIntervalTraining: return "figure.highintensity.intervaltraining"
        case .yoga: return "figure.yoga"
        case .pilates: return "figure.pilates"
        case .dance: return "figure.dance"
        case .soccer: return "figure.soccer"
        case .tennis: return "figure.tennis"
        case .crossTraining: return "figure.cross.training"
        case .coreTraining: return "figure.core.training"
        case .mindAndBody: return "figure.mind.and.body"
        default: return "figure.mixed.cardio"
        }
    }
}
