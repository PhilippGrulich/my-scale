import SwiftUI
import MyOpenScaleCore

/// Lists past weigh-ins (from Apple Health) newest-first. The app's own entries
/// can be edited (tap or swipe) and deleted; entries from other apps show
/// their source and are read-only — HealthKit only lets us change our own.
struct MeasurementHistoryView: View {
    @EnvironmentObject var model: AppModel

    @State private var pendingDelete: WeightSample?
    @State private var editing: WeightSample?

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
                            Button { if sample.isFromThisApp { editing = sample } } label: {
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(sample.weightKg.formatted(1) + " kg")
                                            .font(.headline.monospacedDigit())
                                        // Entries from the Health app or other apps can't
                                        // be edited here — say where they came from.
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
                                    if sample.isFromThisApp {
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .leading) {
                                if sample.isFromThisApp {
                                    Button { editing = sample } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(Theme.accent)
                                }
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
            .sheet(item: $editing) { sample in
                EditMeasurementView(sample: sample, onDelete: {
                    // Let the edit sheet close before the confirmation shows.
                    Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        pendingDelete = sample
                    }
                })
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
