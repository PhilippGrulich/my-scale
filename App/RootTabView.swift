import SwiftUI

/// App shell: two pages you can swipe between (Goal ⟷ Overview) and one
/// Liquid Glass bar at the bottom — Goal · Overview · Weigh in. The system
/// tab bar can't swipe between tabs, hence a paged `TabView` plus our own bar.
/// Settings (profile, Health, scale) live behind the gear at the top right.
/// Also owns the app-wide pieces (Add Measurement sheet, passive weigh-in
/// overlay, Health loading, foreground refresh).
struct RootTabView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    enum Page: Hashable { case goal, overview }
    @State private var page: Page = .overview
    @State private var showingAddMeasurement = false

    var body: some View {
        TabView(selection: $page) {
            GoalPageView().tag(Page.goal)
            DashboardView(onShowGoal: { withAnimation(.snappy) { page = .goal } })
                .tag(Page.overview)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Theme.backgroundGradient.ignoresSafeArea())
        // Pages scroll under the floating bar but can always scroll clear of it.
        .contentMargins(.bottom, 84, for: .scrollContent)
        .overlay(alignment: .bottom) {
            BottomBar(page: $page) { showingAddMeasurement = true }
        }
        .sheet(isPresented: addMeasurementBinding) {
            AddMeasurementView(startIn: model.hasPairedScale ? .scale : .manual)
                .environmentObject(model)
        }
        // Control Center / Siri / Shortcuts "Start Weigh-In".
        .onChange(of: model.addMeasurementRequested, initial: true) { _, requested in
            guard requested else { return }
            model.addMeasurementRequested = false
            showingAddMeasurement = true
        }
        // Passive weigh-ins (stepping on the scale with the app open) still get
        // the full-screen overlay — unless the sheet is already showing them.
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

    /// Closing the sheet (Done, Cancel, swipe-down) ends its measurement in the
    /// same update, so the overlay below never re-shows the reading the sheet
    /// was already displaying.
    private var addMeasurementBinding: Binding<Bool> {
        Binding(
            get: { showingAddMeasurement },
            set: { presented in
                if !presented {
                    model.endPairingScan()
                    model.dismissOverlay()
                }
                showingAddMeasurement = presented
            }
        )
    }

    private var overlayBinding: Binding<Bool> {
        Binding(
            get: { model.measurementPhase.isActive && !showingAddMeasurement },
            set: { if !$0 { model.dismissOverlay() } }
        )
    }
}

/// Floating glass bar: two page buttons (the selected one gets a glass pill
/// that slides between them) and the prominent Weigh in action.
private struct BottomBar: View {
    @Binding var page: RootTabView.Page
    let onWeighIn: () -> Void
    @Namespace private var pill

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    item(.goal, title: "Goal", icon: "target")
                    item(.overview, title: "Overview", icon: "gauge.with.dots.needle.67percent")
                }
                .padding(4)
                .glassEffect(in: .capsule)

                Button(action: onWeighIn) {
                    VStack(spacing: 2) {
                        Image(systemName: "plus")
                            .font(.title3.weight(.bold))
                        Text("Weigh in")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 56)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(Theme.accent).interactive(), in: .capsule)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }

    private func item(_ target: RootTabView.Page, title: LocalizedStringKey, icon: String) -> some View {
        let selected = page == target
        return Button {
            withAnimation(.snappy) { page = target }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(selected ? Theme.accent : .primary)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background {
                if selected {
                    Capsule()
                        .fill(Theme.accent.opacity(0.14))
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
