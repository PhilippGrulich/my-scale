import SwiftUI
import MyOpenScaleCore

extension BMICategory {
    var title: String {
        switch self {
        case .underweight: return String(localized: "Underweight")
        case .normal: return String(localized: "Healthy weight")
        case .overweight: return String(localized: "Overweight")
        case .obese: return String(localized: "Obesity")
        }
    }

    var color: Color {
        switch self {
        case .underweight: return .blue
        case .normal: return Theme.accent
        case .overweight: return .orange
        case .obese: return .red
        }
    }
}

// MARK: - BMI scale

/// Horizontal BMI scale (15–35) coloured by category, with markers for today's
/// trend BMI and the goal BMI, and the healthy weight range for the height.
struct BMIScaleView: View {
    let currentKg: Double
    var goalKg: Double? = nil
    let heightCm: Double

    private let lower = 15.0, upper = 35.0
    private var bmiNow: Double { BodyCompositionCalculator.bmi(weightKg: currentKg, heightCm: heightCm) }
    private var bmiGoal: Double? { goalKg.map { BodyCompositionCalculator.bmi(weightKg: $0, heightCm: heightCm) } }
    private var healthy: ClosedRange<Double> { GoalInsights.healthyWeightRange(heightCm: heightCm) }

    private func x(_ bmi: Double, _ width: CGFloat) -> CGFloat {
        CGFloat((min(upper, max(lower, bmi)) - lower) / (upper - lower)) * width
    }


    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("BMI", systemImage: "ruler.fill").font(.headline)
                Spacer()
                Text("\(bmiNow.formatted(1)) · \(BMICategory(bmi: bmiNow).title)")
                    .font(.subheadline.weight(.semibold))
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 2) {
                        Rectangle().fill(Color.blue.opacity(0.55)).frame(width: max(0, x(18.5, w) - 2))
                        Rectangle().fill(Theme.accent.opacity(0.75)).frame(width: max(0, x(25, w) - x(18.5, w) - 2))
                        Rectangle().fill(Color.orange.opacity(0.7)).frame(width: max(0, x(30, w) - x(25, w) - 2))
                        Rectangle().fill(Color.red.opacity(0.6))
                    }
                    .frame(height: 10)
                    .clipShape(.capsule)
                    .offset(y: 8)
                    // Goal marker below the bar, today's marker on it.
                    if let bmiGoal {
                        Image(systemName: "target")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.accentSecondary)
                            .position(x: x(bmiGoal, w), y: 32)
                    }
                    Circle()
                        .fill(.white)
                        .overlay(Circle().stroke(Color.primary.opacity(0.8), lineWidth: 2.5))
                        .frame(width: 16, height: 16)
                        .shadow(radius: 1)
                        .position(x: x(bmiNow, w), y: 13)
                        .animation(.snappy, value: bmiNow)
                }
            }
            .frame(height: 42)
            HStack(spacing: 12) {
                Label("Now", systemImage: "circle").font(.caption)
                if let bmiGoal {
                    Label("Goal \(bmiGoal.formatted(1))", systemImage: "target").font(.caption)
                        .foregroundStyle(Theme.accentSecondary)
                }
                Spacer()
                Text("Healthy: \(healthy.lowerBound.formatted(0))–\(healthy.upperBound.formatted(0)) kg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .glassEffect(in: .rect(cornerRadius: 22))
    }
}
