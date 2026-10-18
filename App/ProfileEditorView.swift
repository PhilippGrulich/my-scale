import SwiftUI
import MyOpenScaleCore

/// Settings tab: the single HealthKit owner profile plus
/// Health / scale / Bluetooth settings. Profile changes are kept as a draft
/// until Save, so a half-edited stepper never reaches Health. Full profile
/// CRUD is M5b.
struct ProfileEditorView: View {
    @EnvironmentObject var model: AppModel
    @State private var draft = StoredProfile.makeDefault()
    @State private var confirmingUnpair = false

    private var hasChanges: Bool { draft != model.profile }

    var body: some View {
        NavigationStack {
            Form {
                ProfileFieldsView(draft: $draft)

                GoalFieldsView(draft: $draft, currentWeightKg: model.currentWeightKg)

                MochiSettingsSection(mochi: model.mochi)

                Section("Connections") {
                    SyncBadgeView(auth: model.healthAuth,
                                  lastStatus: model.lastOwnReading?.healthKitStatus,
                                  lastError: model.lastSyncError,
                                  onAuthorize: { model.requestHealthAuthorization() },
                                  inline: true)
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Scale")
                                if !model.hasPairedScale {
                                    Text("Works with Xiaomi Mi Body Composition Scale 2")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "scalemass")
                        }
                        Spacer()
                        if model.hasPairedScale {
                            Button("Unpair", role: .destructive) { confirmingUnpair = true }
                                .font(.subheadline)
                        } else {
                            Button("Pair scale") { model.requestPairing() }
                                .font(.subheadline.weight(.semibold))
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.accent)
                        }
                    }
                    .confirmationDialog("Unpair this scale?", isPresented: $confirmingUnpair,
                                        titleVisibility: .visible) {
                        Button("Unpair", role: .destructive) { model.unpairScale() }
                    } message: {
                        Text("You can pair it again from the Weigh in tab.")
                    }
                    // Bluetooth only runs for a paired scale, so there's nothing to show without one.
                    if model.hasPairedScale {
                        HStack {
                            Label("Bluetooth", systemImage: "dot.radiowaves.left.and.right")
                            Spacer()
                            Text(model.bleStatus.label)
                                .font(.subheadline)
                                .foregroundStyle(model.bleStatus == .scanning ? Theme.accent : .secondary)
                                .multilineTextAlignment(.trailing)
                        }
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
            .navigationTitle("Settings")
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
            NavigationLink {
                MochiPoseGalleryView()
            } label: {
                Label("Mochi poses", systemImage: "face.smiling")
            }

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
