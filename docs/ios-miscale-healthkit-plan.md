# iOS App Plan — MiScale 2 → HealthKit (foreground-only)

## Context

We want a self-contained native iOS app that runs on a **dedicated always-on
iPhone** (on charger, Guided Access / kiosk, idle timer disabled). It passively
listens for BLE *advertisements* from a **Xiaomi Mi Body Composition Scale 2**
(no pairing, no GATT connection), parses each advertisement's service data,
decides when a reading is final, computes body composition locally, attributes
the reading to one of several household users by configured weight range, and
writes the result into **Apple HealthKit**. Each measurement is *optionally*
mirrored to **Home Assistant** over HTTP. There is no cloud account, no scale
SDK, and no server component — everything runs on-device.

**Decisions already locked (do not relitigate):**
- Swift + SwiftUI, native, **iOS 16+**.
- BLE input = advertisements under Body Composition service UUID **0x181B**,
  read via `CBAdvertisementDataServiceDataKey` in `didDiscover`. No connect.
- **Foreground-only** scanning. Background BLE / state restoration is explicitly
  **out of scope for v1** (hook points for v2 noted inline).
- HealthKit is the primary sink and we write **only the four HealthKit-native
  body metrics**: `bodyMass`, `bodyFatPercentage`, `leanBodyMass`,
  `bodyMassIndex`. The other scale-derived metrics (muscle, water, bone,
  visceral fat, BMR, metabolic age) have **no HealthKit type** and are **out of
  v1 scope** (formulas catalogued for a future version, not computed in v1).
- HA mirror is a secondary, **non-blocking** sink that must never affect the
  HealthKit path.
- Multi-user: ≥2 users disambiguated by **configurable weight ranges**;
  per-user static profile = height, date of birth, biological sex. An
  ambiguous/no-match reading is **held for manual confirmation**, never
  auto-attributed.

### Verified technical inputs (sources)

**BLE service-data layout — MiScale 2, UUID 0x181B, 13-byte payload.** Verified
against ESPHome `xiaomi_miscale` (PR #1368) and openScale
`BluetoothMiScale2.java`. Byte offsets are into the *service-data value*
(`CBAdvertisementDataServiceDataKey[CBUUID(0x181B)]`), which on iOS does **not**
include the UUID prefix.

| Offset | Field | Encoding |
|---|---|---|
| 0 | Unit/measurement byte | `0x02` = kg, `0x03` = lb (see flags too) |
| 1 | **Control/flags byte** | bitfield (below) |
| 2–3 | Year | uint16 LE |
| 4 | Month | uint8 |
| 5 | Day | uint8 |
| 6 | Hour | uint8 |
| 7 | Minute | uint8 |
| 8 | Second | uint8 |
| 9–10 | **Impedance** | uint16 LE, ohms |
| 11–12 | **Weight (raw)** | uint16 LE |

**Control byte (offset 1) bit flags** — from openScale `isBitSet(ctrlByte1, n)`:
- bit 1 (`0x02`) = **impedance present** ← the flag the spec asks for
- bit 5 (`0x20`) = **stabilized / measurement complete**
- bit 7 (`0x80`) = **weight removed (load lifted)**
- (unit bits: lb via byte0 `0x03`; catty/jin via byte0 bit 6 — handle, prefer kg)

**Weight decode:** `raw = LE(bytes[11..12])`; kg → `raw / 200.0`; lb or
catty/jin → `raw / 100.0` (then convert lb→kg ×0.45359237 for storage). Store
canonical kg internally.
**Impedance decode:** `LE(bytes[9..10])` ohms; treat as valid only if
`1 ≤ impedance ≤ 3000`.
**Finality rule:** a reading is final iff `stabilized (bit5) && impedancePresent
(bit1) && !weightRemoved (bit7)` and impedance in range. *(Note: v1 needs
impedance for body fat / LBM, so impedance-present is required, not optional.)*

> ⚠️ Cross-source ambiguity: ble-in-xiaomi docs mention a "bit 14 impedance
> valid" in a 2-byte control word; openScale's `ctrlByte1 bit 1` is the
> authoritative single-byte interpretation we follow. **Must be confirmed
> against real captured payloads before shipping** (see Open Questions).

**Body-composition formulas (v1 needs only LBM + fat% + BMI).** From lolouk44
`Xiaomi_Scale_Body_Metrics.py` / `body_scales.py`, mirrored by dckiller51
`bodymiscale`:
- **LBM coefficient** (kg): `LBM = (h*9.058/100)*(h/100) + w*0.32 + 12.226 −
  imp*0.0068 − age*0.0542` (h=cm, w=kg, imp=ohms, age=yr).
- **Body fat %**: `fat = (1 − ((LBM − c) * k) / w) * 100`, where `c` and `k`
  are sex/age/weight/height piecewise constants (female c=9.25 if age≤49 else
  7.25; male c=0.8; k from weight/height bands). Clamp to [5, 75].
- **Lean body mass for HealthKit** = `w * (1 − fat/100)` (mass form of LBM, in
  kg). *(Decision point — see Open Questions: store the regression `LBM` vs the
  fat-derived lean mass.)*
- **BMI**: `w / (h/100)^2`, clamp [10, 90].
- ⚠️ Several constants are reverse-engineered (fat% coefficients 0.96/1.02/1.03,
  the c-constants) — **flag as unverified**, cover with golden-value tests.

---

## 1. High-level architecture (components + responsibilities)

SwiftUI app, MVVM, one process, all on-device. Layered so the parser and the
formulas are pure/testable and have **zero** dependency on CoreBluetooth or
HealthKit.

```
┌─────────────────────────────────────────────────────────────┐
│ UI (SwiftUI)  Dashboard · Users/Profiles · Settings · Unassigned │
└───────────────▲─────────────────────────────────────────────┘
                │ @Published state
┌───────────────┴─────────────────────────────────────────────┐
│ AppCoordinator / MeasurementPipeline (orchestrator)          │
└───┬───────────┬──────────────┬──────────────┬────────────────┘
    │           │              │              │
┌───▼───┐  ┌────▼─────┐   ┌────▼──────┐  ┌────▼────────┐
│ BLE   │  │ Parser   │   │ BodyComp  │  │ UserResolver│
│Scanner│→ │(pure)    │ → │(pure)     │  │(weight→user)│
└───────┘  └──────────┘   └───────────┘  └─────────────┘
                                │
                ┌───────────────┼────────────────┐
          ┌─────▼─────┐   ┌─────▼──────┐   ┌──────▼──────┐
          │ Store     │   │ HealthKit  │   │ HASink      │
          │(persist)  │   │ Sink       │   │(HTTP, async)│
          └───────────┘   └────────────┘   └─────────────┘
```

- **BLEScanner** (`CBCentralManager` delegate): foreground scan for service
  0x181B, surfaces raw `(serviceData: Data, rssi, peripheralID, hostTimestamp)`
  on `didDiscover`. Owns the BLE state machine (§3). No parsing logic.
- **AdvertisementParser** (pure struct, no imports beyond Foundation): bytes →
  `ParsedAdvertisement` (flags, weight kg, impedance, embedded timestamp).
  Fully unit-testable from hex fixtures.
- **BodyCompositionCalculator** (pure): `(weightKg, impedance, profile) →
  BodyComposition{ bodyMassKg, bodyFatPercent, leanMassKg, bmi }`. Pure math,
  golden-value tested.
- **UserResolver**: maps a finalized weight to a `UserProfile` via configured
  ranges; returns `.matched(user)` / `.ambiguous` / `.noMatch`.
- **MeasurementStore**: local persistence (source of truth) of every finalized
  reading with sink status flags; survives app restart.
- **HealthKitSink**: authorization + writes the 4 quantity samples as one
  correlated save, tagged with metadata (source = scale, impedance, app build).
- **HASink**: optional, fire-and-forget HTTP POST with retry/backoff; isolated
  from HealthKit path.
- **MeasurementPipeline / AppCoordinator**: wires scanner→parser→finalizer→
  calculator→resolver→store→sinks; owns dedupe/debounce; exposes `@Published`
  view state.

---

## 2. Data model

```swift
struct UserProfile: Codable, Identifiable {
    let id: UUID
    var name: String
    var heightCm: Double
    var dateOfBirth: Date
    var sex: HKBiologicalSex        // .male / .female (formulas are binary)
    var weightRangeKg: ClosedRange<Double>   // configurable disambiguation
    var isHealthKitOwner: Bool      // exactly ONE user; HealthKit is single-profile
}

struct ParsedAdvertisement: Equatable {       // output of the pure parser
    var unitRaw: UInt8
    var isStabilized: Bool          // ctrl bit5
    var hasImpedance: Bool          // ctrl bit1
    var isWeightRemoved: Bool       // ctrl bit7
    var weightKg: Double            // already unit-normalized
    var impedanceOhms: Int          // 0 if absent/invalid
    var deviceTimestamp: Date?      // from bytes 2..8 (may be unreliable)
}

struct BodyComposition: Codable {
    var bodyMassKg: Double
    var bodyFatPercent: Double
    var leanMassKg: Double
    var bmi: Double
}

enum SinkState: String, Codable { case pending, written, failed, skipped }

struct Measurement: Codable, Identifiable {
    let id: UUID
    var capturedAt: Date            // host clock at finalization (authoritative)
    var deviceTimestamp: Date?      // scale's embedded time (informational)
    var weightKg: Double
    var impedanceOhms: Int
    var assignedUserID: UUID?       // nil ⇒ unassigned (held for manual confirm)
    var resolution: ResolutionKind  // matched / ambiguous / noMatch / manual
    var composition: BodyComposition?   // computed once user is known
    var healthKitState: SinkState
    var haState: SinkState
    var rawServiceDataHex: String   // kept for debugging + reprocessing
}
```

- **Persistence**: SwiftData (iOS 17+) *or* a small Codable+file/SQLite store to
  honor iOS 16 floor → **plan uses a lightweight repository protocol** backed by
  Codable-to-file (or GRDB) so it works on iOS 16. `Measurement` is the durable
  record; HealthKit/HA are derived sinks that can be retried from it.
- `capturedAt` (host clock) is authoritative for HealthKit; `deviceTimestamp`
  is stored but not trusted (scale RTC drifts / resets).

---

## 3. BLE scan → parse → finalize state machine

The scale emits a *burst* of advertisements during a single weigh-in: many
"not-yet-stable" frames, then stable+impedance frames, then weight-removed
frames. We must emit **exactly one** `Measurement` per physical weigh-in.

**Scanner config:** `scanForPeripherals(withServices: [CBUUID(0x181B)],
options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])`. Allowing
duplicates is **required** — otherwise iOS coalesces adverts and we miss the
stabilized frame. (This is also exactly why background scanning is out of scope:
`allowDuplicates` is ignored in the background — the v2 hook point.)

**Per-device state (keyed by peripheral identifier):**

```
        ┌─────────┐  adv parsed, !stabilized
        │  IDLE   │◄──────────────┐
        └────┬────┘               │
   stabilized&&impedance&&!removed │ stale-timeout (no adv > T_idle)
             │                     │
        ┌────▼──────────┐  another stable adv (same weigh-in)
        │  MEASURING    │──── update/keep best (highest-confidence) ──┐
        └────┬──────────┘◄────────────────────────────────────────────┘
   debounce settle (T_settle since first stable, value stable within ε)
             │ OR weight-removed flag seen
        ┌────▼──────────┐
        │  FINALIZE     │ emit ONE Measurement, mark device "armed-off"
        └────┬──────────┘
   weight-removed OR cooldown elapsed
        ┌────▼──────────┐
        │  COOLDOWN     │ ignore further adverts for T_cooldown
        └────┬──────────┘
             │ T_cooldown elapsed
          back to IDLE
```

**Rules:**
- **Finality condition:** `stabilized(bit5) && impedancePresent(bit1) &&
  !weightRemoved(bit7) && 1≤impedance≤3000`.
- **Debounce:** on first qualifying frame, start `MEASURING`; collect qualifying
  frames for `T_settle` (~0.4–0.8 s) and pick the modal/last weight (they should
  be identical). Finalize when either (a) `T_settle` passes with consistent
  weight, or (b) a `weightRemoved` frame arrives.
- **Dedupe:** suppress duplicate finalizations using a key of
  `(roundedWeight, impedance)` within a `T_cooldown` window (~8–15 s) so the
  repeating stable burst and the weight-removed event don't double-emit.
- **weight-removed event:** treated as a *finalize trigger if we were
  MEASURING*, otherwise ignored (it carries the last weight but bit7 set ⇒ never
  emit a fresh reading from a removed frame alone).
- **Multiple scales / stray devices:** state is per `peripheralID`; the target
  scale is additionally gated by the 0x181B service filter and (optionally) a
  user-set MAC/identifier allowlist in Settings.
- **v2 hook:** to extend to background, this same state machine is driven by a
  restored `CBCentralManager` (`CBCentralManagerOptionRestoreIdentifierKey`) and
  must tolerate `allowDuplicates` being disabled (rely on stabilized frame only,
  accept lower fidelity).

### 3a. Pure finalizer (`MeasurementFinalizer`) — the testable core

The state machine is split from CoreBluetooth so it runs under CI. One
`MeasurementFinalizer` instance per peripheral; **time is injected** (every
call takes `now: Date`) so the settle/cooldown/stale windows are deterministic
in tests with no real clock.

```swift
public struct FinalizerConfig {           // tunable in M9 field soak
    var settle: TimeInterval = 0.6        // hold a consistent weight this long
    var cooldown: TimeInterval = 10       // suppress the repeat burst after emit
    var staleTimeout: TimeInterval = 5    // drop a half-finished weigh-in
    var weightToleranceKg: Double = 0.1   // "same weight" band while settling
}
public struct FinalizedReading: Equatable {
    var weightKg: Double; var impedanceOhms: Int
    var capturedAt: Date; var deviceTimestamp: Date?
}
public final class MeasurementFinalizer {
    enum State { case idle, measuring, cooldown }
    func ingest(_ adv: ParsedAdvertisement, at now: Date) -> FinalizedReading?
    func tick(at now: Date) -> FinalizedReading?   // settle/stale/cooldown when adverts pause
}
```

Transitions (emit **exactly one** reading per weigh-in):
- **idle + final frame** (`adv.isFinalReading`) → `measuring`; record
  `firstStableAt`, candidate weight/impedance. Non-final frames ignored.
- **measuring + final frame** within tolerance: if `now − firstStableAt ≥
  settle` → emit `FinalizedReading(capturedAt: now)`, go `cooldown`; else keep
  waiting. Weight beyond tolerance → restart the settle window on the new value.
- **measuring + weight-removed frame** → finalize the held candidate immediately
  (the load-lifted finalize trigger), go `cooldown`.
- **measuring + tick**: `now − lastAdvAt ≥ staleTimeout` → reset to `idle` (no
  emit); else `settle` elapsed → emit.
- **cooldown**: ignore all frames (dedupes the repeating stable burst and the
  weight-removed event) until `now − finalizedAt ≥ cooldown`, then → `idle`.

Tests (pure, no hardware): replay an advert sequence with synthetic timestamps
and assert exactly one reading for a normal weigh-in, none for a step-off-early
burst, dedupe across the repeat burst + removed event, and restart when the
weight shifts mid-settle. The CoreBluetooth wrapper (M3b) just forwards
`didDiscover` payloads into `ingest` and runs a timer calling `tick`.

---

## 4. Body-composition computation module

Pure, no I/O. Input `(weightKg, impedanceOhms, UserProfile, at: Date)`.

1. Compute `ageYears` from DOB at `capturedAt` (not "now").
2. `LBM = lbmCoefficient(h, w, imp, age)` (formula in Context).
3. `fat% = fatPercentage(LBM, w, sex, age, h)` with piecewise `c`/`k`, clamp
   [5,75].
4. `leanMassKg = w * (1 − fat/100)`.
5. `bmi = w / (h/100)^2`, clamp [10,90].
6. Return `BodyComposition`.

- **Guard rails:** require `impedance>0`; if impedance missing, do **not**
  compute fat%/LBM — store weight + BMI only and mark composition partial.
- **Sex handling:** formulas are binary (male/female). `HKBiologicalSex.other`/
  `.notSet` ⇒ block computation, require the user to set a value (Open Question).
- **All magic constants live in one `BodyCompConstants` file**, individually
  documented with their source line, so flagged/unverified ones are auditable
  and swappable. Deferred metrics (muscle/water/bone/visceral/BMR/metabolic age)
  are kept here as commented spec for a future version but **not** wired in v1.

---

## 5. HealthKit sink + optional HA sink

**HealthKitSink**
- Capability: HealthKit entitlement; `Info.plist`
  `NSHealthShareUsageDescription` + `NSHealthUpdateUsageDescription`.
- Auth flow: on first launch (and lazily before first write) request
  `requestAuthorization(toShare: [bodyMass, bodyFatPercentage, leanBodyMass,
  bodyMassIndex], read: [dateOfBirth?, biologicalSex?])`. Note HealthKit never
  reveals whether *read* was denied; treat write-only.
- Write: build 4 `HKQuantitySample`s with `startDate=endDate=capturedAt`,
  group into one `HKCorrelation`? (No body-composition correlation type exists —
  save as a batch via `healthStore.save([samples])`.) Units: kg
  (`.gramUnit(with:.kilo)`), `%`→`HKUnit.percent()` with value `fat/100`,
  `count()` for BMI.
- Metadata: `HKMetadataKeyWasUserEntered=false`, custom keys for impedance,
  app build, assigned user id, scale identifier.
- Per-user HealthKit (confirmed single-user): iOS HealthKit has exactly **one**
  profile per device — the device owner. There is no API to write into a second
  person's Health store. One `UserProfile` is marked `isHealthKitOwner = true`;
  **only that user's readings are written to HealthKit**. Every other user's
  readings are persisted locally and sent to HA, flagged
  `healthKitState=skipped`, and labeled in the UI as "HA-only (not this device's
  Health user)". A partner who wants HealthKit runs their own copy on their own
  phone.
- Failure → `healthKitState=failed`, kept in store for manual retry.

**HASink (optional, isolated)**
- Config in Settings: base URL, path (webhook/REST), auth header/token, enabled
  toggle. Stored in Keychain (token) + UserDefaults (url/toggle).
- POST JSON `{user, capturedAt, weightKg, bodyFatPercent, leanMassKg, bmi,
  impedanceOhms}` to the HA endpoint.
- **Strict isolation:** runs on its own async `Task`, after the HealthKit write,
  never blocks or fails the pipeline. Retry with exponential backoff (e.g.
  2s,4s,8s,16s, capped attempts), state `pending→written/failed`. Failed POSTs
  are retried on next app foreground / connectivity regain from the store.
- No PII beyond user display name; configurable.

---

## 6. Multi-user disambiguation logic

`UserResolver.resolve(weightKg) -> Resolution`:
1. Find all profiles whose `weightRangeKg` contains `weightKg`.
2. **Exactly one** → `.matched(user)` → compute + write.
3. **Zero or >1** → `.ambiguous`/`.noMatch` → store `Measurement` with
   `assignedUserID=nil`, `resolution`, **no HealthKit write yet**. Reading shows
   up in the **"Unassigned" UI queue**; user taps to pick the correct profile →
   `resolution=.manual`, then compute + write retroactively (using
   `capturedAt`).
4. Ranges are configured per user in Settings; UI should warn on overlapping or
   gapped ranges at config time (validation), but runtime still defends with the
   hold-for-confirm path.
- Rationale (locked decision): never auto-attribute — a wrong HealthKit write is
  painful to undo, so ambiguity is always human-confirmed.

---

## 7. Edge cases & failure modes

**BLE / parsing**
- Truncated / wrong-length service data (≠13 bytes) → reject, log, no crash.
- `allowDuplicates` throttled by iOS under load → rely on any stabilized frame;
  T_settle tolerant.
- Non-stabilized-only burst (user steps off early) → never finalizes; cleared by
  stale-timeout back to IDLE.
- Impedance absent on a stabilized frame (bit1 clear) → weight-only; v1 cannot
  compute fat/LBM → store partial (weight+BMI), flag for user.
- lb/catty units configured on scale → normalize to kg; surface a Settings hint
  to set the scale to kg.
- Scale RTC wrong/reset → ignore `deviceTimestamp`; use host `capturedAt`.
- Two people weigh in back-to-back within cooldown → dedupe key
  `(weight,impedance)` differs, so distinct; but rapid identical weights could
  collapse — cooldown tuned; acceptable for v1.
- Stray/other 0x181B devices → optional identifier allowlist.

**Attribution**
- Overlapping ranges / no match → Unassigned queue (§6).
- Weight near a range boundary → still single match if ranges disjoint; else
  Unassigned.

**Sinks / persistence**
- HealthKit auth denied → readings persist locally, `healthKitState=failed`;
  banner prompts re-auth via Settings → Health.
- HealthKit write throws → retained for retry.
- HA endpoint down / TLS error / 4xx-5xx → retry/backoff, never affects
  HealthKit; persistent failure surfaced in UI, retried later.
- App killed mid-pipeline → store written *before* sinks, so finalized readings
  survive and re-drive sinks on next launch.
- Non-binary/unset biological sex → block fat%/LBM compute, prompt for value.

**Always-on / foreground assumption (what breaks it)**
- Bluetooth toggled off / airplane mode → `CBCentralManager` state callback;
  UI shows "BLE unavailable", auto-resumes scan on power-on.
- App backgrounded (home button, another app, call, notification center) →
  scanning stops; **v1 mitigation:** Guided Access / Single-App Mode +
  `UIApplication.shared.isIdleTimerDisabled = true` + on-charger. Document the
  kiosk setup. App restart resumes scan in `applicationDidBecomeActive`.
- Low Power Mode / thermal throttling → scan continues but may throttle; note.
- iOS OS reboot (updates) → kiosk auto-launch not guaranteed; documented as a
  known v1 limitation.

---

## 7b. Continuous Integration (GitHub Actions)

CI exploits the plan's core/platform split: the **pure** parser and calculator
live in a SwiftPM library (`MiScaleCore`) that `swift test` runs on a macOS
runner with **no simulator and no hardware**; the SwiftUI/HealthKit/CoreBluetooth
app shell is built (not unit-run) with `xcodebuild`.

**Repo layout introduced now** (also satisfies M0/start of M1):
```
Package.swift                       # SwiftPM manifest, MiScaleCore library + test target
Sources/MiScaleCore/                # pure logic: parser, calculator, models (no UIKit/HK/CB)
Tests/MiScaleCoreTests/             # XCTest golden cases (hex fixtures, formula vectors)
.github/workflows/ci.yml            # the workflow below
```
The Xcode **app** target is added later (M0 scaffold) and depends on the
`MiScaleCore` package; CI gains an `xcodebuild build` job at that point.

**`.github/workflows/ci.yml`:**
- Triggers: `pull_request` to `main`, and `push` to `claude/**` and `main`.
- `concurrency` group per-ref to cancel superseded runs.
- Job **core-tests** (gate, runs today):
  - `runs-on: macos-14`.
  - `swift --version` (Xcode/Swift toolchain check).
  - `swift build` then `swift test --enable-code-coverage` on `MiScaleCore`.
- Job **app-build** (added with the Xcode project in M0; until then omitted /
  guarded so it doesn't fail on a missing `.xcodeproj`):
  - `xcodebuild build -scheme MiScaleApp -destination 'platform=iOS
    Simulator,name=iPhone 15'` (and `test` once UI/integration tests exist).
- Optional **lint** job: SwiftFormat/SwiftLint in `--lint` mode (non-blocking
  initially).

**Bootstrap so CI is green immediately:** scaffold `MiScaleCore` with the
`ParsedAdvertisement`/`BodyComposition` model stubs and **one real smoke test**
(e.g. a BMI golden value) so the first CI run passes; M1/M2 then fill in the
full parser + formula golden vectors behind the same green gate.

---

## 8. Milestone-ordered build plan (v1)

0. **M0a — CI + core package scaffold (this step).** Add `Package.swift`
   (`MiScaleCore` library + test target), `Sources/MiScaleCore` model stubs, one
   passing smoke test, and `.github/workflows/ci.yml` (core-tests job). CI green
   on the existing PR before any app code.
1. **M0b — App scaffold.** SwiftUI app, iOS 16 target, folders per layer,
   `Info.plist` usage strings (`NSBluetoothAlwaysUsageDescription`,
   `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`), HealthKit
   capability, app target depends on `MiScaleCore`; add `app-build` CI job. No
   logic.
2. **M1 — Pure parser + fixtures + tests.** `AdvertisementParser` with the
   verified byte/bit map; XCTest golden cases from captured/synthesized hex
   payloads (stabilized, non-stabilized, weight-removed, lb unit, bad length).
   **No hardware needed.**
3. **M2 — Pure body-comp calculator + tests.** LBM/fat%/lean/BMI with constants
   isolated; golden-value tests vs lolouk44/bodymiscale reference outputs;
   clamping tests; partial (no-impedance) path.
4. **M3a — Pure finalizer (this step).** `MeasurementFinalizer` (§3a) in
   `MiScaleCore`: time-injected finalize/debounce/dedupe state machine + tests
   replaying advert sequences. Under green CI, no hardware.
5. **M3b — BLE scanner wrapper.** `CBCentralManager` foreground scan that
   forwards `didDiscover` 0x181B service data into a per-peripheral
   `MeasurementFinalizer` and runs a `tick` timer; verify with the **real
   scale** (first hardware milestone) and a logging/console view.
5. **M4 — Persistence + pipeline.** `MeasurementStore`, wire
   scan→parse→finalize→(resolve)→store; readings durable before any sink.
6. **M5 — User profiles + resolver + Unassigned queue UI.** Profile CRUD,
   weight-range config with overlap/gap validation, manual-assign flow.
7. **M6 — HealthKit sink.** Auth flow, batched write of 4 samples, metadata,
   failure/retry, owner-user gating; verify samples land in Health app.
8. **M7 — HA sink (optional).** Settings config (Keychain token), async POST,
   backoff retry, isolation from HealthKit, retry-on-foreground.
9. **M8 — Kiosk hardening + dashboard.** Idle-timer disable, Guided Access
   setup doc, dashboard (last readings per user, sink status, BLE/HealthKit
   health indicators), manual sink-retry buttons.
10. **M9 — Field validation & polish.** Multi-day real-scale soak on the
    dedicated device; tune `T_settle`/`T_cooldown`; confirm dedupe; finalize
    flagged-constant accuracy notes.

*(v2 backlog, not built: background BLE via state restoration; full
body-composition metric suite to HA; multi-device HealthKit story.)*

---

## 9. Open questions + things to verify before implementation

**Must verify (cannot ship without):**
1. **Confirm the 0x181B byte/bit layout against REAL captured payloads** from
   the user's specific MiScale 2 firmware — capture a few weigh-ins (nRF
   Connect / a throwaway logging build) covering stabilizing → stable+impedance
   → removed. Verifies: control-bit positions (esp. impedance bit1 vs the
   "bit 14" ambiguity), weight divisor (÷200), impedance offset/range,
   timestamp reliability.
2. **Validate the fat%/LBM constants** (`c=9.25/7.25/0.8`, k coefficients) by
   comparing app output against the **Zepp/Mi Fitness app** readout for the same
   weigh-in on the same body, for both household users. Adjust flagged constants
   if they diverge.

**Resolved:**
- **HealthKit owner user:** confirmed — HealthKit is single-profile per device.
  Exactly one `UserProfile.isHealthKitOwner = true` writes to HealthKit; all
  other users are HA-only / local-only (`healthKitState=skipped`).

**Decisions to confirm with user:**
3. **leanBodyMass definition:** write the fat-derived lean mass `w*(1−fat/100)`
   (consistent with the published fat%) vs the raw regression `LBM`. (Assumed:
   fat-derived, for internal consistency.)
4. **Non-binary/unset sex:** the Xiaomi formulas are strictly male/female.
   Confirm both real users have a binary value; define UX if `.other`/`.notSet`.
5. **Persistence tech:** Codable-file vs GRDB/SQLite vs SwiftData — SwiftData
   needs iOS 17, conflicting with the iOS 16 floor. (Assumed: lightweight
   Codable/SQLite repository to keep iOS 16.)
6. **Scale unit:** confirm the scale is/should be set to **kg** (simplifies and
   matches the ÷200 path); otherwise we rely on the lb/catty normalization.
7. **HA payload contract:** exact endpoint shape (webhook vs REST sensor),
   field names, and auth the user's HA expects.

## Verification (how to test end-to-end)
- **Unit (no hardware):** `swift test` / XCTest for parser (hex fixtures) and
  calculator (golden values vs reference implementations); CI-able.
- **BLE integration:** real scale + M3 logging build; assert exactly one
  finalize per weigh-in across the stabilizing burst and the removed event.
- **HealthKit:** weigh in as the owner user → confirm 4 samples (mass, fat%,
  lean, BMI) appear in Apple Health with correct values/units/timestamp.
- **Attribution:** configure two overlapping ranges → confirm reading lands in
  Unassigned; manual-assign → confirm retroactive HealthKit write.
- **HA isolation:** point HA URL at an unreachable host → confirm HealthKit
  still writes, HA marked failed and retried on next foreground.
- **Kiosk:** Guided Access + on-charger soak; confirm scanning persists with
  screen on and idle timer disabled; confirm resume after backgrounding.
