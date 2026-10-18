# MyOpenScaleControls — Control Center control + widget

**Status: wired into `project.yml` for the 1.0 release.** The shared stores
(`MeasurementHandoff`, `WidgetSnapshot`) now use the App Group
`group.com.philippgrulich.myopenscale`. The only remaining step is the **one-time
Xcode signing setup** below (the headless build can't create the new bundle id /
App Group — "No Accounts").

This folder holds a WidgetKit extension with two things:
- a **Control Center control** ("Start Weigh-In") that opens the app and arms a
  new measurement (`MyOpenScaleControlsBundle.swift`), and
- a **Home / Lock Screen widget** showing the latest weight + trend
  (`MyOpenScaleWidget.swift`), fed by the snapshot the app writes in
  `Shared/WidgetSnapshot.swift`.

It is **not** wired into `project.yml` yet because it needs signing setup that
can't be done from a headless build:

- a **new bundle id** `com.philippgrulich.myopenscale.app.controls`, and
- the **App Groups** capability (`group.com.philippgrulich.myopenscale`) on **both**
  the app and this extension, so the extension (separate process) can hand the
  "start" signal to the app.

Both require the Apple ID account in Xcode's GUI to register the app id / group.

## How to enable it

1. In `project.yml`, re-add (a) `com.apple.security.application-groups: [group.com.philippgrulich.myopenscale]`
   to the **app** target's entitlements, (b) the `MyOpenScaleControls` app-extension
   target (sources: `Controls`, `Shared`; `INFOPLIST_FILE: Controls/Info.plist`;
   entitlements: `Controls/MyOpenScaleControls.entitlements`), and (c) a
   `- target: MyOpenScaleControls` / `embed: true` dependency on the app target.
   (See git history of `project.yml` for the exact block.)
2. In **both** `Shared/MeasurementHandoff.swift` and `Shared/WidgetSnapshot.swift`,
   switch `defaults` from `.standard` to
   `UserDefaults(suiteName: "group.com.philippgrulich.myopenscale")` so the extension's
   separate process shares the flag/snapshot with the app.
3. `xcodegen generate`, open `MyOpenScaleApp.xcodeproj` in Xcode once, select the
   `MyOpenScaleControls` target → Signing & Capabilities → ensure "Automatically
   manage signing" + the team, and confirm the **App Groups** capability shows
   `group.com.philippgrulich.myopenscale` on both targets (Xcode registers them).
4. Build/deploy. The control then appears in the Control Center gallery
   (long-press Control Center → **+** → search "Weigh In").

Until then, "Start Weigh-In" is still available via **Siri, Spotlight, and the
Shortcuts app** (the in-app `StartMeasurementIntent` + `MyOpenScaleShortcuts`), and
the **+ Weigh in** button in the middle of the tab bar.
