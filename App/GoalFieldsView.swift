import SwiftUI
import MyOpenScaleCore

/// The "Goal" form section: direction (lose / gain / maintain) plus an optional target weight.
struct GoalFieldsView: View {
    @Binding var draft: StoredProfile
    let currentWeightKg: Double?

    /// Starting target: the current weight rounded to 0.5 kg, else the long-standing 75 kg default.
    private var startingTarget: Double {
        guard let kg = currentWeightKg else { return 75 }
        return min(250, max(30, (kg * 2).rounded() / 2))
    }

    var body: some View {
        Section("Goal") {
            Picker("Goal type", selection: Binding(get: { draft.goalType ?? .lose },
                                                   set: { draft.goalType = $0 })) {
                Text("Lose weight").tag(GoalType.lose)
                Text("Gain weight").tag(GoalType.gain)
                Text("Maintain").tag(GoalType.maintain)
            }
            .pickerStyle(.segmented)

            if let goal = draft.goalWeightKg {
                Stepper(value: Binding(get: { goal }, set: { draft.goalWeightKg = $0 }),
                        in: 30...250, step: 0.5) {
                    HStack {
                        Text("Target weight")
                        Spacer()
                        Text(goal.formatted(1) + " kg").foregroundStyle(.secondary)
                    }
                }
                Button("Remove goal", role: .destructive) { draft.goalWeightKg = nil }
            } else {
                Button("Set a weight goal") { draft.goalWeightKg = startingTarget }
            }
        }
    }
}
