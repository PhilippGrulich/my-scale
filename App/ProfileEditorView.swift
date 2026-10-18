import SwiftUI
import MyOpenScaleCore

/// Profile tab: edits the single HealthKit owner profile in place. Changes are
/// kept as a draft until Save (shown only when something changed), so a
/// half-edited stepper never reaches Health. Full profile CRUD is M5b.
struct ProfileEditorView: View {
    @EnvironmentObject var model: AppModel
    @State private var draft = StoredProfile.makeDefault()
    @State private var confirmingUnpair = false

    private var hasChanges: Bool { draft != model.profile }

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

                Section("Settings") {
                    SyncBadgeView(auth: model.healthAuth,
                                  lastStatus: model.lastOwnReading?.healthKitStatus,
                                  lastError: model.lastSyncError,
                                  onAuthorize: { model.requestHealthAuthorization() },
                                  inline: true)
                    HStack {
                        Label("Scale", systemImage: "scalemass")
                        Spacer()
                        if model.hasPairedScale {
                            Button("Unpair", role: .destructive) { confirmingUnpair = true }
                                .font(.subheadline)
                        } else {
                            Text("Not paired")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .confirmationDialog("Unpair this scale?", isPresented: $confirmingUnpair,
                                        titleVisibility: .visible) {
                        Button("Unpair", role: .destructive) { model.unpairScale() }
                    } message: {
                        Text("You can pair it again from New measurement.")
                    }
                    HStack {
                        Label("Bluetooth", systemImage: "dot.radiowaves.left.and.right")
                        Spacer()
                        Text(model.bleStatus.label)
                            .font(.subheadline)
                            .foregroundStyle(model.bleStatus == .scanning ? Theme.accent : .secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }

                #if DEBUG
                developerSection
                #endif

                Section {
                    Label("Your weigh-ins are recognised automatically from your weight and body-composition signature — no weight range to configure.",
                          systemImage: "person.fill.checkmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                if hasChanges {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Revert") { draft = model.profile }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { model.saveConfirmedProfile(draft) }
                            .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .onAppear { draft = model.profile }
            .onChange(of: model.profile) { _, saved in draft = saved }
        }
    }

    #if DEBUG
    private var developerSection: some View {
        Section("Developer") {
            Button {
                model.simulateWeighIn()
            } label: {
                Label("Simulate weigh-in", systemImage: "wand.and.stars")
            }

            Button(role: .destructive) {
                model.unpairScale()
                model.resetAttribution()
                OnboardingStore.reset()
            } label: {
                Label("Reset onboarding, scale & learned profile", systemImage: "arrow.counterclockwise")
            }

            if !model.recentFrames.isEmpty {
                Text("Live frames (\(model.recentFrames.count))")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(model.recentFrames.prefix(10)) { frame in
                    FrameRow(frame: frame)
                }
            }
        }
    }
    #endif
}
