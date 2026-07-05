# Plan: Supporting Other Scales

_Created 2026-07-01. Status: feasibility + design (no code yet)._

## The question
Can the app support scales beyond the Xiaomi Mi Body Composition Scale 2 — and
what would it take?

## TL;DR — yes, and the architecture is already most of the way there
Everything downstream of *parsing* is **scale-agnostic**: the finalizer,
body-composition math, "is this me?" attribution, HealthKit sink, trends,
widget, and onboarding all operate on canonical **weight + impedance**. Only two
files are Mi-specific:
- `Sources/MyOpenScaleCore/AdvertisementParser.swift` — the 13-byte 0x181B layout.
- `App/BLEScanner.swift` — scans only service `0x181B` and reads **advertisements
  only** (no GATT connection).

Adding scales means adding **drivers** behind a small abstraction; the rest is
untouched. Two effort tiers:
- **Advertisement-broadcast scales** (like the Mi): easy — just a new parser.
- **Connection (GATT) scales** (most others): a moderate new acquisition path —
  and it actually **improves background reliability** (connection events can
  relaunch the app; advertisement scanning can't).

The new name **"MyOpenScale"** fits this direction well.

---

## 1. Current coupling vs. what's already generic

| Layer | File | Scale-specific? |
|---|---|---|
| BLE acquisition | `App/BLEScanner.swift` | **Yes** — hardcoded `0x181B`, advertisement-only |
| Advertisement parse | `Sources/MyOpenScaleCore/AdvertisementParser.swift` | **Yes** — Mi 13-byte layout + bit flags |
| Canonical frame | `ParsedAdvertisement` (weight, impedance, flags) | Neutral (could be renamed `ScaleFrame`) |
| Finalize (settle/step-off) | `MeasurementFinalizer.swift` | **No** — pure state machine on frames |
| Body composition | `BodyCompositionCalculator.swift` | Mostly no (formula constants are Mi-derived — see §6) |
| Attribution ("is this me?") | `AttributionModel.swift` | **No** — weight+impedance only |
| Sinks / UI / widget | `HealthKitSink`, dashboard, widget | **No** |

So the extension surface is **just the acquisition + parse layer**.

## 2. The landscape of BLE scales (three categories)

**A. Advertisement-broadcast (no connection).** The scale puts the reading in the
BLE advertisement's service data; the app just listens. Rare but ideal.
- Xiaomi/Mi family (Mi Scale 2 / MIBFS, Mi Scale v1 weight-only).
- A handful of others.

**B. Standard BLE GATT.** Implements the Bluetooth SIG **Weight Scale Service
`0x181D`** (Weight Measurement `0x2A9D`) and/or **Body Composition Service
`0x181B`** (Body Composition Measurement `0x2A9C`) over a *connection*. One
generic driver covers any compliant scale.
- Note: the Mi scale reuses the `0x181B` **UUID in advertisement service-data**,
  which is *not* the same as the standard `0x2A9C` GATT characteristic — don't
  confuse them.
- Adoption is partial (some Beurer, medical/clinical scales).

**C. Proprietary GATT.** The bulk of consumer scales: connect, discover a
vendor service, often write an init/handshake command, then parse notification
frames. Each is its own driver. Reference implementations exist in the
open-source **openScale** (Android) project:
- **Yunmai** (Mini/SE/Color), **Beurer/Sanitas** (shared OEM: BF700/710/800,
  SBF70/77), **Medisana** (BS444/440), **Trisa**, **Excelvan/Exingtech**,
  **OKOK / QN-Scale** family (rebadged as **Yolanda**, some **Renpho**), **iHealth**,
  **Silvercrest**, etc.
- **Renpho** (very popular): largely proprietary/cloud; partial community support
  via the QN/OKOK protocol. High user value, higher effort/uncertainty.

## 3. iOS / CoreBluetooth feasibility

- **Category A** — fully feasible today (we already do it). Foreground solid,
  background best-effort (unchanged from current limitations).
- **Categories B & C** — fully feasible with CoreBluetooth: `connect` → discover
  services/characteristics → `setNotifyValue` (indications/notifications) →
  optional `writeValue` handshake → parse frames. **Bonus:** connection-based
  scales pair naturally with **state restoration** (we already pass
  `CBCentralManagerOptionRestoreIdentifierKey`), so iOS can **relaunch the app in
  the background on connect/disconnect** — the reliable background weigh-in we
  couldn't get from advertisement scanning.
- Identity: iOS never exposes a scale's MAC; we key on `CBPeripheral.identifier`
  (already persisted for pairing) — works for both transports.

## 4. Proposed architecture — a driver abstraction

Introduce a driver layer; the Mi parser becomes one driver. No downstream change.

```
protocol ScaleDriver {
    var id: String { get }                 // stable id, persisted with the paired scale
    var displayName: String { get }
    var serviceUUIDs: [CBUUID] { get }      // what BLEScanner should scan for
    var transport: ScaleTransport { get }   // .advertisement or .connection

    // Advertisement drivers:
    func parse(serviceData: [CBUUID: Data]) -> ParsedAdvertisement?

    // Connection drivers (a small session the scanner drives):
    func makeSession() -> ScaleConnectionSession?   // discover → subscribe → (write) → emit frames
}
```

- `ScaleDriverRegistry` lists all drivers. `BLEScanner` scans for the **union** of
  all `serviceUUIDs`, then routes each discovered peripheral to the first driver
  whose `matches`/`parse` succeeds.
- **Advertisement path**: unchanged flow (parse service data → `ParsedAdvertisement`
  → finalizer). The current Mi code moves behind `MiScale2Driver`.
- **Connection path**: a new `ScaleConnectionCoordinator` owns
  `connect/discover/notify/write` and feeds parsed frames into the *same*
  `MeasurementFinalizer` per peripheral. The finalizer, body-comp, attribution,
  HealthKit, widget are reused verbatim.
- Rename `ParsedAdvertisement` → `ScaleFrame` (keep a typealias) so the canonical
  type isn't advertisement-specific. Pure, still testable from hex fixtures.

Persist the matched **driver id** alongside `PairedScale.peripheralID`, so we know
how to talk to a remembered scale (and could support **multiple paired scales**,
even of different brands, per household member — which composes with the
attribution model).

## 5. Driver targets & suggested priority

1. **`MiScale2Driver`** — refactor existing code behind the protocol (no new
   behavior). Proves the abstraction. *No hardware needed beyond current.*
2. **`StandardBLEScaleDriver`** — SIG `0x181D`/`0x2A9D` (+ `0x181B`/`0x2A9C`).
   Covers any standards-compliant scale with one driver; testable against any
   such unit. *Best effort-to-coverage ratio.*
3. **High-volume proprietary**, one at a time, each gated on owning the unit:
   **Yunmai**, **Beurer/Sanitas** (one driver, many models), **OKOK/QN
   (Yolanda/Renpho-compatible)**. Reimplement from protocol, don't copy code (§7).

## 6. Cross-cutting concerns

- **Body-composition formulas differ per brand.** Our current constants are
  Mi/lolouk44-specific. Options per driver: (a) if the scale *transmits* body-fat
  itself, store it directly; (b) else apply our generic formula and flag it as an
  approximation. Make the calculator selectable per driver.
- **Onboarding/pairing.** The pairing step already shows a live candidate; extend
  it to detect *which driver* matched and store `(peripheralID, driverId)`. For
  connection scales, "step on the scale" triggers a connect + read.
- **Units.** Reuse the existing kg/lb normalization; each driver reports kg.
- **Attribution & HealthKit.** Unchanged — weight+impedance in, same signature
  learning and Health writes out.
- **Battery.** Connection drivers should connect *on demand* (scan → connect →
  read → disconnect), not hold a link, to protect battery.

## 7. Risks & open questions

- **Hardware to test.** Every proprietary driver needs the **physical scale** to
  reverse-engineer and verify — the dominant cost. Standard + Mi are the only
  ones testable without buying units.
- **Licensing (important).** openScale is **GPLv3**. **Do not copy its code** into
  this (closed, App Store) app — that would impose GPL. Reimplement drivers
  **clean-room from the protocol** (byte layouts, handshake sequences), citing the
  spec, not the source.
- **Accuracy claims.** Keep the "estimates, not medical advice" framing across all
  scales (formulas vary in quality).
- **App Review.** More third-party device names → keep the nominative,
  non-affiliation wording per brand; no vendor logos.
- **Scope creep.** Proprietary drivers are effectively endless; ship the
  abstraction + Mi + Standard first, then add brands by demand.

## 8. Milestones

- **MS0 — Driver abstraction (no new hardware).** Extract `ScaleDriver` +
  `ScaleDriverRegistry`; move Mi behind `MiScale2Driver`; rename
  `ParsedAdvertisement → ScaleFrame` (typealias). All existing tests stay green.
- **MS1 — Connection transport.** `ScaleConnectionCoordinator` (connect/discover/
  notify/write) feeding the existing finalizer; wire state-restoration for
  background connection wake.
- **MS2 — `StandardBLEScaleDriver`** (`0x181D`/`0x2A9D`, `0x181B`/`0x2A9C`) with
  parser unit tests from spec fixtures; verify against a compliant scale.
- **MS3 — First proprietary driver** (e.g. Yunmai) as the template; per-driver
  body-comp handling.
- **MS4 — Pairing/onboarding** stores `driverId`; support multiple paired scales.
- **MS5+** — additional brands by demand, each gated on a physical unit.

## 9. Verification

- **Pure (no hardware):** driver parse unit tests from captured/spec hex frames
  (as the Mi parser already has); finalizer/attribution unchanged.
- **Standard driver:** test against any SIG-compliant scale.
- **Per proprietary driver:** on the physical unit — one weigh-in yields exactly
  one finalized reading; values match the vendor app within tolerance.
- **Regression:** the Mi path must behave identically after the refactor (MS0).
