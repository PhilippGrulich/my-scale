import SwiftUI
import MyOpenScaleCore

/// Minimal single-profile editor for the HealthKit owner (v1). Full profile
/// CRUD + Unassigned queue is M5b.
struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft: StoredProfile
    private let onSave: (StoredProfile) -> Void

    init(profile: StoredProfile, onSave: @escaping (StoredProfile) -> Void) {
        _draft = State(initialValue: profile)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                ProfileFieldsView(draft: $draft)

                Section("Goal") {
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
                        Button("Set a weight goal") { draft.goalWeightKg = 75 }
                    }
                }

                Section {
                    Label("Your weigh-ins are recognised automatically from your weight and body-composition signature — no weight range to configure.",
                          systemImage: "person.fill.checkmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(draft); dismiss() }
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
