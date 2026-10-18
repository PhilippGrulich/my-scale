import SwiftUI
import MyOpenScaleCore

/// Lists past weigh-ins (from Apple Health) newest-first and lets the user
/// delete them. Deleting removes the samples this app wrote from Apple Health.
struct MeasurementHistoryView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var pendingDelete: WeightSample?
    @State private var showingManualEntry = false

    private var samples: [WeightSample] {
        model.weightHistory.sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            Group {
                if samples.isEmpty {
                    ContentUnavailableView("No measurements yet",
                                           systemImage: "scalemass",
                                           description: Text("Weigh-ins from your scale, manual entries and Apple Health appear here."))
                } else {
                    List {
                        ForEach(samples) { sample in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sample.weightKg.formatted(1) + " kg")
                                        .font(.headline.monospacedDigit())
                                    // Entries from the Health app or other apps can't
                                    // be deleted here — say where they came from.
                                    if !sample.isFromThisApp, let source = sample.sourceName {
                                        Label(source, systemImage: "heart.text.square")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(sample.date, format: .dateTime.month().day().year().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .swipeActions(edge: .trailing) {
                                if sample.isFromThisApp {
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
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingManualEntry = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New measurement")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingManualEntry) {
                AddMeasurementView(startIn: model.hasPairedScale ? .scale : .manual)
                    .environmentObject(model)
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
