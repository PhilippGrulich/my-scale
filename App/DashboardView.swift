import SwiftUI
import MyOpenScaleCore

struct DashboardView: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedMetric: BodyMetric?
    @State private var showingBMI = false
    /// Height of the Mochi corner row (Mochi off: unused).
    @State private var mochiCornerHeight = MochiCornerView.size
    /// Tapping "To goal" / the chart header jumps to the Goal / History tab.
    var onShowGoal: () -> Void = {}
    var onShowHistory: () -> Void = {}
    /// Tapping the big weight opens the Weigh in tab.
    var onWeighIn: () -> Void = {}

    var body: some View {
        NavigationStack {
            weightPage
                .background(Theme.backgroundGradient.ignoresSafeArea())
                .onAppear {
                    model.dashboardVisible = true
                    // With no history yet, the load that is under way gives the first greeting.
                    if !model.weightHistory.isEmpty { model.refreshMochiHomeIfStale() }
                }
                .onDisappear { model.dashboardVisible = false }
                .toolbarVisibility(.hidden, for: .navigationBar)
                .navigationDestination(item: $selectedMetric) { metric in
                    BodyMetricDetailView(metric: metric)
                }
                .navigationDestination(isPresented: $showingBMI) {
                    BMIDetailView()
                }
        }
    }

    private var weightPage: some View {
        ScrollView {
            GlassEffectContainer(spacing: 16) {
                VStack(spacing: 16) {
                    ZStack(alignment: .topLeading) {
                        Button(action: onWeighIn) {
                            WeightHeroView(weightKg: model.currentWeightKg,
                                           measuredAt: model.weightHistory.max { $0.date < $1.date }?.date
                                               ?? model.lastOwnReading?.capturedAt)
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens Weigh in")
                            // The corner row (Mochi and its wrapped bubble) sits above the number.
                            .padding(.top, model.mochi.settings.enabled ? mochiCornerHeight + 4 : 0)
                            .animation(.snappy, value: mochiCornerHeight)
                        MochiHomeCorner(mochi: model.mochi,
                                        display: model.currentWeightKg?.formatted(1) ?? "– –",
                                        onTap: { model.refreshMochiHome() },
                                        onHeightChange: { mochiCornerHeight = $0 })
                    }
                    .padding(.top, 12)

                    TrendSummaryView(history: model.weightHistory,
                                     currentKg: model.currentWeightKg,
                                     goal: model.profile.weightGoal,
                                     onEditGoal: onShowGoal)

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
                                    goalKg: model.profile.goalWeightKg,
                                    onShowHistory: onShowHistory)

                    BodyMetricsGridView(onSelect: { selectedMetric = $0 },
                                        onSelectBMI: { showingBMI = true })

                    Text("Body-composition values are estimates, not medical advice.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)

                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Sections

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
