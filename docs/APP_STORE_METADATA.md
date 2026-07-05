# App Store metadata (draft)

## App name: **MyOpenScale**
Chosen to avoid Xiaomi's **"Mi"** trademark (the original "MiScale" was a
5.2.5/5.2.1 risk). Set as `CFBundleDisplayName` in the app + extension.

Before submitting: confirm **"MyOpenScale"** is available as an App Store app
name in App Store Connect. Note it echoes the open-source *openScale* project —
distinct enough, but avoid implying affiliation with it too.

The bundle id (`com.philippgrulich.myopenscale.app`) stays — Apple cares about the
**visible name** and metadata, not the reverse-DNS id.

## Subtitle (30 chars max)
- `Weigh-ins straight to Health`  (28)

## Promotional text (170 chars)
Turn your Bluetooth body-composition scale into automatic Apple Health
entries — weight, body fat, lean mass and BMI, computed privately on your iPhone.

## Description
Step on your scale and your weigh-ins flow straight into Apple Health — no
accounts, no cloud, nothing leaves your iPhone.

- **Automatic**: catches your weigh-in over Bluetooth, even with the screen off.
- **Body composition**: estimates body fat %, lean mass and BMI from your reading.
- **Knows it's you**: learns your weight + body-composition signature so only your
  readings are saved — a housemate's weigh-in is skipped or held for a one-tap
  "Was this you?".
- **Apple Health**: writes weight, body fat, lean mass and BMI; charts your trend
  and goal.
- **Private by design**: on-device only, no account, no tracking, no servers.
- **Quick access**: Home/Lock-Screen widget, a Control Center "weigh in" button,
  and Siri/Shortcuts.

Body-composition values are estimates, not medical advice.

Works with the Xiaomi Mi Body Composition Scale 2. This is an independent app and
is not affiliated with, endorsed by, or sponsored by Xiaomi.

## Keywords (100 chars, comma-separated, no spaces)
`weight,scale,body fat,BMI,health,bluetooth,body composition,lean mass,weigh in,fitness`

## Category
Primary: **Health & Fitness**

## Age rating
**4+** (no medical/treatment claims — describe metrics as estimates only).

## App Privacy answers (must match PrivacyInfo.xcprivacy)
- **Data used to track you:** None.
- **Data collected:** **None** ("Data Not Collected"). Health data is written to
  the user's own Apple Health and stays on device; the app does not collect it.

## Privacy policy URL
Host `docs/PRIVACY.md` (e.g. GitHub Pages) and paste the URL.

## Support URL
A simple page or a mailto/contact link (required field).
