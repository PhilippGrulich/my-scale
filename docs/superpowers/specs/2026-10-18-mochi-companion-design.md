# Mochi Companion Design

## Intent

MiScale today is a capable but plain tracker: a big number, a trend, a chart.
It records weight well but does nothing to keep you coming back or to make the
journey to a goal feel good. Mochi is a cute, talking companion that lives in
the app and helps the user track their weight and reach their goal. It greets
them when they first open the app, reacts to every weigh-in with motivation,
and reminds them to weigh in, all of it customisable and fully switchable off.

The feeling to aim for: **always motivating, fun and cute, and personal.** Mochi
should feel like it knows you (your name, your goal, your streak, what day it
is), never like a generic notification bot.

## Goals

- A recognisable, charming character with expressive animations.
- Mochi hosts first-run setup and greets the user.
- Mochi reacts after every weigh-in with an animation and a fitting line.
- Smart weigh-in reminders voiced by Mochi.
- Support three goal types: lose, gain, maintain weight.
- Lots of variation; messages aware of calendar and personal context.
- Everything configurable in Settings, including turning Mochi off entirely.
- Full English and German, like the rest of the app.

## Non-goals (this version)

- **LLM / generative text.** Discussed (Apple Foundation Models on-device was
  the preferred route if ever added) and explicitly left out. The message system
  should not preclude adding it later, but nothing is built for it now.
- Mochi on Apple Watch, widgets or Controls. (Builder's call: iPhone only for v1.)
- Chat or free-form conversation with Mochi.
- Diet, calorie or exercise advice of any kind.
- Sounds (haptics only for v1).
- Weight units other than kg (the app is kg-only; use local number formatting).
- Migration for existing installs: there are no existing users, so Mochi is
  introduced only through onboarding.
- Choosing a different name: Mochi is always called Mochi.

## Anti-goals (failure even if it "works")

- **Shaming or guilt.** Mochi never scolds, never asks "what did you eat?", never
  frames a move away from the goal as failure. Up days (for losers) or down days
  (for gainers) get comfort, not criticism.
- Sounding like medical advice.
- Nagging. At most one reminder per day; backing off when ignored.
- Repetitiveness. Hearing the same line over and over kills the charm.
- Getting in the way. On the home screen Mochi is small; the weight stays the hero.
- Ugly or ambiguous gestures. (The first thumbs-up sketch read as a middle
  finger; hands must be drawn as an unmistakable fist + side thumb.)

## The character

**Mochi** is a soft, jelly-like little scale ("squishy Mochi" direction, chosen
from three sketches): a rounded dome body in the app accent green
(`Theme.accent`), a small antenna with a yellow bulb, pink blush cheeks, short
stubby arms, and a little display on its tummy that shows a weight.

- Drawn **in code (SwiftUI shapes/paths)**, not image assets, so it can squash,
  stretch and change expression smoothly and render crisp at any size. (Our call.)
- The tummy display shows **real data**: live weight during a weigh-in, the
  latest weight in the user's unit otherwise; "– –" when waiting/no data.
- Ambient life: occasional blinks, a gentle idle bob/breathe, squish on tap.
- Reference sketches live in `docs/superpowers/specs/mochi-sketches/` (`character.html`,
  `poses.html`, `thumbs-and-home.html`, `thumbs-v2.html`; fragments, open in a browser). They show proportions and spirit; the builder
  may refine shapes.

### Poses / animations

| Pose | Look | Used for |
|------|------|----------|
| Hello wave | Bounce, one arm waving, "hi!" on display | First open; welcome back after a long break |
| "Nailed it!" thumbs up | Squash-hop-tilt, thumb pops out with sparkles, wink, tongue-out grin, antenna bulb lights up | Normal weigh-in toward / at goal |
| Double thumbs, star eyes | Star eyes, both thumbs pumping, double hop | New best, streaks, good week |
| Jump + confetti | Big jump, arms up, confetti, change shown on display | Milestone, goal reached |
| Self-hug + heart | Arms wrapped around itself, pulsing heart above | A day that moved away from the goal |
| Bell ring | Wiggle, holding a ringing bell | Reminder context (notification art / in-app) |
| Snoozing | Closed eyes, floating "z z z" | Home screen idle after several days without a weigh-in |
| Sad wave | Antenna droops, small wave | Declining Mochi in onboarding |
| Waiting / looking around | Eyes glance side to side | Weigh-in, before stepping on |
| Squishing under load | Compressed body, wobbling | Weigh-in, while measuring |
| Birthday | Party hat (+ cake) | User's birthday |

Thumbs-up hands: chunky mitten fist, thumb on the side, curled-finger creases.
Never a single digit from the centre.

Haptics accompany key moments (result reveal, confetti, tap squish). **Our call:**
haptics on by default, with a toggle. **No sounds in v1** (the repo has no audio
assets; sounds can come later). Respect iOS Reduce Motion (simpler crossfades
instead of bounces/confetti).

## Where Mochi appears

### 1. First-run setup (greeting)

The existing onboarding (`OnboardingView`: welcome → health → profile → scale →
done) gains Mochi as host.

- **First screen:** Mochi waves: "Hi, I'm Mochi! Want me to help you reach your
  goal?" with Yes / No thanks.
- **Yes:** Mochi stays on screen through each step, "talking" via speech bubbles
  that explain the step (Health permission, profile, pairing). The profile step
  gains a **goal type** choice (Lose / Gain / Stay at my weight) plus target
  weight. Done step: celebration.
- **No:** Mochi plays the sad-wave animation and says something like "Okay! If you
  ever want me, I'm in Settings 💚", then disappears; the rest of onboarding is
  today's plain flow and Mochi is stored as disabled. (Goal type is still asked
  in the profile step either way; it also drives the app's trend colours.)
- Mochi's onboarding should request notification permission in context ("Can I
  nudge you when it's time to weigh in?") only when Mochi is enabled. (Our call.)

### 2. Weigh-in screen (motivation after a measurement)

When Mochi is enabled, Mochi **takes over `WeighInOverlayView`**, keeping its
existing phases (`MeasurementPhase`):

- **Waiting:** Mochi looking around, display "– –", existing hint/cancel.
- **Measuring / finalizing:** Mochi squishing; the tummy number ticks live with
  the reading; existing hints ("Stay still…") kept as Mochi speech.
- **Result:** number locks in, Mochi plays the chosen reaction pose and says a
  message. Accept/dismiss behaviour unchanged.

When Mochi is disabled, the overlay is exactly today's.

Weigh-ins captured in the background: the "Weigh-in saved" notification is
written in Mochi's voice, and the reaction shows on the home-screen Mochi
(bubble + pose) next time the app opens. (Our call.)

### 3. Home screen

Mochi sits **small in the top-left corner** of the dashboard, above/beside the
weight hero, gently bobbing. A speech bubble pops in when Mochi has something to
say (greeting, streak, distance to goal, the last reaction), then fades. Tapping
Mochi squishes it and shows a new line. Snoozing pose when the user has been
away several days. The big weight number remains the hero; Mochi never pushes
the layout around.

### 4. Reminders

Local notifications (extend `NotificationManager`), voiced by Mochi.

- **Smart (default):** first nudge the day after the last weigh-in, at the user's
  usual weigh-in time (typical time of day across recent weigh-ins, robust to one
  outlier). If ignored, gaps double: 1, 2, 4, 8 days after the last weigh-in,
  then weekly indefinitely. Any weigh-in resets the cycle.
- **Fixed:** every day at a user-chosen time.
- Never more than one per day; never on a day already weighed in.
- Tone softens the longer the gap: "Psst… hop on me? 🥺" → "I miss you! No
  pressure, just say hi 💚". No guilt.
- Tapping opens the app straight into the weigh-in (Mochi waiting).
- **Mochi disabled ⇒ no reminders at all.**
- Without a user-chosen time and no weigh-in history yet, use a sensible morning
  default. (Our call: 08:00.)

## Goal types

New explicit setting: **Lose weight / Gain weight / Stay at my weight**, plus
target weight (maintain: a target with a tolerance band; builder's call ±1 kg,
user-adjustable optional). Set in onboarding, editable in Profile.

- "Toward goal" is defined by goal type; reactions, wording and the existing
  trend colours (`TrendSummaryView.towardGoal`) all follow it.
- "New best" = new low (lose), new high (gain).
- **Maintain:** inside the band counts as on goal; outside the band, moving back
  toward the band counts as "toward goal" (also for trend colours). There are
  no kg or % milestones; instead achievements are streaks of days in range
  (builder's call on the exact thresholds, e.g. 7 / 30 / 100 days). "Goal
  reached" means re-entering the band after being outside it.
- Gainers hear "+0.4, you're growing strong 💪", never "careful, you gained".
- No goal set ⇒ behave as "lose" (today's behaviour) and skip goal-based
  messages and milestones.

## Data Mochi counts (our call)

- **History and stats** (streaks, days since last weigh-in, new best, this week
  vs last, reminder scheduling) use the same weight history the dashboard chart
  uses (`AppModel.weightHistory`, i.e. Apple Health weight samples), so Mochi
  never disagrees with the chart. A weigh-in from the Watch app therefore
  counts; best effort to also cancel that day's reminder (e.g. reschedule on
  app activation / HealthKit observer, builder's call).
- **Reactions** fire only for a fresh weigh-in that this app captured and
  attributed to the owner.
- **Someone else's reading** (`.other`), or a held "Was this you?" reading:
  Mochi stays neutral (no celebration or comfort, no goal talk), e.g. "That
  wasn't you? I'll keep it secret 🤫". If a held reading is later confirmed as
  the owner's, it counts normally and its reaction shows on the home-screen
  Mochi.
- **Start weight:** stored when the goal (or goal type) is set or changed: the
  latest weight at that moment. Milestones and % progress count from it.
  "New best" means best since the goal was set. Changing the goal resets fired
  milestones and the best.

## Reactions after a weigh-in

First matching rule wins:

1. **Goal reached** (crossed target / entered maintain band): confetti jump.
2. **Milestone:** every whole kg toward the goal, and 25 / 50 / 75 % of the way:
   confetti jump.
3. **New best** (see goal types): double thumbs, star eyes.
4. **Streak** (3+ consecutive days) or **good week** (week trending toward goal):
   double thumbs.
5. **Toward goal or flat:** "Nailed it!" thumbs up.
6. **Away from goal:** self-hug + heart.
7. **Back after a long break** (builder's call: 7+ days): hello wave. (Applies as
   an overlay on the above: the welcome-back line takes priority, the pose may
   combine.)

Small changes below scale noise (~0.1 kg) count as flat. Milestones/new-best
fire once each (persisted), not repeatedly on every weigh-in near the threshold.

## Messages and personalisation

**Context Mochi uses:**

- You: name (from profile), birthday (from date of birth: party hat, no weight
  talk that day).
- Calendar: time of day (early bird / late evening), weekday, Monday / after the
  weekend, Friday, weekend, holidays (Christmas, New Year, Easter; region-aware
  via locale), season.
- Your story: streak length, days since last weigh-in, progress to goal
  (kg left, % done, ETA from existing `WeightHistory.weeksToGoal`), this week vs
  last, time using the app ("one month together! 🎂").
- The current event: reaction category above, or reminder stage, or home greeting.

**Variety:**

- A large hand-written library of lines (target several hundred across EN/DE),
  each tagged with the contexts it fits (event, goal type, weekday, time of day,
  holiday, streak, …) and with placeholders for numbers/name.
- Selection picks among the most specific matching lines, fills placeholders in
  the user's units and locale formatting.
- Recently used lines are remembered; no repeats within ~2 weeks where
  alternatives exist.
- "After the weekend" lines are encouraging, never blaming ("Weekends happen!
  Fresh week, let's go 💪").
- Lines live in the localisation catalogue (`Localization/Localizable.xcstrings`)
  or an equivalent per-language data file, whichever keeps tagging manageable.
  (Builder's call.) Every line exists in English and German.

The message selector should be pure, deterministic given (context, history,
random seed) logic, so it can be unit tested in `MyOpenScaleCore` style.

## Settings

A new **Mochi** section in Settings (Profile tab, `ProfileEditorView`):

- **Mochi** on/off (master switch). Off: no corner Mochi, plain weigh-in
  overlay, no Mochi messages, no reminders, app looks exactly as today.
- **Reminders** on/off.
- **Reminder style:** Smart / Fixed time.
- **Reminder time:** for Fixed; for Smart, optional override of "usual time".
- **Haptics** on/off (default on).

Goal type and target weight live in the existing Goal section.

## Constraints

- iOS 26+, SwiftUI, existing architecture (`AppModel`, UserDefaults-backed stores
  like `ProfileStore` / `OnboardingStore`).
- No network, no accounts: everything on-device, consistent with the app's
  privacy promise.
- Localised EN + DE.
- Must not regress the existing weigh-in, attribution or HealthKit flows.

## Left to the builder

- Exact SwiftUI drawing, animation curves and timing.
- Data format and tagging scheme for the message library; writing the lines.
- Persistence shape for Mochi settings, reminder state, line history, fired
  milestones.
- Robust "usual time" calculation.
- How notifications are rescheduled (on each weigh-in, app launch, settings change).
- Exact layout of the corner Mochi and speech bubble.
