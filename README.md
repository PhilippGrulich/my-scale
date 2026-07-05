# MyOpenScale

A private, on-device iOS app that turns a Bluetooth body-composition scale into
automatic **Apple Health** entries — weight, body fat, lean mass and BMI —
computed on your iPhone. No accounts, no cloud, nothing leaves the device.

- Listens for the scale's Bluetooth advertisements (no pairing/connection).
- Learns your weight + body-composition **signature** so only your readings are
  saved; a housemate's weigh-in is skipped or held for a one-tap "Was this you?".
- Writes to Apple Health; charts your trend and goal; Home/Lock-Screen widget,
  Control Center control, and Siri/Shortcuts.

> Body-composition values are estimates, not medical advice.

## Build

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate
xcodebuild -scheme MyOpenScaleApp -destination 'generic/platform=iOS' build
```

Pure logic lives in the `MyOpenScaleCore` Swift package (`swift test`); the app,
HealthKit, and CoreBluetooth code is in `App/`. See `docs/` for the design plan,
the multi-scale support plan, and App Store notes. To ship a new build to
TestFlight, follow [`docs/RELEASING.md`](docs/RELEASING.md).

## Compatibility

Works with the **Xiaomi Mi Body Composition Scale 2** by reading its public
Bluetooth advertisements. This is an independent project and is **not affiliated
with, endorsed by, or sponsored by Xiaomi**. Support for additional scales is
planned — see [`docs/multi-scale-support-plan.md`](docs/multi-scale-support-plan.md).

## License

[MIT](LICENSE) © 2026 Philipp Grulich
