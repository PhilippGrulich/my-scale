import SwiftUI

/// Quick goal editor, opened from the "To goal" stat on the overview. Same
/// goal as Profile → Goal; starts from the current goal, or a little below the
/// current weight when none is set yet.
struct GoalEditorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var goalKg: Double = 75

    private static let range = 30.0...250.0

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
                } footer: {
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
                }

                if model.profile.goalWeightKg != nil {
                    Section {
                        Button("Remove goal", role: .destructive) {
                            var updated = model.profile
                            updated.goalWeightKg = nil
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
                    Button("Save") {
                        var updated = model.profile
                        updated.goalWeightKg = (goalKg * 10).rounded() / 10
                        model.saveProfile(updated)
                        dismiss()
                    }
                    .disabled(!Self.range.contains(goalKg))
                }
            }
            .onAppear {
                if let goal = model.profile.goalWeightKg {
                    goalKg = goal
                } else if let current = model.currentWeightKg {
                    goalKg = ((current - 3) * 2).rounded() / 2
                }
            }
        }
        .tint(Theme.accent)
        .presentationDetents([.medium])
    }
}
