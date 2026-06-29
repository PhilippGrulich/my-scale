import SwiftUI
import MiScaleCore

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
                Section("Identity") {
                    TextField("Name", text: $draft.name)
                    DatePicker("Date of birth",
                               selection: $draft.dateOfBirth,
                               in: ...Date(),
                               displayedComponents: .date)
                    Picker("Biological sex", selection: $draft.sex) {
                        Text("Male").tag(BiologicalSex.male)
                        Text("Female").tag(BiologicalSex.female)
                    }
                }

                Section("Body") {
                    stepperRow("Height", value: $draft.heightCm, unit: "cm", range: 100...230, step: 1)
                }

                Section {
                    stepperRow("Min weight", value: $draft.weightMinKg, unit: "kg", range: 20...300, step: 1)
                    stepperRow("Max weight", value: $draft.weightMaxKg, unit: "kg", range: 20...300, step: 1)
                } header: {
                    Text("Weight range (attribution)")
                } footer: {
                    Text("Readings whose weight falls in this range are attributed to this user. Keep it wide for a single-user setup.")
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

    private func stepperRow(_ title: String,
                            value: Binding<Double>,
                            unit: String,
                            range: ClosedRange<Double>,
                            step: Double) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue)) \(unit)").foregroundStyle(.secondary)
            }
        }
    }
}
