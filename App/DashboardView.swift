import SwiftUI
import MyOpenScaleCore

struct DashboardView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingProfile = false
    @State private var showingHistory = false
    @State private var selectedMetric: HealthKitSink.MetricKind?
    #if DEBUG
    @State private var showingDeveloper = false
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                GlassEffectContainer(spacing: 16) {
                    VStack(spacing: 16) {
                        WeightHeroView(weightKg: model.currentWeightKg,
                                       trendDeltaKg: model.trendDeltaKg)
                            .padding(.top, 8)

                        TrendSummaryView(history: model.weightHistory,
                                         currentKg: model.currentWeightKg,
                                         goalKg: model.profile.goalWeightKg)

                        Button {
                            model.startMeasurement()
                        } label: {
                            Label("Start new measurement", systemImage: "scalemass")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .controlSize(.large)
                        .clipShape(.capsule)

                        // Discoverable when there's no data yet (e.g. App Review
                        // without the physical scale); hides once you have readings.
                        if model.weightHistory.isEmpty && model.readings.isEmpty {
                            Button { model.showSampleReading() } label: {
                                Label("See a sample reading", systemImage: "eye")
                                    .font(.subheadline.weight(.medium))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                            .tint(.secondary)
                        }

                        reviewSection

                        WeightChartView(history: model.weightHistory,
                                        goalKg: model.profile.goalWeightKg)

                        metricCards

                        SyncBadgeView(auth: model.healthAuth,
                                      lastStatus: model.lastOwnReading?.healthKitStatus,
                                      lastError: model.lastSyncError,
                                      onAuthorize: { model.requestHealthAuthorization() })
                            .frame(maxWidth: .infinity)

                        bluetoothHint

                        Text("Body-composition values are estimates, not medical advice.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)

                        #if DEBUG
                        developerSection
                        #endif
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("MyOpenScale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingHistory = true } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("Measurement history")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingProfile = true } label: {
                        Image(systemName: "person.crop.circle")
                    }
                }
            }
            .sheet(isPresented: $showingProfile) {
                ProfileEditorView(profile: model.profile) { model.saveConfirmedProfile($0) }
            }
            .sheet(isPresented: $showingHistory) {
                MeasurementHistoryView().environmentObject(model)
            }
            .sheet(item: $selectedMetric) { kind in
                MetricDetailView(kind: kind).environmentObject(model)
            }
            .fullScreenCover(isPresented: overlayBinding) {
                WeighInOverlayView(phase: model.measurementPhase,
                                   startedAt: model.liveStartedAt,
                                   bleStatus: model.bleStatus,
                                   onAccept: { model.acceptCurrentLiveWeight() },
                                   onDismiss: { model.dismissOverlay() })
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { model.onForeground() }
            }
            .task {
                model.loadWeightHistory()
                model.requestNotificationAuthorization()
            }
        }
    }

    // MARK: - Sections

    private var metricCards: some View {
        let c = model.latestComposition
        return HStack(spacing: 12) {
            metricCard(.bodyFat, value: c?.bodyFatPercent, unit: "%", image: "drop.fill", tint: .orange)
            metricCard(.lean, value: c?.leanMassKg, unit: "kg", image: "figure.arms.open", tint: Theme.accentSecondary)
            metricCard(.bmi, value: c?.bmi, unit: "", image: "ruler.fill", tint: Theme.accent)
        }
    }

    private func metricCard(_ kind: HealthKitSink.MetricKind, value: Double?,
                            unit: String, image: String, tint: Color) -> some View {
        Button { selectedMetric = kind } label: {
            MetricCardView(title: kind.title, systemImage: image, value: value, unit: unit, tint: tint)
        }
        .buttonStyle(.plain)
    }

    /// Held weigh-ins that didn't clearly match the owner — one-tap confirm.
    @ViewBuilder
    private var reviewSection: some View {
        if !model.pendingConfirmations.isEmpty {
            VStack(spacing: 12) {
                ForEach(model.pendingConfirmations) { r in
                    VStack(spacing: 10) {
                        Label("Was this you?", systemImage: "questionmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(Theme.accent)
                        Text("\(r.weightKg.formatted(1)) kg · \(r.capturedAt, format: .dateTime.month().day().hour().minute())")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button {
                                model.rejectReading(r.id)
                            } label: {
                                Label("Not me", systemImage: "xmark")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                            .tint(.secondary)

                            Button {
                                model.confirmReading(r.id)
                            } label: {
                                Label("This was me", systemImage: "checkmark")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accent)
                        }
                    }
                    .padding(16)
                    .glassEffect(in: .rect(cornerRadius: 22))
                }
            }
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

    #if DEBUG
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

                Button(role: .destructive) {
                    model.unpairScale()
                    model.resetAttribution()
                    OnboardingStore.reset()
                } label: {
                    Label("Reset onboarding, scale & learned profile", systemImage: "arrow.counterclockwise")
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
    #endif

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
