# App Store metadata (draft)

## App name: **Mochi: Weight Tracker**
App Store name (30 chars max: 21). Home-screen name (`CFBundleDisplayName`):
**Mochi**, after the cat companion. Renamed from "MyOpenScale" on 2026-10-20;
the ASC app record keeps its id (`6787745052`), only the name changes — set it
in App Store Connect → App Information → Name (must be available).
Avoid Xiaomi's "Mi" in the name (trademark, guidelines 5.2.1/5.2.5).

The bundle id (`com.philippgrulich.myopenscale.app`) stays — Apple cares about the
**visible name** and metadata, not the reverse-DNS id.

## Subtitle (30 chars max)
- `Smart scale & body composition`  (30)

## Promotional text (170 chars)
Turn your Bluetooth body-composition scale into automatic Apple Health
entries — weight, body fat, lean mass and BMI, computed privately on your iPhone.

## Description
Step on your scale and your weigh-ins flow straight into Apple Health — no
accounts, no cloud, nothing leaves your devices.

- **Automatic**: catches your weigh-in over Bluetooth, even with the screen off.
- **Body composition**: body fat, muscle, water, bone, visceral fat, BMI, basal
  metabolic rate and metabolic age, each with a history and an explanation.
- **Calm trend**: a smoothed weight trend that ignores day-to-day water swings.
- **Goals**: target date, on-plan status, forecast, milestones and a maintenance
  range once you get there.
- **Mochi**: a friendly companion that cheers on your weigh-ins and workouts and
  sends gentle reminders (optional).
- **Manual entries** and a **History** that includes workouts and steps from
  Apple Health.
- **Apple Watch**, Home/Lock-Screen widgets, Control Center and Siri.
- **Knows it's you**: only your readings are saved; a housemate's weigh-in is
  skipped or held for a one-tap "Was this you?".
- **Private and open source**: on-device only, no account, no tracking.
- English and German.

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
https://github.com/PhilippGrulich/my-scale/blob/main/docs/PRIVACY.md

## Support URL
https://github.com/PhilippGrulich/my-scale/issues

## Licenses
MyOpenScale is MIT. Body-composition formulas are based on
lolouk44/Xiaomi_Scale_Body_Metrics (MIT) and dckiller51/bodymiscale
(Apache-2.0); their licenses are shown in-app under Settings → About &
licenses and in `THIRD_PARTY_NOTICES.md`. No third-party code libraries are
linked. Export compliance: no non-exempt encryption
(`ITSAppUsesNonExemptEncryption = NO`).
