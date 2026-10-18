import SwiftUI

@main
struct MyOpenScaleApp: App {
    @StateObject private var model = AppModel()
    @State private var showOnboarding = !OnboardingStore.isCompleted
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if showOnboarding {
                    OnboardingView(onFinish: {
                        OnboardingStore.markCompleted()
                        model.endOnboardingScan()
                        showOnboarding = false
                    })
                } else {
                    RootTabView()
                }
            }
            .environmentObject(model)
            .onChange(of: scenePhase, initial: true) { _, phase in
                // A "Start Weigh-In" from Control Center / Siri / Spotlight /
                // Shortcuts sets a shared flag and opens the app; arm the
                // measurement once we're active and past onboarding.
                guard phase == .active, !showOnboarding else { return }
                if MeasurementHandoff.consumePending() { model.startMeasurement() }
            }
        }
    }
}
