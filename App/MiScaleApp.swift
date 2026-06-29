import SwiftUI

@main
struct MiScaleApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(model)
                .onAppear {
                    // Dedicated always-on device: keep the screen awake so the
                    // foreground BLE scan never stops (plan §7 kiosk mitigation).
                    UIApplication.shared.isIdleTimerDisabled = true
                }
        }
    }
}
