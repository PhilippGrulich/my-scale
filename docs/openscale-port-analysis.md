# openScale → iOS: OpenScaleKit analysis (2026-10-18)

Source: openScale (https://github.com/oliexdev/openScale) at commit `8ef93b2` (2026-10-17), read only.
`B` = `android_app/app/src/main/java/com/health/openscale/core/bluetooth`.

## Recommendation

Build **OpenScaleKit** as a separate, **permissively licensed (MIT/Apache-2.0) clean-room** Swift package. Use openScale as a source of *protocol facts* (UUIDs, byte layouts, handshakes, formula coefficients): extract them into written per-driver specs, then write Swift from the specs. **Do not translate the Kotlin**: a translation is a GPLv3+ derivative work, and a GPL dependency is incompatible with App Store distribution of MyOpenScale (MIT). Ship by protocol family, gated on captured byte fixtures. Don't aim for "all 66 drivers" up front.

## Licence

- openScale is GPLv3-or-later, with many copyright holders, and also imports GPL-3.0 code from ble-scale-sync and bodymiscale. Relicensing or an App Store exception is unrealistic.
- Facts (UUIDs, offsets, scale factors, command bytes, regression coefficients) aren't copyrightable. A documented spec-first reimplementation is defensible (US: *Feist*; EU: SAS v WPL). There is residual risk around "substantial similarity", so keep the spec → code process explicit.
- A GPL OpenScaleKit would make the shipped app binary GPLv3 (Corresponding Source, plus §6 Installation Information for an iPhone). The FSF considers App Store terms incompatible (VLC, 2011).
- ⚠️ **Check now:** `Sources/MyOpenScaleCore/BodyCompositionCalculator.swift` cites dckiller51/`bodymiscale`, which openScale labels GPL-3.0. If that code was translated rather than rederived from the equations, it's an existing GPL exposure. Also verify the licence of lolouk44's `Xiaomi_Scale_Body_Metrics`.
- `docs/multi-scale-support-plan.md` §7 calls the app "closed"; it's MIT. "Cite the spec, not the source" is naive here, because openScale's source is often the only spec.

## openScale's Bluetooth architecture

- BLE library: blessed-kotlin (MIT).
- Base class: `B/scales/ScaleDeviceHandler.kt` (~410 lines). `supportFor(ScannedDeviceInfo)` handles matching. GATT drivers use `onConnected`/`onNotification`, broadcast drivers use `onAdvertisement → BroadcastAction`. There are helpers for notify/write/read/publish/disconnect, per-driver settings, and user prompts (CHOOSE_USER / ENTER_CONSENT). It's already nearly sans-IO.
- `DeviceSupport` declares capabilities, a `TuningProfile` and `LinkMode {CONNECT_GATT, BROADCAST_ONLY, CLASSIC_SPP}`. Adapters: `ModernScaleAdapter`, `GattScaleAdapter`, `BroadcastScaleAdapter`, `SppScaleAdapter`.
- Selection: `B/ScaleFactory.kt` holds an **ordered list where the first match wins**, and order matters (the `0xFFB0` drivers must come before MGB; PicoocBroadcast before Scaleup's generic match). Most drivers match by name prefix, some by service UUID or manufacturer data plus checksums.
- User slots: `StandardWeightProfileHandler.kt` uses UDS `0x181C` / UCP `0x2A9F` (register, consent, list) and persists slot→user and the consent code. Beurer/Sanitas, Medisana and Omron have vendor variants.
- Formulas: `B/libs/` has 27 pure-Kotlin files (6.7k lines, no Android imports). `StandardImpedanceLib` is used by 13 drivers, `YunmaiLib` by 4, `TrisaBodyAnalyzeLib` by 3, `MiScaleLib` by 2, plus one library per vendor. Many scales report body fat themselves.

## Supported drivers: 66 handlers, 102 products (`ScaleCatalog.kt`)

| Family | Drivers |
|---|---|
| SIG standard (`0x181D`/`0x181B`/`0x181C`/`0x1805`) | StandardWeightProfile + AndUC352, BeurerBF450, SanitasSbf72, StandardBeurerSanitas, OmronWlc. Standard plus vendor extensions: MiScale v1/v2 (GATT), Renpho, Soehnle, HuaweiHagridWsp |
| Broadcast-only (12) | AAAx, AiLinkBroadcast (TEA), EtekcityFit8S, EufyC20, MiScaleS400 (AES-CCM + bind key), OkOk, PicoocBroadcast, QNBroadcast, Scaleup, Sinocare, XiaomiS800/S200, YunmaiX |
| LeFu `0xFFB0` (13) | ActiveEraBF06, DrTrustSSW532, EEBBL, FitTrackDara, HealthKeep280, HoffenBbs8107, MGB, OneByoneNew, Relaxmedic, RobiS9, RunstarR5/R6, TaylorBIA |
| `0xFFF0` | CultSmart, Digoo, EufyP2, ExcelvanCF36x, Hesley, HumeDara2, Inlife, OneByone (incl. eufy), Picooc, Vitafit, Senssun |
| `0xFFE0` | BeurerSanitas (BF700/710/800, SBF70/75), Yunmai Mini/SE, QN, CustomOpenScale |
| Medisana-style | MedisanaBs44x, Trisa, BodyConnect, WeightGurusA3 |
| Other GATT | Ebelter, HuaweiAhCh100/CH100S (`0xFAA0`); ESCS20M, RenphoES26BB (`0x1A10`); KeepS3; AfuB1, EtekcityESF551, ExingtechY1, Realme, RyFit |
| Classic SPP | IHealthHS3: **impossible on iOS** (needs MFi) |

**Hard on iOS:**
- MAC address as crypto input (EufyP2, Huawei ×3, Realme, Mi S400). iOS hides MACs, so the workarounds are the Device Info System ID `0x2A23`, a MAC echoed in the payload, or user entry.
- MAC used only for matching (RyFit OUI, AAAx/YunmaiX echo checks) is easy to relax.
- **Background scanning needs service-UUID filters.** Broadcast scales that only send manufacturer data (AAAx, OkOk, Scaleup, EufyC20, YunmaiX) are foreground-only.
- Bonding/consent flows (Omron, WeightGurus, BodyConnect, UDS) are doable but need hardware. AES-CCM isn't in CryptoKit (~100 lines on CommonCrypto).

## Size and effort

Handlers 24.2k lines, libraries 6.7k, infrastructure 2.6k, tests 14.8k. A clean-room build is about 25k Swift lines, roughly **60–100 dev-days** for everything, or **45–65 days for phases P0–P4** below.

## Proposed package layout

```
OpenScaleKit/
  OpenScaleCore      pure: ByteReader/Writer, BLEUUID (no CBUUID), AdvertisementSnapshot, ScaleReading
  OpenScaleFormulas  pure: StandardImpedance, Yunmai, Trisa, Xiaomi, … (one per vendor)
  OpenScaleDrivers   pure: one driver per family + ordered DriverRegistry
  OpenScaleBluetooth CoreBluetooth transport (actor ScaleCentral, state restoration, serial GATT queue)
  OpenScaleTesting   hex helpers, TranscriptPlayer, MockTransport
```

```swift
public protocol ScaleDriver: Sendable {
  static var descriptor: DriverDescriptor { get }               // id, family, capabilities, linkMode
  static func match(_ adv: AdvertisementSnapshot) -> MatchScore? // specificity, not Bool
}
public protocol BroadcastDriver: ScaleDriver {
  mutating func ingest(_ adv: AdvertisementSnapshot, context: DriverContext) -> [DriverOutput]
}
public protocol GattDriver: ScaleDriver {
  mutating func start(services: GattTree, context: DriverContext) -> [DriverOutput]
  mutating func handle(_ event: GattEvent) -> [DriverOutput]
}
public enum DriverOutput { case subscribe(BLEUUID), write(BLEUUID, Data, withResponse: Bool),
  read(BLEUUID), reading(ScaleReading), needsUser(UserPrompt), persist(String, Data), disconnect }
```

Connection states: `idle → connecting → discovering → subscribing → driverHandshake → measuring → done | failed`.

MyOpenScale's current passive parser becomes `XiaomiMiScale2BroadcastDriver`; `BLEScanner`/`WatchBLEScanner` become thin clients of `ScaleCentral`; `MeasurementFinalizer` stays for streaming drivers. Use the scale's own composition values when present, otherwise MyOpenScale's calculator. Persist `(peripheralID, driverID)`.

## Test strategy

1. **Byte fixtures:** JSON fixtures with provenance (issue URL, model, vendor-app value), built from the 36 issue-linked captures in openScale's tests and their GitHub issues. Data, not copied test code.
2. **Transcript tests:** `TranscriptPlayer` scripts a GATT tree and notifications into a driver and asserts the exact writes (handshake, time sync, UDS consent) and the readings. `MockTransport` exercises `ScaleCentral` timeouts and mid-handshake disconnects.
3. **Registry tests:** a synthetic-advertisement catalog paired with the expected driver (mirrors `ScaleCatalog.kt`/`ScaleFactoryTest`). This catches match-order bugs.
4. **Formula tests:** golden CSVs from running openScale's pure `libs/` on a plain JVM (`kotlinc`) over a weight × impedance × age × height × sex grid; the harness lives in a separate repo, and its output data isn't a derivative work. Plus property tests (ranges, monotonic in impedance, fat + lean = weight) and encode/decode round trips.
5. **Capture tooling:** a converter from nRF Connect / PacketLogger / btsnoop logs to transcripts, an in-app debug "GATT dump" mode, and an issue template asking for the vendor-app value for the same weigh-in.
6. **Hardware-only:** bonding/consent, background relaunch, MTU/timing, MAC-dependent crypto, accuracy against the vendor app. Mark each driver *fixture-verified* or *hardware-verified*.
7. **CI:** `swift test` for the pure modules on macOS (plus Linux), `xcodebuild` for the Bluetooth module on iOS/watchOS, and a licence lint that rejects "GNU General Public".

## Roadmap

| Phase | Scope | Effort |
|---|---|---|
| P0 | Skeleton, sans-IO API, `ScaleCentral`, testing module, Mi Scale 2 broadcast driver; MyOpenScale switched over with no change in behaviour | 8–12 d |
| P1 | SIG standard + UDS slots/consent, Beurer/Sanitas/A&D/Omron subclasses, user-picker UI | 8–12 d |
| P2 | Broadcast family incl. S400 (CCM) | 8–10 d |
| P3 | LeFu `0xFFB0` (13 drivers) + StandardImpedance | 10–15 d |
| P4 | Yunmai, QN/Renpho, Beurer BF700, Medisana-style | 10–15 d |
| P5 | Long tail on demand; MAC-crypto drivers once a workaround is proven; never iHealth HS3 | open |
