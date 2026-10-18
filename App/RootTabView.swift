import SwiftUI

/// System tab bar: Goal · Overview · "+" Weigh in (an action, not a page).
/// Settings (profile, Health, scale) live behind the gear at the top right.
/// Also owns the app-wide pieces (Add Measurement sheet, passive weigh-in
/// overlay, Health loading, foreground refresh) so they work on every tab.
struct RootTabView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    enum TabID: Hashable { case goal, overview, measure }
    @State private var selection: TabID = .overview
    @State private var showingAddMeasurement = false

    var body: some View {
        TabView(selection: $selection) {
            Tab("Goal", systemImage: "target", value: TabID.goal) {
                GoalPageView()
            }
            Tab("Overview", systemImage: "gauge.with.dots.needle.67percent", value: TabID.overview) {
                DashboardView(onShowGoal: { selection = .goal })
            }
            // Action tab: selecting it opens Add Measurement (see onChange below).
            Tab("Weigh in", systemImage: "plus.circle.fill", value: TabID.measure) {
                Color.clear
            }
        }
        .tint(Theme.accent)
        // The "+" tab is an action, not a destination: when it gets selected,
        // jump straight back to the previous tab and open the sheet.
        // (Refusing the selection in a custom Binding instead leaves TabView
        // thinking "+" is selected, so every second tap was ignored.)
        .onChange(of: selection) { previous, tab in
            guard tab == .measure else { return }
            selection = previous
            showingAddMeasurement = true
        }
        .tabBarMinimizeBehavior(.onScrollDown)
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

