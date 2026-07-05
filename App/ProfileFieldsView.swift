import SwiftUI
import MyOpenScaleCore

/// The shared identity + body `Form` sections (name, DOB, sex, height) used by
/// both `ProfileEditorView` and the onboarding "Confirm your details" step, so
/// the two never drift. Weight-range config is editor-only and lives there.
struct ProfileFieldsView: View {
    @Binding var draft: StoredProfile

    var body: some View {
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
            Stepper(value: $draft.heightCm, in: 100...230, step: 1) {
                HStack {
                    Text("Height")
                    Spacer()
                    Text("\(Int(draft.heightCm)) cm").foregroundStyle(.secondary)
                }
            }
        }
    }
}
