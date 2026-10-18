import SwiftUI
import MyOpenScaleCore

/// Watch-side fallback for body details HealthKit didn't provide. Height is
/// required (it gates every downstream metric); sex + age are optional and only
/// improve the body-fat / lean estimate (without them a weigh-in still records
/// weight + BMI). Prefilled from whatever HealthKit already synced.
struct WatchSetupView: View {
    @EnvironmentObject var model: WatchAppModel
    @Environment(\.dismiss) private var dismiss

    @State private var heightCm: Double
    @State private var age: Int
    @State private var sexChoice: SexChoice

    enum SexChoice: Hashable { case male, female, unspecified }

    init() {
        // Placeholders; real values are applied from the model in `.onAppear`
        // (the environment object isn't available in init).
        _heightCm = State(initialValue: 170)
        _age = State(initialValue: 30)
        _sexChoice = State(initialValue: .male)
    }

    var body: some View {
        Form {
            if model.mochiEnabled {
                WatchMochiRow(presentation: MochiPresentation(
                    pose: .helloWave, text: String(localized: "Tell me a bit about you 💚"), display: ""))
                    .listRowBackground(Color.clear)
            }
            Section("Height") {
                Stepper(value: $heightCm, in: 120...220, step: 1) {
                    Text("\(Int(heightCm)) cm")
                }
            }
            Section("Biological sex") {
                Picker("Sex", selection: $sexChoice) {
                    Text("Male").tag(SexChoice.male)
                    Text("Female").tag(SexChoice.female)
                    Text("Prefer not to say").tag(SexChoice.unspecified)
                }
                .pickerStyle(.navigationLink)
            }
            Section("Age") {
                Stepper(value: $age, in: 13...100, step: 1) {
                    Text("\(age) years")
                }
            }
            Section {
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
        }
        .navigationTitle("Your Details")
        .onAppear(perform: applyExisting)
    }

    private func applyExisting() {
        let p = model.profile
        if let h = p.heightCm, h > 0 { heightCm = h }
        if let dob = p.dateOfBirth {
            age = max(13, min(100, DateMath.ageYears(dateOfBirth: dob, at: Date())))
        }
        switch p.sex {
        case .male: sexChoice = .male
        case .female: sexChoice = .female
        case .none: sexChoice = .unspecified
        }
    }

    private func save() {
        var updated = model.profile
        updated.heightCm = heightCm
        switch sexChoice {
        case .male: updated.sex = .male
        case .female: updated.sex = .female
        case .unspecified: updated.sex = nil
        }
        // Store an approximate DOB from the entered age (Jan 1, age years ago).
        let calendar = Calendar(identifier: .gregorian)
        updated.dateOfBirth = calendar.date(byAdding: .year, value: -age, to: Date())
        model.updateProfile(updated)
        dismiss()
    }
}
