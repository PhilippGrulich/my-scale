import WidgetKit
import SwiftUI
import AppIntents

/// Widget-extension bundle hosting the Control Center control(s). Lives in its
/// own process; shares only `StartMeasurementIntent` / `MeasurementHandoff` with
/// the app (via the Shared sources + App Group).
@main
struct MyOpenScaleControlsBundle: WidgetBundle {
    var body: some Widget {
        StartWeighInControl()    // Control Center / Lock Screen "weigh in" button
        MyOpenScaleWidget()          // Home / Lock Screen latest-weight widget
        ProgressWidget()             // Home Screen multi-value progress widget
    }
}

/// A Control Center button (also addable to the Lock Screen / Action Button)
/// that starts a new weigh-in. Tapping runs `StartMeasurementIntent`, which
/// opens the app and arms the measurement.
struct StartWeighInControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.philippgrulich.myopenscale.controls.startWeighIn") {
            ControlWidgetButton(action: StartMeasurementIntent()) {
                Label("Weigh In", systemImage: "scalemass")
            }
        }
        .displayName("Start Weigh-In")
        .description("Start a new weight measurement in Mochi.")
    }
}
