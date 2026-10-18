import SwiftUI

@main
struct MyOpenScaleApp: App {
    @StateObject private var model = AppModel()
    @State private var showOnboarding = !OnboardingStore.isCompleted
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                // `-mochiGallery YES` on launch shows only the Mochi pose gallery (simulator screenshots).
                if UserDefaults.standard.bool(forKey: "mochiGallery") {
                    NavigationStack { MochiPoseGalleryView() }
                } else {
                    appContent
                }
                #else
                appContent
                #endif
            }
            .environmentObject(model)
            .onChange(of: scenePhase, initial: true) { _, phase in
                // A "Start Weigh-In" from Control Center / Siri / Spotlight /
                // Shortcuts sets a shared flag and opens the app; arm the
                // measurement once we're active and past onboarding.
                guard phase == .active, !showOnboarding else { return }
                if MeasurementHandoff.consumePending() { model.addMeasurementRequested = true }
            }
        }
    }

    @ViewBuilder private var appContent: some View {
        if showOnboarding {
            OnboardingView(onFinish: {
                OnboardingStore.markCompleted()
                model.endPairingScan()
                showOnboarding = false
            })
        } else {
            RootTabView()
        }
    }
}
