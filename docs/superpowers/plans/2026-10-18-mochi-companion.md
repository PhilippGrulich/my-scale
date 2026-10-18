# Mochi Companion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Mochi, a squishy talking-scale companion that hosts onboarding, reacts to every weigh-in, sends smart reminders, and can be switched off entirely.

**Architecture:** All decision logic (goal direction, calendar context, stats, reaction rules, line selection, reminder timing) is pure Swift in the `MyOpenScaleCore` package under `Sources/MyOpenScaleCore/Mochi/`, unit tested with `swift test`. The app side (`App/Mochi/`) is thin: a SwiftUI-drawn `MochiView`, a `MochiCoordinator` that feeds `AppModel` data into the core and persists Mochi state in `UserDefaults`, a reminder scheduler on `UNUserNotificationCenter`, and integrations into onboarding, the weigh-in overlay, the dashboard and Settings. Message lines live in two JSON files (EN, DE) bundled with the app and validated by a core test.

**Tech Stack:** Swift 6 (core) / Swift 5 mode (app), SwiftUI, iOS 26, XCTest, UserNotifications, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-18-mochi-companion-design.md` (reference sketches in `docs/superpowers/specs/mochi-sketches/`).

## Global Constraints

- iOS 26+ app target; core package stays platform-free (no UIKit/SwiftUI/UserNotifications imports in `Sources/`).
- No network, no accounts, everything on-device.
- Every user-visible string exists in English and German (`Localization/Localizable.xcstrings` for UI copy; `MochiLines-en.json` / `MochiLines-de.json` for Mochi lines).
- kg only, local number formatting.
- Mochi is always called "Mochi"; no renaming.
- Never shame: no "careful, you gained", no "what did you eat", no diet/calorie/medical advice in any line.
- At most one reminder per day; none on a day already weighed in; Mochi off ⇒ no reminders.
- Haptics on by default with a toggle; no sounds in v1.
- Respect Reduce Motion (crossfades instead of bounces/confetti).
- Changes below 0.1 kg count as flat.
- Mochi off ⇒ app looks and behaves exactly as today.
- XcodeGen: never edit `.xcodeproj`; run `xcodegen generate` after adding files.
- Core tests: `swift test`. App build: `xcodegen generate && xcodebuild -scheme MyOpenScaleApp -destination 'platform=iOS Simulator,name=<any available iPhone>' build` (pick a name from `xcrun simctl list devices available`).

## Review Focus

1. **Several weigh-ins on one day / Watch + phone duplicates:** streaks count calendar days, not readings; the reaction compares against the latest sample *before* the new reading (ignoring samples within 60 s of it). Test in Task 3 and Task 4.
2. **No goal set:** reactions still work in "lose" direction, but no milestone/goal-reached fires and no line using `{left}`/`{percent}`/`{weeks}` is chosen. Test in Task 4 and Task 5.
3. **Usual weigh-in time near midnight / DST:** usual time is a circular median (23:50 and 00:10 → ~00:00, not noon); fire dates are built with `Calendar` date components so DST shifts keep the wall-clock time. Test in Task 6.
4. **First ever weigh-in / empty history:** no crash, reaction is `toward` (thumbs up), stats are zero/nil, no "welcome back". Test in Task 3 and Task 4.
5. **Changing the goal after milestones fired:** fired milestones and best reset; old milestones don't re-fire against the old start weight. Test in Task 4.

---

## File Structure

Core (`Sources/MyOpenScaleCore/Mochi/`):
- `WeightGoal.swift`: `GoalType`, `WeightGoal` (direction, progress, reached, better-than).
- `MochiCalendarContext.swift`: time of day, weekday flags, holidays, season, birthday.
- `MochiStats.swift`: streak, days since last weigh-in, week changes, days in range.
- `MochiReaction.swift`: `MochiPose`, `MochiEvent`, `MochiProgressState`, `MochiReactionEngine`.
- `MochiLines.swift`: `MochiLine`, `MochiSituation`, `MochiLineHistory`, `MochiMessageSelector`, template rendering.
- `ReminderPlanner.swift`: usual time, back-off stages, planned fire dates.

Tests (`Tests/MyOpenScaleCoreTests/`): `WeightGoalTests`, `MochiCalendarContextTests`, `MochiStatsTests`, `MochiReactionEngineTests`, `MochiMessageSelectorTests`, `ReminderPlannerTests`, `MochiLibraryFileTests`.

App (`App/Mochi/`):
- `MochiLines-en.json`, `MochiLines-de.json`: the line library.
- `MochiView.swift`: drawing + pose animations.
- `MochiSpeechBubble.swift`: bubble view.
- `MochiStores.swift`: `MochiSettings` + `MochiStateStore` (UserDefaults).
- `MochiCoordinator.swift`: glue between `AppModel` and core; haptics; line loading.
- `MochiReminderScheduler.swift`: schedules/cancels reminder notifications.
- `MochiWeighInView.swift`: Mochi version of the weigh-in overlay phases.
- `MochiCornerView.swift`: dashboard corner Mochi.
- `MochiSettingsSection.swift`: Settings section.
- `MochiPoseGalleryView.swift`: DEBUG-only gallery of all poses.

Modified app files: `ProfileStore.swift`, `ProfileEditorView.swift`, `TrendSummaryView.swift`, `DashboardView.swift`, `WeighInOverlayView.swift`, `RootTabView.swift`, `OnboardingView.swift`, `AppModel.swift`, `NotificationManager.swift`, `MyOpenScaleApp.swift`, `Localization/Localizable.xcstrings`.

---

### Task 1: Goal type and goal maths (core)

**Files:**
- Create: `Sources/MyOpenScaleCore/Mochi/WeightGoal.swift`
- Test: `Tests/MyOpenScaleCoreTests/WeightGoalTests.swift`

**Interfaces:**
- Produces:
  - `public enum GoalType: String, Codable, Sendable, CaseIterable { case lose, gain, maintain }`
  - `public struct WeightGoal: Equatable, Sendable { public var type: GoalType; public var targetKg: Double?; public var startKg: Double?; public var toleranceKg: Double /* default 1.0 */ ; public init(type:targetKg:startKg:toleranceKg:) }`
  - `public static let noiseKg = 0.1` on `WeightGoal`
  - `func isInBand(_ kg: Double) -> Bool` (maintain only; false if no target)
  - `func isToward(fromKg: Double, toKg: Double) -> Bool` (flat, |Δ| < noiseKg, counts as toward)
  - `func isReached(_ kg: Double) -> Bool` (lose: ≤ target; gain: ≥ target; maintain: in band; false if no target)
  - `func isBetter(_ kg: Double, than best: Double) -> Bool` (lose: kg < best − noise; gain: kg > best + noise; maintain: always false)
  - `func progressFraction(_ kg: Double) -> Double?` (0…1 clamped, from start to target; nil for maintain, missing target/start, or start == target)
  - `func signature() -> String` (e.g. `"lose|72.0|80.0"`; changes whenever type/target/start change; used to reset progress state)

- [ ] **Step 1: Write the failing tests**

```swift
func testLoseDirection() {
    let g = WeightGoal(type: .lose, targetKg: 70, startKg: 80)
    XCTAssertTrue(g.isToward(fromKg: 75, toKg: 74.5))
    XCTAssertFalse(g.isToward(fromKg: 75, toKg: 75.4))
    XCTAssertTrue(g.isToward(fromKg: 75, toKg: 75.05))   // flat counts as toward
    XCTAssertTrue(g.isReached(70)); XCTAssertFalse(g.isReached(70.2))
    XCTAssertEqual(g.progressFraction(75)!, 0.5, accuracy: 1e-9)
    XCTAssertEqual(g.progressFraction(90)!, 0)            // clamped
    XCTAssertTrue(g.isBetter(74.8, than: 75)); XCTAssertFalse(g.isBetter(74.95, than: 75))
}
func testGainDirection() {
    let g = WeightGoal(type: .gain, targetKg: 70, startKg: 60)
    XCTAssertTrue(g.isToward(fromKg: 62, toKg: 62.4))
    XCTAssertFalse(g.isToward(fromKg: 62, toKg: 61.5))
    XCTAssertTrue(g.isReached(70.1))
    XCTAssertEqual(g.progressFraction(65)!, 0.5, accuracy: 1e-9)
    XCTAssertTrue(g.isBetter(62.2, than: 62))
}
func testMaintainBandAndDirection() {
    let g = WeightGoal(type: .maintain, targetKg: 70, startKg: nil)   // tolerance defaults to 1.0
    XCTAssertTrue(g.isInBand(70.9)); XCTAssertFalse(g.isInBand(71.2))
    XCTAssertTrue(g.isToward(fromKg: 72, toKg: 71.5))    // outside band, moving back
    XCTAssertFalse(g.isToward(fromKg: 72, toKg: 72.5))
    XCTAssertTrue(g.isToward(fromKg: 70.2, toKg: 70.8))  // inside band = on goal
    XCTAssertNil(g.progressFraction(70.5))
    XCTAssertFalse(g.isBetter(69, than: 70))
}
func testNoTargetBehavesAsDirectionOnly() {
    let g = WeightGoal(type: .lose, targetKg: nil, startKg: nil)
    XCTAssertTrue(g.isToward(fromKg: 80, toKg: 79.5))
    XCTAssertFalse(g.isReached(10))
    XCTAssertNil(g.progressFraction(79))
}
func testSignatureChangesWithGoal() {
    let a = WeightGoal(type: .lose, targetKg: 70, startKg: 80)
    XCTAssertNotEqual(a.signature(), WeightGoal(type: .lose, targetKg: 69, startKg: 80).signature())
    XCTAssertNotEqual(a.signature(), WeightGoal(type: .gain, targetKg: 70, startKg: 80).signature())
}
```

- [ ] **Step 2: Run `swift test --filter WeightGoalTests`.** Expected: FAIL, `WeightGoal` not found.
- [ ] **Step 3: Implement `WeightGoal.swift`** with the interface above. For maintain outside the band, "toward" means the distance to the band shrinks (or changes by < noise).
- [ ] **Step 4: Run `swift test --filter WeightGoalTests`.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(core): goal type and goal direction maths`.

---

### Task 2: Calendar context (core)

**Files:**
- Create: `Sources/MyOpenScaleCore/Mochi/MochiCalendarContext.swift`
- Test: `Tests/MyOpenScaleCoreTests/MochiCalendarContextTests.swift`

**Interfaces:**
- Produces:
  - `public enum TimeOfDay: String, Codable, Sendable { case earlyMorning /*04–07*/, morning /*07–11*/, midday /*11–14*/, afternoon /*14–18*/, evening /*18–22*/, night /*22–04*/ }`
  - `public enum Holiday: String, Codable, Sendable { case christmas, newYear, easter }`
  - `public enum Season: String, Codable, Sendable { case spring, summer, autumn, winter }` (northern hemisphere by month: Mar–May spring, …)
  - `public struct MochiCalendarContext: Equatable, Sendable { timeOfDay; weekday: Int /*1=Sun…7=Sat, Calendar convention*/; isWeekend; isMonday; isFriday; holiday: Holiday?; season; isBirthday }`
  - `public static func make(now: Date, dateOfBirth: Date?, calendar: Calendar, regionCode: String?) -> MochiCalendarContext`
  - `public static func easterSunday(year: Int, calendar: Calendar) -> Date` (Anonymous Gregorian algorithm)
  - `public var tags: Set<String>`: the context as line-filter tags: `"time:<timeOfDay>"`, `"weekday:<1…7>"`, `"weekend"`, `"monday"`, `"friday"`, `"holiday:<holiday>"`, `"season:<season>"`, `"birthday"`.

Holiday windows: christmas Dec 24–26 for regions `DE`, `AT`, `CH`, otherwise Dec 25–26; newYear Dec 31–Jan 1; easter Good Friday through Easter Monday.

- [ ] **Step 1: Write the failing tests** (UTC gregorian calendar, fixed dates):

```swift
func testEasterDates() {
    XCTAssertEqual(ymd(MochiCalendarContext.easterSunday(year: 2026, calendar: cal)), "2026-04-05")
    XCTAssertEqual(ymd(MochiCalendarContext.easterSunday(year: 2027, calendar: cal)), "2027-03-28")
}
func testMondayMorning() {
    let c = MochiCalendarContext.make(now: date("2026-10-19 07:30"), dateOfBirth: nil, calendar: cal, regionCode: "DE")
    XCTAssertTrue(c.isMonday); XCTAssertFalse(c.isWeekend)
    XCTAssertEqual(c.timeOfDay, .morning); XCTAssertEqual(c.season, .autumn)
    XCTAssertTrue(c.tags.isSuperset(of: ["monday", "time:morning", "season:autumn", "weekday:2"]))
}
func testChristmasEveIsRegional() {
    XCTAssertEqual(MochiCalendarContext.make(now: date("2026-12-24 10:00"), dateOfBirth: nil, calendar: cal, regionCode: "DE").holiday, .christmas)
    XCTAssertNil(MochiCalendarContext.make(now: date("2026-12-24 10:00"), dateOfBirth: nil, calendar: cal, regionCode: "US").holiday)
}
func testEasterMondayAndNewYear() {
    XCTAssertEqual(MochiCalendarContext.make(now: date("2026-04-06 09:00"), dateOfBirth: nil, calendar: cal, regionCode: nil).holiday, .easter)
    XCTAssertEqual(MochiCalendarContext.make(now: date("2027-01-01 09:00"), dateOfBirth: nil, calendar: cal, regionCode: nil).holiday, .newYear)
}
func testBirthdayIgnoresYear() {
    let c = MochiCalendarContext.make(now: date("2026-03-14 08:00"), dateOfBirth: date("1990-03-14 00:00"), calendar: cal, regionCode: nil)
    XCTAssertTrue(c.isBirthday); XCTAssertTrue(c.tags.contains("birthday"))
}
func testNightWrapsMidnight() {
    XCTAssertEqual(MochiCalendarContext.make(now: date("2026-10-19 02:00"), dateOfBirth: nil, calendar: cal, regionCode: nil).timeOfDay, .night)
}
```

(`date(_:)`/`ymd(_:)` are small test helpers on a UTC `DateFormatter`.)

- [ ] **Step 2: Run `swift test --filter MochiCalendarContextTests`.** Expected: FAIL.
- [ ] **Step 3: Implement `MochiCalendarContext.swift`.** Birthday compares month+day only; Feb 29 birthdays match Feb 28 in non-leap years.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(core): Mochi calendar context`.

---

### Task 3: Weigh-in stats (core)

**Files:**
- Create: `Sources/MyOpenScaleCore/Mochi/MochiStats.swift`
- Test: `Tests/MyOpenScaleCoreTests/MochiStatsTests.swift`

**Interfaces:**
- Consumes: `WeightSample` (existing), `WeightGoal` (Task 1).
- Produces:
  - `public struct MochiStats: Equatable, Sendable { streakDays: Int; daysSinceLastWeighIn: Int?; weekChangeKg: Double?; previousWeekChangeKg: Double?; daysInRangeStreak: Int; daysUsingApp: Int }`
  - `public static func compute(history: [WeightSample], now: Date, firstLaunch: Date, goal: WeightGoal, calendar: Calendar) -> MochiStats`

Definitions:
- `streakDays`: consecutive calendar days with ≥1 sample, ending today, or ending yesterday if today has none yet. 0 for empty history.
- `daysSinceLastWeighIn`: whole calendar days between the latest sample's day and today (0 = today); nil if empty.
- `weekChangeKg`: mean of samples in `(now − 7 d, now]` minus mean of samples in `(now − 14 d, now − 7 d]`; nil if either window is empty. `previousWeekChangeKg`: the same, shifted back one week.
- `daysInRangeStreak` (maintain only, else 0): consecutive days ending at the latest sample day whose daily mean is in the band; days without samples don't break it.
- `daysUsingApp`: calendar days from `firstLaunch` to `now`.

- [ ] **Step 1: Write the failing tests**

```swift
func testStreakCountsDaysNotReadings() {
    let h = [s("2026-10-16 07:00", 80), s("2026-10-17 07:00", 79.8), s("2026-10-18 07:00", 79.7), s("2026-10-18 07:00:30", 79.7)]
    XCTAssertEqual(stats(h, now: "2026-10-18 20:00").streakDays, 3)
}
func testStreakSurvivesUntilTodaysWeighIn() {
    let h = [s("2026-10-16 07:00", 80), s("2026-10-17 07:00", 79.8)]
    XCTAssertEqual(stats(h, now: "2026-10-18 06:00").streakDays, 2)
    XCTAssertEqual(stats(h, now: "2026-10-19 06:00").streakDays, 0)
}
func testEmptyHistory() {
    let st = stats([], now: "2026-10-18 06:00")
    XCTAssertEqual(st.streakDays, 0); XCTAssertNil(st.daysSinceLastWeighIn); XCTAssertNil(st.weekChangeKg)
}
func testDaysSinceAndWeekChange() {
    let h = [s("2026-10-05 07:00", 81), s("2026-10-08 07:00", 80.6), s("2026-10-13 07:00", 80), s("2026-10-15 07:00", 79.6)]
    let st = stats(h, now: "2026-10-18 09:00")
    XCTAssertEqual(st.daysSinceLastWeighIn, 3)
    XCTAssertEqual(st.weekChangeKg!, (80 + 79.6)/2 - (81 + 80.6)/2, accuracy: 1e-9)
}
func testDaysInRangeForMaintain() {
    let g = WeightGoal(type: .maintain, targetKg: 70, startKg: nil)
    let h = [s("2026-10-14 07:00", 72), s("2026-10-15 07:00", 70.5), s("2026-10-17 07:00", 69.6), s("2026-10-18 07:00", 70.2)]
    XCTAssertEqual(MochiStats.compute(history: h, now: d("2026-10-18 09:00"), firstLaunch: d("2026-10-01 00:00"), goal: g, calendar: cal).daysInRangeStreak, 3)
}
```

(`s(_:_:)` builds a `WeightSample`; `stats(_:now:)` uses a lose goal with no target and `firstLaunch` 2026-10-01; UTC calendar.)

- [ ] **Step 2: Run `swift test --filter MochiStatsTests`.** Expected: FAIL.
- [ ] **Step 3: Implement `MochiStats.compute`.**
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(core): Mochi weigh-in stats`.

---

### Task 4: Reaction engine (core)

**Files:**
- Create: `Sources/MyOpenScaleCore/Mochi/MochiReaction.swift`
- Test: `Tests/MyOpenScaleCoreTests/MochiReactionEngineTests.swift`

**Interfaces:**
- Consumes: `WeightGoal` (Task 1), `MochiStats` (Task 3), `WeightSample`.
- Produces:
  - `public enum MochiPose: String, Codable, Sendable, CaseIterable { case idle, helloWave, thumbsUp, doubleThumbs, confetti, selfHug, bellRing, snoozing, sadWave, waiting, squishing, birthday }`
  - `public enum MochiEvent: Equatable, Codable, Sendable { case goalReached, milestonePercent(Int), milestoneKg(Int), newBest, streak(Int), goodWeek, daysInRange(Int), toward, away, notYou }`
  - `public var lineEvent: String` on `MochiEvent`: `"goalReached"`, `"milestonePercent"`, `"milestoneKg"`, `"newBest"`, `"streak"`, `"goodWeek"`, `"daysInRange"`, `"toward"`, `"away"`, `"notYou"`.
  - `public struct MochiReaction: Equatable, Sendable { event: MochiEvent; pose: MochiPose; isWelcomeBack: Bool; changeKg: Double? }`
  - `public struct MochiProgressState: Codable, Equatable, Sendable { goalSignature: String; bestKg: Double?; firedMilestones: Set<String>; lastStreakCelebrated: Int; lastGoodWeekStart: Date?; wasOutsideBand: Bool; goalReachedFired: Bool; firedRangeStreaks: Set<Int> }` with `public static func fresh(for goal: WeightGoal) -> MochiProgressState` (bestKg = goal.startKg).
  - `public enum MochiReactionEngine { public static func react(newKg: Double, at date: Date, history: [WeightSample], goal: WeightGoal, state: MochiProgressState, calendar: Calendar) -> (MochiReaction, MochiProgressState) }`
  - `public static func notYou() -> MochiReaction` (event `.notYou`, pose `.idle`, no state change).

Algorithm (first match wins; all decisions update state even when a higher rule wins):
1. If `state.goalSignature != goal.signature()`, start from `.fresh(for: goal)`.
2. `prior` = history samples with `date < at − 60 s`; `previousKg` = latest of `prior`; `changeKg = newKg − previousKg` (nil if none).
3. Stats = `MochiStats.compute(history: prior + [new sample], …)`; `isWelcomeBack` = stats of `prior` alone have `daysSinceLastWeighIn ≥ 7`.
4. Goal reached: lose/gain: `goal.isReached(newKg) && !goalReachedFired` → set fired. Maintain: `isInBand(newKg) && state.wasOutsideBand` → event; update `wasOutsideBand = !isInBand(newKg)` every time. Pose `.confetti`.
5. Milestones (lose/gain with target+start): crossed percent marks `25/50/75` and whole-kg marks (`|start − newKg|` floored, ≥ 1) not yet in `firedMilestones` (ids `"pct:25"`, `"kg:3"`). Mark all crossed as fired; event = highest crossed percent if any, else highest kg. Pose `.confetti`.
6. Maintain: `daysInRangeStreak` reached 7, 30, or 100 and not in `firedRangeStreaks` → `.daysInRange(n)`, pose `.doubleThumbs`.
7. New best: `bestKg` nil → set to newKg, no event; else `goal.isBetter(newKg, than: bestKg)` → `.newBest`, update best. Pose `.doubleThumbs`.
8. Streak: `streakDays ∈ {3, 5, 7, 10, 14, 21, 30}` or a multiple of 30, and `> lastStreakCelebrated` → `.streak(n)`; reset `lastStreakCelebrated` to 0 when the streak drops below it. Pose `.doubleThumbs`. (Plan decision: celebrate streak milestones, not every day of a streak, so the "Nailed it!" pose stays the common one.)
9. Good week: `weekChangeKg` toward goal by ≥ 0.3 kg (using `goal.isToward` and magnitude), at most once per calendar week (`lastGoodWeekStart`). Pose `.doubleThumbs`.
10. `changeKg == nil` or `goal.isToward(previousKg, newKg)` → `.toward`, pose `.thumbsUp`; else `.away`, pose `.selfHug`.
11. If `isWelcomeBack` and the event is `.toward`/`.away`, pose becomes `.helloWave`.

- [ ] **Step 1: Write the failing tests**

```swift
func testFirstEverWeighInIsThumbsUp() {
    let (r, _) = react(80, history: [], goal: lose(70, start: 80))
    XCTAssertEqual(r.event, .toward); XCTAssertEqual(r.pose, .thumbsUp); XCTAssertFalse(r.isWelcomeBack); XCTAssertNil(r.changeKg)
}
func testUpDayGetsHugNotShame() {
    let (r, _) = react(80.6, history: [s(daysAgo: 1, 80)], goal: lose(70, start: 82))
    XCTAssertEqual(r.event, .away); XCTAssertEqual(r.pose, .selfHug)
}
func testGainerUpDayIsToward() {
    let (r, _) = react(60.6, history: [s(daysAgo: 1, 60)], goal: gain(70, start: 59))
    XCTAssertEqual(r.event, .toward)
}
func testHalfwayMilestoneFiresOnce() {
    var st = MochiProgressState.fresh(for: lose(70, start: 80))
    let (r1, st1) = react(74.9, history: [s(daysAgo: 1, 75.3)], goal: lose(70, start: 80), state: st)
    XCTAssertEqual(r1.event, .milestonePercent(50)); XCTAssertEqual(r1.pose, .confetti)
    st = st1
    let (r2, _) = react(74.8, history: [s(daysAgo: 1, 74.9)], goal: lose(70, start: 80), state: st)
    XCTAssertNotEqual(r2.event, .milestonePercent(50))
}
func testGoalReachedBeatsEverything() {
    let (r, _) = react(69.9, history: [s(daysAgo: 1, 70.3)], goal: lose(70, start: 80))
    XCTAssertEqual(r.event, .goalReached)
}
func testNoGoalNeverFiresMilestones() {
    let g = WeightGoal(type: .lose, targetKg: nil, startKg: nil)
    let (r, _) = react(70, history: [s(daysAgo: 1, 75)], goal: g)
    XCTAssertFalse([.goalReached, .milestonePercent(50), .milestoneKg(5)].contains(r.event))
}
func testChangingGoalResetsProgress() {
    let old = lose(70, start: 80)
    let (_, st) = react(74.9, history: [s(daysAgo: 1, 75.3)], goal: old)
    let newGoal = lose(65, start: 74.9)
    let (r, st2) = react(74.8, history: [s(daysAgo: 1, 74.9)], goal: newGoal, state: st)
    XCTAssertTrue(st.firedMilestones.contains("pct:50"))
    XCTAssertEqual(st2.goalSignature, newGoal.signature())
    XCTAssertFalse(st2.firedMilestones.contains("pct:50"))
    XCTAssertNotEqual(r.event, .milestonePercent(50))
}
func testSameDayDuplicateIsIgnoredForChange() {
    // Watch already wrote this weigh-in 20 s earlier.
    let now = base
    let (r, _) = MochiReactionEngine.react(newKg: 79.0, at: now,
        history: [s(daysAgo: 1, 80), WeightSample(id: UUID(), date: now.addingTimeInterval(-20), weightKg: 79.0)],
        goal: lose(70, start: 82), state: .fresh(for: lose(70, start: 82)), calendar: cal)
    XCTAssertEqual(r.changeKg!, -1.0, accuracy: 1e-9)
}
func testWelcomeBackWaves() {
    let (r, _) = react(80, history: [s(daysAgo: 9, 80.2)], goal: lose(70, start: 82))
    XCTAssertTrue(r.isWelcomeBack); XCTAssertEqual(r.pose, .helloWave)
}
func testStreakCelebratedAtThree() {
    let (r, _) = react(79.9, history: [s(daysAgo: 2, 80.1), s(daysAgo: 1, 80.0)], goal: lose(70, start: 79))
    XCTAssertEqual(r.event, .streak(3))
}
func testMaintainReentryIsGoalReached() {
    let g = WeightGoal(type: .maintain, targetKg: 70, startKg: nil)
    var st = MochiProgressState.fresh(for: g)
    (_, st) = react(71.5, history: [s(daysAgo: 1, 71.4)], goal: g, state: st)
    let (r, _) = react(70.8, history: [s(daysAgo: 1, 71.5)], goal: g, state: st)
    XCTAssertEqual(r.event, .goalReached)
}
```

(Helpers: `lose(_:start:)`, `gain(_:start:)`, `s(daysAgo:_:)` relative to a fixed `base` at 07:00 UTC, `react(_:history:goal:state:)` defaulting `state` to `.fresh(for: goal)`. In `testStreakCelebratedAtThree` the start weight 79 is below every reading, so no milestone, new best or goal fires first.)

- [ ] **Step 2: Run `swift test --filter MochiReactionEngineTests`.** Expected: FAIL.
- [ ] **Step 3: Implement `MochiReaction.swift`** per the algorithm.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(core): Mochi reaction engine`.

---

### Task 5: Line model, selection and rendering (core)

**Files:**
- Create: `Sources/MyOpenScaleCore/Mochi/MochiLines.swift`
- Test: `Tests/MyOpenScaleCoreTests/MochiMessageSelectorTests.swift`

**Interfaces:**
- Consumes: `GoalType` (Task 1), `MochiCalendarContext.tags` (Task 2).
- Produces:
  - `public struct MochiLine: Codable, Equatable, Sendable { id: String; text: String; events: [String]; goals: [GoalType]?; tags: [String]?; minStreak: Int? }` (a line matches when its event matches, its `goals` (if any) contain the goal type, all its `tags` are in the situation's tags, and `minStreak` ≤ streak).
  - `public struct MochiLibrary: Codable, Sendable { version: Int; lines: [MochiLine] }`
  - `public struct MochiSituation: Sendable { event: String; goalType: GoalType; tags: Set<String>; streakDays: Int; values: [String: String] }`
  - `public struct MochiLineHistory: Codable, Equatable, Sendable { used: [String: Date] }` with `mutating func record(_ id: String, at: Date)` (drops entries older than 60 days)
  - `public enum MochiMessageSelector { public static let noRepeatDays = 14; public static func select(from lines: [MochiLine], situation: MochiSituation, history: MochiLineHistory, now: Date, random: inout some RandomNumberGenerator) -> (line: MochiLine, text: String)? }`
  - `public static func render(_ template: String, values: [String: String]) -> String?` (substitutes `{key}`; nil if any placeholder has no value)
  - `public static func placeholders(in template: String) -> Set<String>`

Selection: candidates = matching lines whose placeholders are all available; score = `(goals != nil ? 1 : 0) + (tags?.count ?? 0) + (minStreak != nil ? 1 : 0)`; keep the highest score that still has a line not used within `noRepeatDays`; if every candidate at every score was used recently, take the least recently used of the top score. Pick uniformly at random among the kept lines.

Allowed placeholder keys (document in the file): `name`, `weight`, `change`, `left`, `percent`, `streak`, `weeks`, `days`, `target`.

- [ ] **Step 1: Write the failing tests**

```swift
func testMoreSpecificLineWins() {
    let lines = [line("a", "Nice!", events: ["toward"]),
                 line("b", "Monday magic!", events: ["toward"], tags: ["monday"])]
    let r = select(lines, event: "toward", tags: ["monday", "time:morning"])
    XCTAssertEqual(r?.line.id, "b")
}
func testMissingPlaceholderSkipsLine() {
    let lines = [line("a", "Only {left} to go!", events: ["toward"]), line("b", "Nice!", events: ["toward"])]
    XCTAssertEqual(select(lines, event: "toward", values: [:])?.line.id, "b")
}
func testGoalFilter() {
    let lines = [line("g", "Growing strong 💪", events: ["toward"], goals: [.gain]), line("x", "Nice!", events: ["toward"])]
    XCTAssertEqual(select(lines, event: "toward", goal: .lose)?.line.id, "x")
    XCTAssertEqual(select(lines, event: "toward", goal: .gain)?.line.id, "g")
}
func testNoRepeatWithinTwoWeeks() {
    let lines = [line("a", "A", events: ["toward"]), line("b", "B", events: ["toward"])]
    var h = MochiLineHistory(used: [:]); h.record("a", at: now.addingTimeInterval(-3 * 86_400))
    for _ in 0..<20 { XCTAssertEqual(select(lines, event: "toward", history: h)?.line.id, "b") }
}
func testFallsBackToLeastRecentlyUsed() {
    let lines = [line("a", "A", events: ["toward"]), line("b", "B", events: ["toward"])]
    var h = MochiLineHistory(used: [:])
    h.record("a", at: now.addingTimeInterval(-2 * 86_400)); h.record("b", at: now.addingTimeInterval(-1 * 86_400))
    XCTAssertEqual(select(lines, event: "toward", history: h)?.line.id, "a")
}
func testRender() {
    XCTAssertEqual(MochiMessageSelector.render("Hi {name}, {change} kg!", values: ["name": "Philipp", "change": "−0,6"]), "Hi Philipp, −0,6 kg!")
    XCTAssertNil(MochiMessageSelector.render("{left} left", values: [:]))
}
func testMinStreak() {
    let lines = [line("s", "{streak} days!", events: ["home"], minStreak: 3), line("h", "Hi!", events: ["home"])]
    XCTAssertEqual(select(lines, event: "home", streak: 1, values: ["streak": "1"])?.line.id, "h")
    XCTAssertEqual(select(lines, event: "home", streak: 4, values: ["streak": "4"])?.line.id, "s")
}
```

(Helpers build lines/situations; `select` uses a seeded generator, e.g. a small SplitMix64 struct in the test file.)

- [ ] **Step 2: Run `swift test --filter MochiMessageSelectorTests`.** Expected: FAIL.
- [ ] **Step 3: Implement `MochiLines.swift`.**
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(core): Mochi line selection and rendering`.

---

### Task 6: Reminder planner (core)

**Files:**
- Create: `Sources/MyOpenScaleCore/Mochi/ReminderPlanner.swift`
- Test: `Tests/MyOpenScaleCoreTests/ReminderPlannerTests.swift`

**Interfaces:**
- Consumes: `WeightSample`.
- Produces:
  - `public enum ReminderMode: String, Codable, Sendable { case smart, fixed }`
  - `public enum ReminderStage: Int, Codable, Sendable, CaseIterable { case day1 = 1, day2 = 2, day4 = 4, day8 = 8, weekly = 0 }` with `public var lineEvent: String` (`"reminder1"`, `"reminder2"`, `"reminder4"`, `"reminder8"`, `"reminderWeekly"`)
  - `public struct PlannedReminder: Equatable, Sendable { fireDate: Date; stage: ReminderStage }`
  - `public enum ReminderPlanner { public static let defaultMinuteOfDay = 8 * 60; public static func usualMinuteOfDay(history: [WeightSample], calendar: Calendar, sampleCount: Int = 10) -> Int?; public static func plan(lastWeighIn: Date?, now: Date, mode: ReminderMode, minuteOfDay: Int, count: Int = 8, calendar: Calendar) -> [PlannedReminder] }`

Rules:
- `usualMinuteOfDay`: circular median of the minute-of-day of the latest `sampleCount` samples (pick the sample minute minimising the sum of circular distances); nil when empty.
- Smart: offsets from the last weigh-in's calendar day: +1, +2, +4, +8, then +15, +22, +29 … (weekly after day 8), each at `minuteOfDay`; only dates after `now`; first `count` of them. With no weigh-in ever: daily-style start at the next `minuteOfDay` after now with stage `.day1`, then follow the same offsets from today.
- Fixed: every day at `minuteOfDay`, starting the day after the last weigh-in's day (so never on a weigh-in day), stage `.day1` for the first, `.day2` for the second, and so on up to `.weekly` (stage only picks the tone).
- At most one per calendar day (true by construction; test it).
- Build each date with `calendar.date(bySettingHour:minute:second:of:)` on the target day so DST keeps the wall-clock time.

- [ ] **Step 1: Write the failing tests**

```swift
func testSmartBackoffOffsets() {
    let p = ReminderPlanner.plan(lastWeighIn: d("2026-10-18 07:10"), now: d("2026-10-18 07:15"), mode: .smart, minuteOfDay: 7*60+10, count: 6, calendar: berlin)
    XCTAssertEqual(p.map { ymdhm($0.fireDate) }, ["2026-10-19 07:10", "2026-10-20 07:10", "2026-10-22 07:10", "2026-10-26 07:10", "2026-11-02 07:10", "2026-11-09 07:10"])
    XCTAssertEqual(p.map(\.stage), [.day1, .day2, .day4, .day8, .weekly, .weekly])
}
func testSkipsPastReminders() {
    let p = ReminderPlanner.plan(lastWeighIn: d("2026-10-10 07:00"), now: d("2026-10-13 09:00"), mode: .smart, minuteOfDay: 420, count: 2, calendar: berlin)
    XCTAssertEqual(p.map { ymdhm($0.fireDate) }, ["2026-10-14 07:00", "2026-10-18 07:00"])
}
func testDSTKeepsWallClockTime() {   // Europe/Berlin falls back on 2026-10-25
    let p = ReminderPlanner.plan(lastWeighIn: d("2026-10-24 07:00"), now: d("2026-10-24 08:00"), mode: .smart, minuteOfDay: 420, count: 2, calendar: berlin)
    XCTAssertEqual(p.map { ymdhm($0.fireDate) }, ["2026-10-25 07:00", "2026-10-26 07:00"])
}
func testFixedNeverOnWeighInDayAndOncePerDay() {
    let p = ReminderPlanner.plan(lastWeighIn: d("2026-10-18 06:00"), now: d("2026-10-18 06:05"), mode: .fixed, minuteOfDay: 20*60, count: 3, calendar: berlin)
    XCTAssertEqual(p.map { ymdhm($0.fireDate) }, ["2026-10-19 20:00", "2026-10-20 20:00", "2026-10-21 20:00"])
    XCTAssertEqual(Set(p.map { ymd($0.fireDate) }).count, p.count)
}
func testUsualTimeIsCircularMedian() {
    let h = ["2026-10-14 23:50", "2026-10-15 23:55", "2026-10-16 00:05", "2026-10-17 00:10", "2026-10-18 12:00"].map { s($0, 80) }
    let m = ReminderPlanner.usualMinuteOfDay(history: h, calendar: berlin)!
    XCTAssertTrue(m >= 23*60+50 || m <= 10, "got \(m)")
}
func testUsualTimeEmpty() { XCTAssertNil(ReminderPlanner.usualMinuteOfDay(history: [], calendar: berlin)) }
```

(`berlin` = gregorian calendar in `Europe/Berlin`; `d`/`ymdhm` format in that zone.)

- [ ] **Step 2: Run `swift test --filter ReminderPlannerTests`.** Expected: FAIL.
- [ ] **Step 3: Implement `ReminderPlanner.swift`.**
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(core): Mochi reminder planner`.

---

### Task 7: The line library (EN + DE) and its validation test

**Files:**
- Create: `App/Mochi/MochiLines-en.json`, `App/Mochi/MochiLines-de.json`
- Test: `Tests/MyOpenScaleCoreTests/MochiLibraryFileTests.swift`

**Interfaces:**
- Consumes: `MochiLibrary`, `MochiLine`, `MochiMessageSelector.placeholders` (Task 5).
- Produces: two JSON files decoding as `MochiLibrary`, same line `id`s in both languages (a DE line with id `x` is the translation of the EN line `x`, same filters).

Event coverage (minimum lines **per language**; `*` = needs ≥ 2 per goal type via `goals` filters or goal-neutral lines):

| Event | Min | Notes |
|---|---|---|
| `toward`* | 25 | incl. `monday`, `weekend`, `friday`, `time:*`, `season:*`, `holiday:*` variants |
| `away`* | 20 | comfort only; incl. `monday` ("Weekends happen! Fresh week, let's go 💪") |
| `newBest`* | 8 | |
| `streak` | 8 | use `{streak}` |
| `goodWeek`* | 6 | |
| `daysInRange` | 4 | maintain only, `{days}` |
| `milestonePercent` | 6 | `{percent}` |
| `milestoneKg` | 6 | `{change}` or `{weeks}` |
| `goalReached`* | 6 | |
| `welcomeBack` | 8 | combined with the reaction line (see Task 9) |
| `notYou` | 4 | neutral, no goal talk |
| `home` | 30 | greetings by `time:*`, `weekday`, holidays; `{streak}` with `minStreak`, `{left}`/`{weeks}` lines |
| `homeIdle` | 6 | snoozing state, gentle |
| `birthday` | 4 | no weight talk |
| `anniversary` | 4 | `{days}` app-usage milestones (30/100/365 days) |
| `saved` | 6 | background notification body, `{weight}` |
| `reminder1`, `reminder2`, `reminder4`, `reminder8`, `reminderWeekly` | 5 each | tone softens with the stage |

Copy rules (from the spec): always encouraging, playful, cute; emojis welcome; never shaming; no diet/calorie/medical advice; gainers never hear "careful, you gained"; Mochi is "Mochi". Lines may use `{name}`. German uses informal "du".

- [ ] **Step 1: Write the failing test** (reads the files relative to `#filePath`: `../../App/Mochi/MochiLines-<lang>.json`):

```swift
func testBothLanguagesDecodeAndShareIDs() throws {
    let en = try load("en"), de = try load("de")
    XCTAssertEqual(Set(en.lines.map(\.id)), Set(de.lines.map(\.id)))
    XCTAssertEqual(en.lines.count, Set(en.lines.map(\.id)).count, "duplicate ids")
    XCTAssertGreaterThanOrEqual(en.lines.count, 150)
}
func testFiltersMatchAcrossLanguages() throws {
    let de = Dictionary(uniqueKeysWithValues: try load("de").lines.map { ($0.id, $0) })
    for l in try load("en").lines {
        let t = try XCTUnwrap(de[l.id])
        XCTAssertEqual([l.events, l.tags ?? []], [t.events, t.tags ?? []], l.id)
        XCTAssertEqual(l.goals, t.goals, l.id); XCTAssertEqual(l.minStreak, t.minStreak, l.id)
        XCTAssertEqual(MochiMessageSelector.placeholders(in: l.text), MochiMessageSelector.placeholders(in: t.text), l.id)
    }
}
func testOnlyKnownPlaceholders() throws {
    let allowed: Set = ["name", "weight", "change", "left", "percent", "streak", "weeks", "days", "target"]
    for lang in ["en", "de"] { for l in try load(lang).lines {
        XCTAssertTrue(MochiMessageSelector.placeholders(in: l.text).isSubset(of: allowed), "\(lang) \(l.id)")
    } }
}
func testEventCoverage() throws {
    let minimums: [String: Int] = ["toward": 25, "away": 20, "newBest": 8, "streak": 8, "goodWeek": 6, "daysInRange": 4,
        "milestonePercent": 6, "milestoneKg": 6, "goalReached": 6, "welcomeBack": 8, "notYou": 4, "home": 30, "homeIdle": 6,
        "birthday": 4, "anniversary": 4, "saved": 6, "reminder1": 5, "reminder2": 5, "reminder4": 5, "reminder8": 5, "reminderWeekly": 5]
    let en = try load("en")
    for (event, min) in minimums { XCTAssertGreaterThanOrEqual(en.lines.filter { $0.events.contains(event) }.count, min, event) }
}
func testEveryGoalTypeHasPlaceholderFreeFallback() throws {
    // With no values at all, every reaction event must still find a line for every goal type.
    for event in ["toward", "away", "newBest", "goodWeek", "goalReached", "notYou", "home"] {
        for goal in GoalType.allCases where !(goal == .maintain && event == "newBest") {
            var rng = SystemRandomNumberGenerator()
            let s = MochiSituation(event: event, goalType: goal, tags: [], streakDays: 0, values: [:])
            XCTAssertNotNil(MochiMessageSelector.select(from: try load("en").lines, situation: s, history: .init(used: [:]), now: Date(), random: &rng), "\(event)/\(goal)")
        }
    }
}
func testNoShamingWords() throws {
    let banned = ["calorie", "kalorie", "diet", "diät", "careful", "vorsicht", "what did you eat", "was hast du gegessen", "fat", "fett"]
    for lang in ["en", "de"] { for l in try load(lang).lines {
        let t = l.text.lowercased()
        XCTAssertFalse(banned.contains { t.contains($0) }, "\(lang) \(l.id): \(l.text)")
    } }
}
```

- [ ] **Step 2: Run `swift test --filter MochiLibraryFileTests`.** Expected: FAIL (files missing).
- [ ] **Step 3: Write `MochiLines-en.json`** meeting the coverage table and copy rules (ids like `toward.monday.1`).
- [ ] **Step 4: Write `MochiLines-de.json`** as the German translation, same ids and filters.
- [ ] **Step 5: Run `swift test`.** Expected: all tests PASS.
- [ ] **Step 6: Commit** `feat: Mochi line library (EN/DE)`.

---

### Task 8: Goal type in the profile, Settings goal section, trend colours

**Files:**
- Modify: `App/ProfileStore.swift` (`StoredProfile`)
- Create: `App/GoalFieldsView.swift`
- Modify: `App/ProfileEditorView.swift:18-32` (replace the Goal section with `GoalFieldsView`)
- Modify: `App/TrendSummaryView.swift:97-100` (`towardGoal`)
- Modify: `App/DashboardView.swift` (pass the goal to `TrendSummaryView`)
- Modify: `Localization/Localizable.xcstrings`

**Interfaces:**
- Consumes: `GoalType`, `WeightGoal` (Task 1).
- Produces:
  - `StoredProfile.goalType: GoalType?` and `StoredProfile.goalStartKg: Double?` (optional so older stored JSON still decodes; synthesized `Codable` handles missing keys for optionals)
  - `extension StoredProfile { var weightGoal: WeightGoal }` → `WeightGoal(type: goalType ?? .lose, targetKg: goalWeightKg, startKg: goalStartKg)`
  - `struct GoalFieldsView: View { @Binding var draft: StoredProfile; let currentWeightKg: Double? }`: `Section("Goal")` with a segmented `Picker` (Lose weight / Gain weight / Stay at my weight) and the existing target stepper + set/remove buttons.
  - `TrendSummaryView` takes `goal: WeightGoal` instead of `goalKg: Double?`; `towardGoal(_ change:)` uses `goal.isToward(fromKg: current - change, toKg: current)` when a target exists, else the existing "down is good" default via the lose goal.
  - `AppModel.saveConfirmedProfile` / `saveProfile`: when `goalType` or `goalWeightKg` differs from the stored profile, set `goalStartKg = currentWeightKg` before saving.

- [ ] **Step 1: Add the fields, `weightGoal`, and the start-weight rule in `saveProfile`.**
- [ ] **Step 2: Build `GoalFieldsView`, use it in `ProfileEditorView`, wire `TrendSummaryView` to `model.profile.weightGoal`.**
- [ ] **Step 3: Add German translations for the new strings** ("Lose weight" → "Abnehmen", "Gain weight" → "Zunehmen", "Stay at my weight" → "Gewicht halten", "Goal type" → "Ziel").
- [ ] **Step 4: Build.** Run the app build command. Expected: `** BUILD SUCCEEDED **`.
- [ ] **Step 5: Verify in the simulator** (launch with `-demoWeightHistory YES`): set goal type Gain with target above the current weight; the trend colours flip (an upward month shows green). Take a screenshot.
- [ ] **Step 6: Commit** `feat: explicit goal type (lose / gain / maintain)`.

---

### Task 9: Mochi stores, coordinator and Settings section

**Files:**
- Create: `App/Mochi/MochiStores.swift`, `App/Mochi/MochiCoordinator.swift`, `App/Mochi/MochiSettingsSection.swift`
- Modify: `App/AppModel.swift` (own a `MochiCoordinator`), `App/ProfileEditorView.swift` (insert `MochiSettingsSection` above `Section("Settings")`), `Localization/Localizable.xcstrings`

**Interfaces:**
- Consumes: everything from Tasks 1–7.
- Produces:
  - `struct MochiSettings: Codable, Equatable { var enabled = false; var remindersEnabled = true; var reminderMode: ReminderMode = .smart; var fixedMinuteOfDay = 8 * 60; var smartMinuteOverride: Int? = nil; var haptics = true }` (`enabled` stays false until the user says yes in onboarding)
  - `enum MochiStateStore` (UserDefaults, keys prefixed `myopenscale.mochi.`): `settings`, `progress: MochiProgressState?`, `lineHistory: MochiLineHistory`, `firstLaunch: Date` (set on first read), `pendingHomeReaction: MochiPresentation?`.
  - `struct MochiPresentation: Codable, Equatable { pose: MochiPose; text: String; display: String /* tummy text */ }`
  - `@MainActor final class MochiCoordinator: ObservableObject`
    - `@Published var settings: MochiSettings` (persists on set; on change calls `rescheduleReminders`)
    - `@Published private(set) var homePresentation: MochiPresentation?`
    - `init(library loader: () -> MochiLibrary = MochiCoordinator.loadBundledLibrary)`; `static func loadBundledLibrary() -> MochiLibrary` loads `MochiLines-de.json` when `Locale.preferredLanguages.first` starts with `de`, else `-en`.
    - `func presentationForWeighIn(_ reading: LoggedReading, history: [WeightSample], profile: StoredProfile) -> MochiPresentation`: `.me` → engine reaction + line (welcome-back: prefix a `welcomeBack` line, separated by a space); `.other`/needs confirmation → `notYou`. On the user's birthday the engine still runs (state stays correct) but the shown line is a `birthday` line with pose `.birthday`, unless the event is `.goalReached` (no weight talk that day otherwise).
    - Situations are built with `tags = MochiCalendarContext.make(now:dateOfBirth:calendar: .current, regionCode: Locale.current.region?.identifier).tags`, `goalType = profile.weightGoal.type`, `event = reaction.event.lineEvent` (or the home/reminder event), `streakDays` from `MochiStats`. Persists progress and line history; triggers haptics (`.success` for confetti/doubleThumbs, light impact otherwise) when `settings.haptics`.
    - `func refreshHome(history: [WeightSample], profile: StoredProfile, now: Date = Date())`: picks pending reaction first (and clears it), else birthday → `birthday`, `daysSinceLastWeighIn ≥ 3` → `homeIdle` (pose `.snoozing`), anniversary day 30/100/365 → `anniversary`, else `home`; pose `.idle` (birthday `.birthday`).
    - `func savedNotificationBody(weightKg: Double, profile: StoredProfile) -> String` (`saved` event).
    - `func reminderBody(stage: ReminderStage, profile: StoredProfile) -> String`.
    - `func stash(_ p: MochiPresentation)` → `pendingHomeReaction`.
    - Placeholder values built here with `Double.formatted(1)` and locale-aware signs: `name`, `weight`, `change` (signed, e.g. "−0,6"), `left` (|target − current|), `percent`, `streak`, `weeks` (from `WeightHistory.weeksToGoal` + `weeklyRateKg` over 28 days), `days`, `target`. Omit keys whose data is missing.
  - `struct MochiSettingsSection: View` bound to `model.mochi.settings`: Toggle "Mochi"; when on: Toggle "Reminders", Picker "Reminder style" (Smart / Fixed time), time `DatePicker` (Fixed: `fixedMinuteOfDay`; Smart: optional "Choose my own time" toggle + picker for `smartMinuteOverride`), Toggle "Haptics". Footer when off: "Turn Mochi on to get a little companion, weigh-in cheers and reminders."
  - `AppModel.mochi: MochiCoordinator` (created in `init`).

- [ ] **Step 1: Implement `MochiStores.swift`.**
- [ ] **Step 2: Implement `MochiCoordinator.swift`.** Reminder scheduling is not part of this task; Task 12 adds `rescheduleReminders` and its calls.
- [ ] **Step 3: Implement `MochiSettingsSection` and insert it in `ProfileEditorView`.**
- [ ] **Step 4: Add DE translations** for the Settings strings.
- [ ] **Step 5: Build.** Expected: `** BUILD SUCCEEDED **`.
- [ ] **Step 6: Verify in the simulator:** the Mochi section shows; toggling Mochi hides/shows the sub-options; values survive an app relaunch.
- [ ] **Step 7: Commit** `feat: Mochi settings and coordinator`.

---

### Task 10: Drawing Mochi and its poses

**Files:**
- Create: `App/Mochi/MochiView.swift`, `App/Mochi/MochiSpeechBubble.swift`, `App/Mochi/MochiPoseGalleryView.swift`
- Modify: `App/ProfileEditorView.swift` (`developerSection`: NavigationLink "Mochi poses" → gallery, DEBUG only)

**Interfaces:**
- Consumes: `MochiPose` (Task 4).
- Produces:
  - `struct MochiView: View { let pose: MochiPose; var display: String = ""; var size: CGFloat = 160; var onTap: (() -> Void)? = nil }`, drawn with SwiftUI `Shape`s/`Path`s in a 200×200 design space scaled to `size` (match `docs/superpowers/specs/mochi-sketches/thumbs-v2.html` proportions: dome body `Theme.accent`, highlight, antenna + yellow bulb `#FFD166`, blush `#FF8FA3`, tummy display pill with `display` text in rounded bold font).
  - Each pose's animation per the spec table (`helloWave`: bounce + waving arm; `thumbsUp`: squash-hop-tilt, thumb pop with sparkles, wink, tongue-out grin, bulb glow; `doubleThumbs`: star eyes, both thumbs pumping, double hop; `confetti`: jump, arms up, falling confetti; `selfHug`: arms wrapped, pulsing heart; `bellRing`: wiggle + ringing bell; `snoozing`: closed eyes + floating z's; `sadWave`: drooping antenna, small wave; `waiting`: eyes glance left/right; `squishing`: compressed wobble; `birthday`: party hat; `idle`: breathe + blink every 3–6 s).
  - Thumbs-up hand = mitten fist + side thumb + finger creases (never a centred single digit).
  - Tap: squish (scale 1.12×0.86 then spring back) and call `onTap`.
  - `@Environment(\.accessibilityReduceMotion)`: no bounces/confetti, pose changes crossfade.
  - Accessibility: `.accessibilityLabel("Mochi")`, `.accessibilityHidden` for decorative parts.
  - `struct MochiSpeechBubble: View { let text: String }`: white rounded bubble with a tail toward the leading side, max width 220, `.transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))`.
  - `MochiPoseGalleryView`: grid of every `MochiPose.allCases` at size 140 with names.

- [ ] **Step 1: Implement `MochiView` body, face and arms as separate small `Shape`/`View` types in the same file.**
- [ ] **Step 2: Implement the pose animations** (`TimelineView`/`PhaseAnimator`/`keyframeAnimator`, builder's choice).
- [ ] **Step 3: Implement `MochiSpeechBubble` and the DEBUG gallery.**
- [ ] **Step 4: Build.** Expected: `** BUILD SUCCEEDED **`.
- [ ] **Step 5: Verify in the simulator:** open Profile → Developer → Mochi poses; screenshot the gallery; check the thumbs-up reads as a thumbs up; toggle Reduce Motion (Settings → Accessibility → Motion) and confirm there are no bounces.
- [ ] **Step 6: Commit** `feat: draw Mochi and its poses`.

---

### Task 11: Weigh-in takeover, background weigh-ins, confirm-later

**Files:**
- Create: `App/Mochi/MochiWeighInView.swift`
- Modify: `App/WeighInOverlayView.swift` (choose Mochi variant), `App/RootTabView.swift:45-52` (pass Mochi state), `App/AppModel.swift` (`finish(with:)`, `handle`, `confirmReading`, `armDismiss`), `Localization/Localizable.xcstrings`

**Interfaces:**
- Consumes: `MochiCoordinator.presentationForWeighIn`, `stash`, `savedNotificationBody` (Task 9); `MochiView`, `MochiSpeechBubble` (Task 10).
- Produces:
  - `AppModel` publishes `@Published private(set) var weighInPresentation: MochiPresentation?`, set in `finish(with:)` when `mochi.settings.enabled` (computed before the Health write, so `weightHistory` does not yet include the reading; the engine also ignores samples within 60 s).
  - `armDismiss`: 6.5 s when Mochi is enabled, else the existing 3.5 s.
  - `handle(_:from:)` background `.me` path: when Mochi is enabled, `notifications.notifySaved(body:)` with `mochi.savedNotificationBody(…)` and `mochi.stash(presentation)`; otherwise unchanged.
  - `NotificationManager.notifySaved(weightKg:)` gains an overload `notifySaved(title: String, body: String)`; Mochi title: "Mochi".
  - `confirmReading`: when Mochi is enabled, compute the presentation for the now-owner reading and `stash` it (shows on the home corner).
  - `struct MochiWeighInView: View { let phase: MeasurementPhase; let startedAt: Date?; let bleStatus: BLEStatus; let presentation: MochiPresentation?; let onAccept: () -> Void; let onDismiss: () -> Void }`:
    - `.waiting`: `MochiView(pose: .waiting, display: "– –", size: 220)` + existing hint text as a bubble + Cancel button.
    - `.measuring(w)` / `.finalizing(w)`: `MochiView(pose: .squishing, display: w.formatted(1))` (tummy ticks live), existing hints as bubble, existing "save current weight" escape hatch.
    - `.result(r)`: `MochiView(pose: presentation.pose, display: r.weightKg.formatted(1), size: 240)`, the line in a bubble, the same mini metrics + sync badge as today's `ResultView`, "Tap anywhere to dismiss".
  - `WeighInOverlayView` gains `mochiEnabled: Bool` and `presentation: MochiPresentation?`; when enabled it renders `MochiWeighInView`, else the existing content unchanged.

- [ ] **Step 1: Wire `AppModel` (presentation, dismiss timing, background, confirm).**
- [ ] **Step 2: Build `MochiWeighInView` and switch to it in `WeighInOverlayView`.**
- [ ] **Step 3: Add DE translations** for any new strings.
- [ ] **Step 4: Build.** Expected: `** BUILD SUCCEEDED **`.
- [ ] **Step 5: Verify in the simulator** using Developer → simulate weigh-in (`simulateWeighIn`) with Mochi on: waiting → squishing with ticking number → result pose + line. Repeat with Mochi off and confirm the old overlay. Screenshot both.
- [ ] **Step 6: Commit** `feat: Mochi takes over the weigh-in screen`.

---

### Task 12: Reminders

**Files:**
- Create: `App/Mochi/MochiReminderScheduler.swift`
- Modify: `App/Mochi/MochiCoordinator.swift`, `App/NotificationManager.swift`, `App/AppModel.swift`, `Localization/Localizable.xcstrings`

**Interfaces:**
- Consumes: `ReminderPlanner` (Task 6), `MochiCoordinator.reminderBody` (Task 9).
- Produces:
  - `final class MochiReminderScheduler { static let idPrefix = "mochi.reminder."; static let category = "mochi.reminder"; func replace(with reminders: [(PlannedReminder, title: String, body: String)]); func cancelAll() }`: removes all pending requests with the prefix, then adds `UNCalendarNotificationTrigger` (date components year/month/day/hour/minute, non-repeating) requests.
  - `MochiCoordinator.rescheduleReminders(history: [WeightSample], profile: StoredProfile, now: Date = Date())`: `cancelAll()` when Mochi or reminders are off; else plan with `lastWeighIn = history.last?.date`, minute = Fixed: `fixedMinuteOfDay`; Smart: `smartMinuteOverride ?? usualMinuteOfDay(history) ?? ReminderPlanner.defaultMinuteOfDay`, `count: 8`, and a body per stage (`reminderBody`). Title "Mochi".
  - Called from: `settings` didSet, `AppModel.loadWeightHistory` success (covers foreground + Watch weigh-ins synced via Health), and after a weigh-in is written.
  - `NotificationManager`: `var onReminderTap: (() -> Void)?`; in `didReceive`, when `categoryIdentifier == MochiReminderScheduler.category`, call it before the existing reading-ID handling. `willPresent` stays `[]`.
  - `AppModel` sets `notifications.onReminderTap = { [weak self] in self?.startMeasurement() }` (on the main actor).

- [ ] **Step 1: Implement `MochiReminderScheduler`.**
- [ ] **Step 2: Implement `rescheduleReminders` and its three call sites.**
- [ ] **Step 3: Route reminder taps to `startMeasurement()`.**
- [ ] **Step 4: Build.** Expected: `** BUILD SUCCEEDED **`.
- [ ] **Step 5: Verify:** in a DEBUG build add a temporary log of `UNUserNotificationCenter.current().pendingNotificationRequests()` after rescheduling (remove before commit): with Mochi on and smart mode, 8 requests at the expected dates; with Mochi off, 0. Tap a delivered test reminder (set fixed time 1–2 min ahead) and confirm the weigh-in overlay opens.
- [ ] **Step 6: Commit** `feat: Mochi weigh-in reminders`.

---

### Task 13: Home-screen corner Mochi

**Files:**
- Create: `App/Mochi/MochiCornerView.swift`
- Modify: `App/DashboardView.swift:15-17` (overlay at top-leading of the scroll content, above `WeightHeroView`), `App/AppModel.swift` (`refreshHome` calls)

**Interfaces:**
- Consumes: `MochiCoordinator.homePresentation`, `refreshHome` (Task 9); `MochiView`, `MochiSpeechBubble` (Task 10).
- Produces:
  - `struct MochiCornerView: View { let presentation: MochiPresentation?; let onTap: () -> Void }`: `MochiView(size: 64)` at top-leading with the bubble to its right; the bubble appears 0.6 s after appear, stays 5 s, then fades; tapping Mochi squishes and calls `onTap` (which asks the coordinator for a fresh `home` line and shows the bubble again).
  - Tummy display: latest weight (`model.currentWeightKg?.formatted(1) ?? "– –"`).
  - Layout: placed in a `ZStack(alignment: .topLeading)` around the hero so the hero keeps its position; add top padding to the hero only if the corner overlaps the number on the smallest supported width (check on a 6.1" simulator).
  - `refreshHome` called on dashboard appear, on foreground, and after a weigh-in result is dismissed.
  - Hidden entirely when Mochi is off.

- [ ] **Step 1: Implement `MochiCornerView` and place it in `DashboardView`.**
- [ ] **Step 2: Wire the `refreshHome` calls.**
- [ ] **Step 3: Build.** Expected: `** BUILD SUCCEEDED **`.
- [ ] **Step 4: Verify in the simulator** with `-demoWeightHistory YES`: corner Mochi shows the latest weight, a greeting bubble appears then fades, tap gives a new line; Mochi off hides it. Screenshot.
- [ ] **Step 5: Commit** `feat: Mochi in the dashboard corner`.

---

### Task 14: Onboarding hosted by Mochi

**Files:**
- Modify: `App/OnboardingView.swift`, `App/RootTabView.swift:55-58`, `Localization/Localizable.xcstrings`

**Interfaces:**
- Consumes: `MochiCoordinator.settings` (Task 9), `MochiView`, `MochiSpeechBubble` (Task 10), `GoalFieldsView` (Task 8).
- Produces:
  - New first step `.meetMochi` before `.welcome`: `MochiView(pose: .helloWave)` + bubble "Hi, I'm Mochi! Want me to help you reach your goal?" + buttons "Yes, let's go!" / "No thanks".
    - Yes: `settings.enabled = true`, go to `.welcome`.
    - No: switch the view to `MochiView(pose: .sadWave)` with bubble "Okay! If you ever want me, I'm in Settings 💚" for 2.5 s (or until tapped), fade Mochi out, then `.welcome` with Mochi disabled.
  - Every later step, when Mochi is enabled: small `MochiView(size: 90)` above the step's content with a step-specific bubble replacing the SF Symbol header icon (welcome: "Let's get you set up!", health: "I'll read a few details from Apple Health so the maths is right.", profile: "Tell me a bit about you!", scale: "Hop on your scale, I'll look for it!", done: confetti pose + "We're a team now! 🎉"). When Mochi is disabled, the steps look exactly as today.
  - Profile step: add `GoalFieldsView(draft: $draft, currentWeightKg: model.currentWeightKg)` below `ProfileFieldsView` (shown with or without Mochi).
  - New step `.reminders` between `.scale` and `.done`, Mochi-only: bell-ring pose + "Can I nudge you when it's time to weigh in?" → "Yes, remind me" (calls `model.requestNotificationAuthorization()`, keeps `remindersEnabled = true`) / "Not now" (`remindersEnabled = false`).
  - `RootTabView.task`: keep `model.requestNotificationAuthorization()` (needed for weigh-in-saved notifications); it is a no-op if already decided.

- [ ] **Step 1: Add `.meetMochi` with the yes/no and sad-wave flow.**
- [ ] **Step 2: Add the Mochi host header to each step (conditional) and the `.reminders` step.**
- [ ] **Step 3: Add `GoalFieldsView` to the profile step.**
- [ ] **Step 4: Add DE translations** for every new onboarding string (informal "du").
- [ ] **Step 5: Build.** Expected: `** BUILD SUCCEEDED **`.
- [ ] **Step 6: Verify in the simulator** after Developer → reset onboarding (`OnboardingStore.reset()` exists): run once choosing Yes (Mochi hosts every step, reminder ask appears, dashboard shows corner Mochi), once choosing No (sad wave + Settings hint, plain flow, no corner Mochi, Settings shows Mochi off). Run once with the simulator language set to German. Screenshot each.
- [ ] **Step 7: Commit** `feat: Mochi hosts onboarding`.

---

### Task 15: Final verification

**Files:** none new.

- [ ] **Step 1: Run `swift test`.** Expected: all tests pass, including the existing suites.
- [ ] **Step 2: Build the app** with the build command. Expected: `** BUILD SUCCEEDED **` with no new warnings in `App/Mochi/`.
- [ ] **Step 3: Check the string catalog:** `python3 -c "import json;d=json.load(open('Localization/Localizable.xcstrings'));print([k for k,v in d['strings'].items() if not v.get('shouldTranslate',True)==False and 'de' not in v.get('localizations',{})])"`. Expected: `[]`.
- [ ] **Step 4: End-to-end pass in the simulator** with Mochi on (onboarding → simulated weigh-in → corner bubble → Settings change reschedules reminders) and with Mochi off (app identical to before). Note anything that couldn't be checked on a simulator (real BLE weigh-in, a reminder delivered after days, Watch weigh-in cancelling a reminder).
- [ ] **Step 5: Commit any fixes** `fix: Mochi polish from final pass`.
