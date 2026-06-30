import SwiftUI
import MiScaleCore

struct DashboardView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingProfile = false
    @State private var showingDeveloper = false

    var body: some View {
        NavigationStack {
            ScrollView {
                GlassEffectContainer(spacing: 16) {
                    VStack(spacing: 16) {
                        WeightHeroView(weightKg: model.currentWeightKg,
                                       trendDeltaKg: model.trendDeltaKg)
                            .padding(.top, 8)

                        WeightChartView(history: model.weightHistory)

                        metricCards

                        SyncBadgeView(auth: model.healthAuth,
                                      lastStatus: model.readings.first?.healthKitStatus,
                                      lastError: model.lastSyncError,
                                      onAuthorize: { model.requestHealthAuthorization() })
                            .frame(maxWidth: .infinity)

                        bluetoothHint

                        developerSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("MiScale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingProfile = true } label: {
                        Image(systemName: "person.crop.circle")
                    }
                }
            }
            .sheet(isPresented: $showingProfile) {
                ProfileEditorView(profile: model.profile) { model.saveProfile($0) }
            }
            .fullScreenCover(isPresented: overlayBinding) {
                WeighInOverlayView(phase: model.measurementPhase,
                                   startedAt: model.liveStartedAt,
                                   onAccept: { model.acceptCurrentLiveWeight() },
                                   onDismiss: { model.dismissOverlay() })
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { model.onForeground() }
            }
            .task { model.loadWeightHistory() }
        }
    }

    // MARK: - Sections

    private var metricCards: some View {
        let c = model.latestComposition
        return HStack(spacing: 12) {
            MetricCardView(title: "Body Fat", systemImage: "drop.fill",
                           value: c?.bodyFatPercent, unit: "%", tint: .orange)
            MetricCardView(title: "Lean Mass", systemImage: "figure.arms.open",
                           value: c?.leanMassKg, unit: "kg", tint: Theme.accentSecondary)
            MetricCardView(title: "BMI", systemImage: "ruler.fill",
                           value: c?.bmi, unit: "", tint: Theme.accent)
        }
    }

    @ViewBuilder
    private var bluetoothHint: some View {
        if model.bleStatus != .scanning {
            Label(model.bleStatus.label, systemImage: "dot.radiowaves.left.and.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(in: .capsule)
                .frame(maxWidth: .infinity)
        }
    }

    private var developerSection: some View {
        DisclosureGroup(isExpanded: $showingDeveloper) {
            VStack(spacing: 10) {
                Button {
                    model.simulateWeighIn()
                } label: {
                    Label("Simulate weigh-in", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)

                if !model.recentFrames.isEmpty {
                    Text("Live frames (\(model.recentFrames.count))")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(model.recentFrames.prefix(10)) { frame in
                        FrameRow(frame: frame)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Label("Developer", systemImage: "wrench.and.screwdriver")
                .font(.subheadline.weight(.medium))
        }
        .padding(16)
        .glassEffect(in: .rect(cornerRadius: 22))
    }

    // MARK: - Overlay presentation

    private var overlayBinding: Binding<Bool> {
        Binding(
            get: { model.measurementPhase.isActive },
            set: { if !$0 { model.dismissOverlay() } }
        )
    }
}

// MARK: - Developer frame row (raw BLE advert)

struct FrameRow: View {
    let frame: ObservedFrame

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(String(format: "%.2f kg", frame.parsed.weightKg))
                    .font(.subheadline.monospaced())
                Spacer()
                Text("\(frame.rssi) dBm").font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                flag("stable", frame.parsed.isStabilized)
                flag("imp", frame.parsed.hasImpedance)
                flag("off", frame.parsed.isWeightRemoved)
                if frame.parsed.impedanceOhms > 0 {
                    Text("\(frame.parsed.impedanceOhms)Ω").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(frame.rawHex).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
        }
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func flag(_ label: String, _ on: Bool) -> some View {
        Text(label)
            .font(.caption2)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(on ? Color.green.opacity(0.25) : Color.gray.opacity(0.15))
            .foregroundStyle(on ? .green : .secondary)
            .clipShape(Capsule())
    }
}
