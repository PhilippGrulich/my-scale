# App Review Notes (paste into App Store Connect → App Review Information → Notes)

Thank you for reviewing Mochi: Weight Tracker.

## How to evaluate without the scale
The app reads a physical Bluetooth body-composition scale, which the review
device will not have. Everything else works without it:

1. Launch the app and go through the short onboarding. You can tap **"Not now"**
   on the Apple Health step and skip pairing a scale.
2. On **Overview**, tap **"See a sample reading"** (shown while there's no data).
   It plays the live weigh-in and shows an example result with body fat, lean
   mass and BMI. This sample is labelled and **saves nothing**.
3. Tap **+ Weigh in** (centre tab) to enter a weight manually with the rolling
   wheel and tap **Save**. It's saved to Apple Health (if allowed) and the
   companion character (Mochi) reacts.
4. **Goal** tab: set a goal and see progress, a forecast and milestones.
   **History** tab: weigh-ins (tap to edit, swipe to delete) and, with Health
   access, workouts and steps. **Settings** → **About & licenses** shows the
   open-source licenses and disclaimers.

A video of a real weigh-in with the scale is available on request.

## Apple Health
Read: date of birth, sex, height, weight, body fat, lean mass, BMI (profile, body
composition, history), and workouts, steps, active and dietary energy (shown in
History and used for the companion's messages). Write: weight, body fat, lean
mass, BMI. Data is used only on-device; never transmitted, never used for
advertising. Denying Health access does not block the app.

## Background Bluetooth
The `bluetooth-central` background mode lets the app catch a weigh-in while the
phone is locked (the scale broadcasts its reading for a few seconds). Bluetooth
is only used after the user pairs a scale, and the app only listens for that
scale's advertisements: no connection, no location, no scanning for other
devices.

## Apple Watch
The watch app weighs in with the scale while open (watchOS has no background
Bluetooth) or takes a manual entry, and writes to Apple Health. Settings arrive
from the iPhone via WatchConnectivity.

## Privacy / accounts
No account, no sign-in, no server, no analytics, no tracking. Medical
disclaimer: body-composition values are shown as estimates, not medical advice.
Not affiliated with Xiaomi.
