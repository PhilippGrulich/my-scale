import SwiftUI

/// System tab bar: Goal · Overview · "+" Weigh in (center) · History · Settings.
/// Also owns the app-wide pieces (passive weigh-in overlay, Health loading,
/// foreground refresh) so they work on every tab.
struct RootTabView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    enum TabID: Hashable { case goal, overview, measure, history, settings }
    @State private var selection: TabID = .overview

    var body: some View {
        TabView(selection: tabSelection) {
            Tab("Goal", systemImage: "target", value: TabID.goal) {
                GoalPageView()
            }
            Tab("Overview", systemImage: "gauge.with.dots.needle.67percent", value: TabID.overview) {
                DashboardView(onShowGoal: { selection = .goal },
                              onShowHistory: { selection = .history })
            }
            Tab("Weigh in", systemImage: "plus.circle.fill", value: TabID.measure) {
                AddMeasurementView(onFinished: { selection = .overview })
            }
            Tab("History", systemImage: "list.bullet.rectangle", value: TabID.history) {
                MeasurementHistoryView()
            }
            Tab("Settings", systemImage: "gearshape", value: TabID.settings) {
                ProfileEditorView()
            }
        }
        .tint(Theme.accent)
        .tabBarMinimizeBehavior(.onScrollDown)
        // Control Center / Siri / Shortcuts "Start Weigh-In".
        .onChange(of: model.addMeasurementRequested, initial: true) { _, requested in
            guard requested else { return }
            model.addMeasurementRequested = false
            selection = .measure
        }
        // Passive weigh-ins (stepping on the scale with the app open) get the
        // full-screen overlay — except on the Weigh in tab, which shows them.
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
            #if DEBUG
            // `-startTab settings` on launch opens the Settings tab (simulator screenshots).
            if ["settings", "profile"].contains(UserDefaults.standard.string(forKey: "startTab")) { selection = .settings }
            #endif
            model.loadWeightHistory()
            model.requestNotificationAuthorization()
        }
    }

    /// Leaving the Weigh in tab ends its measurement/pairing scan in the same
    /// update, so the overlay never re-shows a reading on the next tab.
    private var tabSelection: Binding<TabID> {
        Binding(
            get: { selection },
            set: { tab in
                if selection == .measure, tab != .measure {
                    model.endPairingScan()
                    model.dismissOverlay()
                }
                selection = tab
            }
        )
    }

    private var overlayBinding: Binding<Bool> {
        Binding(
            get: { model.measurementPhase.isActive && selection != .measure },
            set: { if !$0 { model.dismissOverlay() } }
        )
    }
}

