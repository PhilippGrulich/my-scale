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
                               mochiEnabled: model.mochi.settings.enabled,
                               presentation: model.weighInPresentation,
                               onAccept: { model.acceptCurrentLiveWeight() },
                               onDismiss: { model.dismissOverlay() })
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.onForeground() }
        }
        .task {
            #if DEBUG
            // `-startTab settings|measure` on launch opens that tab (simulator screenshots).
            switch UserDefaults.standard.string(forKey: "startTab") {
            case "settings", "profile": selection = .settings
            case "measure": selection = .measure
            default: break
            }
            #endif
            model.loadWeightHistory()
            #if DEBUG
            // `-simulateWeighIn YES` on launch: arm a weigh-in, then simulate one a few
            // seconds later (waiting → measuring → result, for simulator screenshots).
            // Skips the notification prompt so it doesn't cover the overlay.
            if UserDefaults.standard.bool(forKey: "simulateWeighIn") {
                model.startMeasurement()
                try? await Task.sleep(for: .seconds(4))
                model.simulateWeighIn()
                return
            }
            // `-skipNotificationPrompt YES`: no permission alert (it makes the app inactive,
            // which holds back Mochi's home content), for simulator screenshots.
            if UserDefaults.standard.bool(forKey: "skipNotificationPrompt") { return }
            #endif
            // Needed for weigh-in-saved alerts; a no-op if onboarding's reminders step already asked.
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

