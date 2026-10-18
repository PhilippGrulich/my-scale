import SwiftUI
import MyOpenScaleCore

/// Correct a weigh-in this app saved (a mis-read, a heavy jacket, the wrong
/// time). Saving replaces the Apple Health samples; body fat keeps its
/// percentage, lean mass and BMI follow the new weight.
struct EditMeasurementView: View {
    let sample: WeightSample
    var onDelete: () -> Void

    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var weightKg: Double
    @State private var date: Date
    @State private var saving = false
    @State private var error: String?

    private static let weightRange = 20.0...300.0

    init(sample: WeightSample, onDelete: @escaping () -> Void) {
        self.sample = sample
        self.onDelete = onDelete
        _weightKg = State(initialValue: (sample.weightKg * 10).rounded() / 10)
        _date = State(initialValue: sample.date)
    }

    private var changed: Bool {
        abs(weightKg - sample.weightKg) >= 0.05 || abs(date.timeIntervalSince(sample.date)) >= 60
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Weight")
                        Spacer()
                        TextField("Weight", value: $weightKg,
                                  format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.title3.weight(.semibold).monospacedDigit())
                            .frame(maxWidth: 110)
                        Text("kg").foregroundStyle(.secondary)
                        Stepper("Weight", value: $weightKg, in: Self.weightRange, step: 0.1)
                            .labelsHidden()
                    }
                    DatePicker("Date", selection: $date, in: ...Date())
                } footer: {
                    Text("Updates the entry in Apple Health. Body fat keeps its percentage; lean mass and BMI are recalculated for the new weight.")
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    Button("Delete from Apple Health", role: .destructive) {
                        dismiss()
                        onDelete()
                    }
                }
            }
            .navigationTitle("Edit weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!changed || !Self.weightRange.contains(weightKg) || saving)
                }
            }
        }
        .tint(Theme.accent)
    }

    private func save() {
        saving = true
        error = nil
        model.editMeasurement(sample, weightKg: weightKg, date: date) { result in
            saving = false
            switch result {
            case .success: dismiss()
            case .failure(let e): error = HealthKitSink.userMessage(for: e)
            }
        }
    }
}
