# MyOpenScaleControls — Control Center control + widget

WidgetKit extension (target `MyOpenScaleControls` in `project.yml`, embedded in
the app, bundle id `com.philippgrulich.myopenscale.app.controls`). It shares the
App Group `group.com.philippgrulich.myopenscale` with the app.

## Control Center control — "Start Weigh-In"

`MyOpenScaleControlsBundle.swift` → `StartWeighInControl`. Also available on the
Lock Screen and the Action Button. It runs `StartMeasurementIntent` (in
`Shared/`), which sets a timestamped flag in `MeasurementHandoff` and opens the
app. On activation the app consumes the flag and selects the **Weigh in** tab:
live weigh-in if a scale is paired, otherwise manual entry. The same intent backs
Siri, Spotlight and the Shortcuts app (`App/MyOpenScaleShortcuts.swift`).

## Weight widget

`MyOpenScaleWidget.swift`. Sizes:

| Size | Shows |
|---|---|
| Small | weight, 30-day trend, when it was measured |
| Medium | the same, plus a chart |
| Large | the same, plus a chart with axes and the goal line |
| Lock Screen rectangular | weight + 30-day trend |
| Lock Screen inline | weight |
| Lock Screen circular | goal progress ring with kg to go (weight without a goal) |

The app does all the maths. After each weigh-in, Health change or goal change,
`AppModel.updateWidgetSnapshot()` writes a `WidgetSnapshot` (`Shared/WidgetSnapshot.swift`)
with:
- daily dots and the centered trend for 30 days, so the chart looks like the
  Overview chart
- the app's calm chart axis
- the 30-day trend change
- goal progress

It then calls `WidgetCenter.reloadAllTimelines()`. New snapshot fields are
optional, so older snapshots still decode.

Weight is health data, so all values are `.privacySensitive()`: they're redacted
on the Lock Screen while the device is locked.

## Signing

New bundle ids and the App Group need a one-time Xcode signing step on a fresh
machine (open the project, sign in, automatic signing on both targets, ⌘B). After
that, headless `xcodebuild -allowProvisioningUpdates` works. See `docs/RELEASING.md`.
