import SwiftUI
import UIKit

@main
struct MiScaleApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .onAppear {
                    // Kiosk assumption: keep the always-on device awake.
                    UIApplication.shared.isIdleTimerDisabled = true
                    model.start()
                }
        }
    }
}
