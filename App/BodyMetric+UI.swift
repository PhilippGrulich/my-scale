import SwiftUI
import MyOpenScaleCore

/// Presentation for each body metric: name, unit, icon, colour, and the
/// explanation shown on its detail page.
extension BodyMetric {
    var title: String {
        switch self {
        case .bodyFat: return String(localized: "Body Fat")
        case .muscle: return String(localized: "Muscle mass")
        case .water: return String(localized: "Body water")
        case .visceralFat: return String(localized: "Visceral fat")
        case .lean: return String(localized: "Lean Mass")
        case .bone: return String(localized: "Bone mass")
        case .bmr: return String(localized: "Basal metabolic rate")
        case .metabolicAge: return String(localized: "Metabolic age")
        case .protein: return String(localized: "Protein")
        }
    }

    var unit: String {
        switch self {
        case .bodyFat, .water, .protein: return "%"
        case .muscle, .lean, .bone: return "kg"
        case .visceralFat: return ""
        case .bmr: return "kcal"
        case .metabolicAge: return String(localized: "yrs")
        }
    }

    var systemImage: String {
        switch self {
        case .bodyFat: return "drop.fill"
        case .muscle: return "figure.strengthtraining.traditional"
        case .water: return "drop.circle.fill"
        case .visceralFat: return "circle.circle.fill"
        case .lean: return "figure.arms.open"
        case .bone: return "figure.walk"
        case .bmr: return "flame.fill"
        case .metabolicAge: return "hourglass"
        case .protein: return "leaf.fill"
        }
    }

    var tint: Color {
        switch self {
        case .bodyFat: return .orange
        case .muscle: return .red
        case .water: return .cyan
        case .visceralFat: return .pink
        case .lean: return Theme.accentSecondary
        case .bone: return .gray
        case .bmr: return .yellow
        case .metabolicAge: return .purple
        case .protein: return .green
        }
    }

    private var digits: Int {
        switch self {
        case .visceralFat, .bmr, .metabolicAge: return 0
        default: return 1
        }
    }

    func format(_ value: Double) -> String { value.formatted(digits) }

    /// "80,4 kg", "1.786 kcal", "12"
    func formatWithUnit(_ value: Double) -> String {
        unit.isEmpty ? format(value) : "\(format(value)) \(unit)"
    }

    /// What the value is, in two or three sentences.
    var explanation: String {
        switch self {
        case .bodyFat:
            return String(localized: "The share of your weight that is fat. Some fat is essential; too much — especially around the organs — raises the risk of heart disease and diabetes.")
        case .muscle:
            return String(localized: "The weight of your muscles, including water held in them. More muscle raises your resting calorie burn and protects joints and bones; keeping it while losing weight is a good sign.")
        case .water:
            return String(localized: "The share of your weight that is water. It drops when body fat rises, and it changes with drinking, salt and exercise — so day-to-day swings are normal.")
        case .visceralFat:
            return String(localized: "A rating for the fat around your inner organs. It is more strongly linked to health risks than fat under the skin: 1–9 is healthy, 10–14 high, 15 and above very high.")
        case .lean:
            return String(localized: "Everything that isn't fat: muscles, bones, organs and water. Your weight minus your body fat.")
        case .bone:
            return String(localized: "An estimate of the mineral weight of your skeleton. It changes very slowly; the scale derives it from your lean mass, so it is a rough guide only.")
        case .bmr:
            return String(localized: "The calories your body burns at complete rest in a day — for breathing, circulation and keeping warm. Your total daily need is higher, depending on how active you are.")
        case .metabolicAge:
            return String(localized: "Compares your basal metabolic rate with the average of different age groups. Below your real age suggests a favourable body composition.")
        case .protein:
            return String(localized: "The share of your weight that is protein, mostly in muscle. It's estimated from muscle mass and body water.")
        }
    }
}

extension MetricStatus {
    func title(for metric: BodyMetric) -> String {
        if metric == .metabolicAge {
            return self == .normal ? String(localized: "Younger than you") : String(localized: "Older than you")
        }
        switch self {
        case .low: return String(localized: "Low")
        case .normal: return String(localized: "Normal")
        case .high: return String(localized: "High")
        case .veryHigh: return String(localized: "Very high")
        }
    }

    var color: Color {
        switch self {
        case .low: return .blue
        case .normal: return Theme.accent
        case .high: return .orange
        case .veryHigh: return .red
        }
    }
}
