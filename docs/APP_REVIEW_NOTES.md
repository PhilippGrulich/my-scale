# App Review Notes (paste into App Store Connect → App Review Information → Notes)

Thank you for reviewing the app.

## How to evaluate without the hardware
The app's core feature reads a physical Bluetooth body-composition scale, which
the review device will not have. To see the full flow **without a scale**:

1. Launch the app and complete the short onboarding (you can tap **"Not now"**
   on the Apple Health step and **"Skip for now"** on the scale-pairing step).
2. On the main screen, tap **"See a sample reading"** (shown when there's no data
   yet). This plays the live measuring animation and shows an example result with
   computed body-fat / lean mass / BMI.
   - This sample is clearly labelled and **saves nothing** to Apple Health.
3. Tapping a metric card opens that metric's history; the profile (person icon)
   lets you edit details and set a goal.

A demonstration video of a real weigh-in with the physical scale is available on
request.

## Apple Health
The app requests permission to **read** date of birth, biological sex, height,
and weight history (to set up the profile and compute body composition), and to
**write** weight, body-fat %, lean body mass, and BMI. Health data is used only
on-device to provide these features; it is never transmitted off the device or
used for advertising. Denying Health access does not block the app.

## Background Bluetooth
The app declares the `bluetooth-central` background mode so it can catch a
weigh-in when the phone's screen is off (the scale broadcasts its reading for a
few seconds). It **only listens for advertisements** of the user's remembered
scale — it does not connect, does not track location, and does not scan for other
devices. This is essential to the app's purpose (recording weigh-ins that happen
while the phone is in a pocket or on a charger).

## Privacy / accounts
No account, no sign-in, no server, no analytics, no tracking. All data stays on
the device and in the user's own Apple Health. Privacy policy URL is provided in
the App Privacy section.

## Third-party hardware
The app is **compatible with** the Xiaomi Mi Body Composition Scale 2 by reading
its public Bluetooth advertisements. It is an independent app, **not affiliated
with, endorsed by, or sponsored by Xiaomi**, and uses no Xiaomi trademarks or
logos in its branding.
