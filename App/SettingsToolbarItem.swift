import SwiftUI

/// Gear button at the top right of the Goal and Overview tabs; opens Settings
/// (profile, Apple Health, scale, Bluetooth).
struct SettingsToolbarItem: ToolbarContent {
    @EnvironmentObject var model: AppModel
    @State private var showing = false

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showing = true } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
            .sheet(isPresented: $showing) {
                ProfileEditorView()
                    .environmentObject(model)
                    .tint(Theme.accent)
            }
        }
    }
}
