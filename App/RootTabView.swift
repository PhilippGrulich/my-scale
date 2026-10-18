import SwiftUI

/// Bottom tab bar: overview · "+" weigh-in action (center) · profile. Owns the
/// app-wide pieces (weigh-in overlay, Health loading, foreground refresh) so a
/// measurement started from Control Center / Siri shows no matter which tab is
/// open.
struct RootTabView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    enum TabID: Hashable { case overview, measure, profile }
    @State private var selection: TabID = .overview

    /// The "+" tab is an action, not a destination: selecting it starts a
    /// measurement and leaves the current tab selected.
    private var tabSelection: Binding<TabID> {
        Binding(
            get: { selection },
            set: { tab in
                if tab == .measure {
                    model.startMeasurement()
                } else {
                    selection = tab
                }
            }
        )
    }

    var body: some View {
        TabView(selection: tabSelection) {
            Tab("Overview", systemImage: "gauge.with.dots.needle.67percent", value: TabID.overview) {
                DashboardView()
            }
            // Action tab: selecting it starts a weigh-in (see `tabSelection`).
            Tab("Weigh in", systemImage: "plus.circle.fill", value: TabID.measure) {
                Color.clear
            }
            Tab("Profile", systemImage: "person.crop.circle", value: TabID.profile) {
                ProfileEditorView()
            }
        }
        .tint(Theme.accent)
        .tabBarMinimizeBehavior(.onScrollDown)
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

    private var overlayBinding: Binding<Bool> {
        Binding(
            get: { model.measurementPhase.isActive },
            set: { if !$0 { model.dismissOverlay() } }
        )
    }
}
