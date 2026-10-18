import SwiftUI

@main
struct MyOpenScaleApp: App {
    @StateObject private var model = AppModel()
    @State private var showOnboarding = MyOpenScaleApp.needsOnboarding
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

    private static var needsOnboarding: Bool {
        #if DEBUG
        // `-onboardingStep <step>` on launch always shows onboarding (see `OnboardingView`).
        if UserDefaults.standard.string(forKey: "onboardingStep") != nil { return true }
        #endif
        return !OnboardingStore.isCompleted
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
