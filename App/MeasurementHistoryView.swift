import SwiftUI
import MyOpenScaleCore

/// Lists past weigh-ins (from Apple Health) newest-first and lets the user
/// delete them. Deleting removes the samples this app wrote from Apple Health.
struct MeasurementHistoryView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var pendingDelete: WeightSample?

    private var samples: [WeightSample] {
        model.weightHistory.sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            Group {
                if samples.isEmpty {
                    ContentUnavailableView("No measurements yet",
                                           systemImage: "scalemass",
                                           description: Text("Weigh-ins you take will appear here."))
                } else {
                    List {
                        ForEach(samples) { sample in
                            HStack(alignment: .firstTextBaseline) {
                                Text(sample.weightKg.formatted(1) + " kg")
                                    .font(.headline.monospacedDigit())
                                Spacer()
                                Text(sample.date, format: .dateTime.month().day().year().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    pendingDelete = sample
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Delete this weigh-in?",
                                isPresented: deleteDialogBinding,
                                titleVisibility: .visible,
                                presenting: pendingDelete) { sample in
                Button("Delete from Apple Health", role: .destructive) {
                    model.deleteMeasurement(sample)
                }
            } message: { sample in
                Text("\(sample.weightKg.formatted(1)) kg on \(sample.date.formatted(date: .abbreviated, time: .shortened)) will be removed from Apple Health.")
            }
        }
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } })
    }
}
