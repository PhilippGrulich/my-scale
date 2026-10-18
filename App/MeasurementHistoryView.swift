import SwiftUI
import HealthKit
import MyOpenScaleCore

/// History tab as a day-by-day activity feed: one compact card per day with its
/// weigh-ins and — when Apple Health has them — workouts, steps / active
/// energy and eaten energy. Days without any data don't appear. The app's own
/// weigh-ins can be edited (tap or swipe) and deleted; others are read-only
/// and show their source (HealthKit only lets us change our own samples).
struct MeasurementHistoryView: View {
    @EnvironmentObject var model: AppModel

    @State private var pendingDelete: WeightSample?
    @State private var editing: WeightSample?

    var body: some View {
        NavigationStack {
            Group {
                let feed = model.activityFeed
                if feed.isEmpty {
                    ContentUnavailableView("No measurements yet",
                                           systemImage: "scalemass",
                                           description: Text("Weigh-ins from your scale, manual entries and Apple Health appear here."))
                } else {
                    List {
                        ForEach(Array(feed.enumerated()), id: \.element.id) { index, day in
                            Section {
                                ForEach(day.weighIns) { weighInRow($0) }
                                ForEach(day.workouts) { workoutRow($0) }
                                if let t = day.totals, t.steps != nil || t.activeKcal != nil {
                                    activityRow(t)
                                }
                                if let eaten = day.totals?.eatenKcal {
                                    nutritionRow(eaten)
                                }
                            } header: {
                                dayHeader(day, previous: previousWeight(after: index, in: feed))
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(.compact)
                    .environment(\.defaultMinListRowHeight, 44)
                    .refreshable {
                        model.loadWeightHistory()
                        model.loadActivity()
                    }
                }
            }
            // Standard grouped grey (like Settings) so the white day cards stand out.
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("History")
            .task { model.loadActivity() }
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

    // MARK: - Day header

    private func dayHeader(_ day: AppModel.ActivityDay, previous: Double?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(dayTitle(day.day))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .textCase(nil)
            Spacer()
            if let latest = day.weighIns.first?.weightKg, let previous {
                let delta = latest - previous
                Text(verbatim: "\(abs(delta) < 0.05 ? "±" + 0.0.formatted(1) : delta.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()))) kg")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return String(localized: "Today") }
        if cal.isDateInYesterday(day) { return String(localized: "Yesterday") }
        let sameYear = cal.isDate(day, equalTo: Date(), toGranularity: .year)
        return day.formatted(sameYear ? .dateTime.weekday(.wide).day().month(.wide)
                                      : .dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
    }

    /// Latest weight on the closest earlier day that has one.
    private func previousWeight(after index: Int, in feed: [AppModel.ActivityDay]) -> Double? {
        feed.dropFirst(index + 1).first { !$0.weighIns.isEmpty }?.weighIns.first?.weightKg
    }

    // MARK: - Rows

    private func weighInRow(_ sample: WeightSample) -> some View {
        let fat = sample.impedanceOhms.map {
            BodyMetricsCalculator.compute(weightKg: sample.weightKg, impedanceOhms: Double($0),
                                          profile: BodyProfile(from: model.profile.coreProfile, at: sample.date)).bodyFatPercent
        }
        let detail: String = {
            if !sample.isFromThisApp, let source = sample.sourceName { return source }
            return sample.impedanceOhms != nil ? String(localized: "Scale") : String(localized: "Manual entry")
        }()
        return Button { if sample.isFromThisApp { editing = sample } } label: {
            row(icon: "scalemass.fill", tint: Theme.accent,
                title: Text("\(sample.weightKg.formatted(1)) kg").font(.headline.monospacedDigit()),
                subtitle: "\(sample.date.formatted(date: .omitted, time: .shortened)) · \(detail)",
                trailing: fat.map { Text("\($0.formatted(1)) % fat") },
                chevron: sample.isFromThisApp)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading) {
            if sample.isFromThisApp {
                Button { editing = sample } label: { Label("Edit", systemImage: "pencil") }
                    .tint(Theme.accent)
            }
        }
        .swipeActions(edge: .trailing) {
            if sample.isFromThisApp {
                Button(role: .destructive) { pendingDelete = sample } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func workoutRow(_ w: HealthKitSink.WorkoutEntry) -> some View {
        let minutes = Int((w.duration / 60).rounded())
        return row(icon: w.activityType.systemImage, tint: .green,
                   title: Text(w.activityType.title).font(.subheadline.weight(.semibold)),
                   subtitle: "\(w.start.formatted(date: .omitted, time: .shortened)) · \(String(localized: "\(minutes) min")) · \(w.sourceName)",
                   trailing: w.activeKcal.map { Text("\(Int($0.rounded())) kcal") },
                   chevron: false)
    }

    private func activityRow(_ t: HealthKitSink.DailyTotals) -> some View {
        row(icon: "figure.walk", tint: .orange,
            title: Group {
                if let steps = t.steps {
                    Text("\(Int(steps).formatted()) steps")
                } else {
                    Text("Activity")
                }
            }.font(.subheadline.weight(.semibold)),
            subtitle: nil,
            trailing: t.activeKcal.map { Text("\(Int($0.rounded()).formatted()) kcal active") },
            chevron: false)
    }

    private func nutritionRow(_ kcal: Double) -> some View {
        row(icon: "fork.knife", tint: .pink,
            title: Text("Eaten").font(.subheadline.weight(.semibold)),
            subtitle: nil,
            trailing: Text("\(Int(kcal.rounded()).formatted()) kcal"),
            chevron: false)
    }

    private func row<Title: View>(icon: String, tint: Color, title: Title, subtitle: String?,
                                  trailing: Text?, chevron: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                title
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let trailing {
                trailing
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var deleteDialogBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } })
    }
}
