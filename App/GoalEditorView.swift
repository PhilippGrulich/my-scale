import SwiftUI
import MyOpenScaleCore

/// Goal editor (from the Goal tab): target weight with the healthy range for
/// the user's height, an optional target date (the plan) with the pace it
/// needs, and an optional body-fat goal.
struct GoalEditorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var goalKg: Double = 75
    @State private var hasTargetDate = false
    @State private var targetDate = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
    @State private var hasBodyFatGoal = false
    @State private var bodyFatGoal: Double = 20

    private static let range = 30.0...250.0

    private var healthy: ClosedRange<Double> { GoalInsights.healthyWeightRange(heightCm: model.profile.heightCm) }
    private var goalBMI: Double { BodyCompositionCalculator.bmi(weightKg: goalKg, heightCm: model.profile.heightCm) }

    /// Pace the chosen date needs, from today's weight.
    private var requiredWeekly: Double? {
        guard hasTargetDate, let current = model.currentWeightKg else { return nil }
        let weeks = targetDate.timeIntervalSince(Date()) / (7 * 86_400)
        guard weeks > 0.1 else { return nil }
        return (goalKg - current) / weeks
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Target weight")
                        Spacer()
                        TextField("Target weight", value: $goalKg,
                                  format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .frame(maxWidth: 110)
                        Text("kg").foregroundStyle(.secondary)
                        Stepper("Target weight", value: $goalKg, in: Self.range, step: 0.5)
                            .labelsHidden()
                    }
                    LabeledContent("BMI at goal") {
                        Text(goalBMI.formatted(1))
                            .foregroundStyle(BMICategory(bmi: goalBMI) == .normal ? Theme.accent : .orange)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let current = model.currentWeightKg {
                            let diff = goalKg - current
                            if abs(diff) < 0.05 {
                                Text("That's your current weight.")
                            } else if diff < 0 {
                                Text("\(abs(diff).formatted(1)) kg below your current weight.")
                            } else {
                                Text("\(diff.formatted(1)) kg above your current weight.")
                            }
                        }
                        Text("Healthy range for \(Int(model.profile.heightCm)) cm: \(healthy.lowerBound.formatted(0))–\(healthy.upperBound.formatted(0)) kg (BMI 18.5–25).")
                        if goalBMI < 18.5 {
                            Text("This goal is below the healthy range.")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section {
                    Toggle("Target date", isOn: $hasTargetDate.animation())
                    if hasTargetDate {
                        DatePicker("Reach by", selection: $targetDate,
                                   in: Date().addingTimeInterval(7 * 86_400)...,
                                   displayedComponents: .date)
                    }
                } footer: {
                    if let pace = requiredWeekly {
                        if abs(pace) > 1 {
                            Text("That needs \(abs(pace).formatted(1)) kg per week — more than 1 kg per week is hard to keep up.")
                                .foregroundStyle(.orange)
                        } else {
                            Text("That needs \(abs(pace).formatted(1)) kg per week.")
                        }
                    } else {
                        Text("With a date, the Goal tab shows whether you're on plan.")
                    }
                }

                Section {
                    Toggle("Body-fat goal", isOn: $hasBodyFatGoal.animation())
                    if hasBodyFatGoal {
                        HStack {
                            Text("Target")
                            Spacer()
                            Text("\(bodyFatGoal.formatted(1)) %").foregroundStyle(.secondary)
                            Stepper("Target", value: $bodyFatGoal, in: 5...45, step: 0.5)
                                .labelsHidden()
                        }
                    }
                } footer: {
                    if hasBodyFatGoal, let fat = model.latestValue(.bodyFat), fat.isFinite {
                        Text("Currently \(fat.formatted(1)) %.")
                    }
                }

                if model.profile.goalWeightKg != nil {
                    Section {
                        Button("Remove goal", role: .destructive) {
                            var updated = model.profile
                            updated.goalWeightKg = nil
                            updated.goalBodyFatPercent = nil
                            model.saveProfile(updated)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!Self.range.contains(goalKg))
                }
            }
            .onAppear(perform: load)
        }
        .tint(Theme.accent)
    }

    private func load() {
        let p = model.profile
        if let goal = p.goalWeightKg {
            goalKg = goal
        } else if let current = model.currentWeightKg {
            goalKg = ((current - 3) * 2).rounded() / 2
        }
        if let date = p.goalTargetDate { hasTargetDate = true; targetDate = date }
        if let fat = p.goalBodyFatPercent {
            hasBodyFatGoal = true
            bodyFatGoal = fat
        } else if let fat = model.latestValue(.bodyFat), fat.isFinite {
            bodyFatGoal = ((fat - 3) * 2).rounded() / 2
        }
    }

    private func save() {
        var updated = model.profile
        updated.goalWeightKg = (goalKg * 10).rounded() / 10
        updated.goalTargetDate = hasTargetDate ? targetDate : nil
        updated.goalBodyFatPercent = hasBodyFatGoal ? bodyFatGoal : nil
        model.saveProfile(updated)
        dismiss()
    }
}
