# Competitor analysis — weight diary apps (2026-10-18)

Apps reviewed: **Gewichtstagebuch** (several apps use the name; main pick *BMI Rechner & Gewichtstagebuch* by aktiWir, 4.6★ / 4.8K DE ratings; secondary *WeightFit: Gewichtstagebuch*), **Monitor Your Weight** (Husain Al-Bustan, 4.8★ / ~24K US), **Mein Gewicht** (= CurlyBrace *Weight Diary*, 4.9★ / ~2.6K US).

None of the listings document Y-axis scaling or the smoothing algorithm; chart findings come from feature lists, release notes and reviews.

## Comparison

| Feature | aktiBMI | WeightFit | Monitor Your Weight | Mein Gewicht | MyOpenScale |
|---|---|---|---|---|---|
| Trend / smoothing line | avg line (reviews say it drifts) | yes | not stated | **core feature** | ✔ time-aware EMA |
| Raw points + trend | ? | yes | ? | yes (v15) | ✔ (since this change) |
| Goal line / progress | progress bar | yes | yes, % | yes + maintenance range | goal line |
| ETA / prediction | no | days to goal, plateau | ideal weight + timeline | rate + ETA | 30-day change, distance, ETA |
| Body composition | fat, muscle, water, girths | weight, BMI | BMI, fat, girths | fat, BMI | fat, lean, BMI, water (from BLE scale) |
| Girth measurements | yes | no | yes | no | no |
| HealthKit | yes | two-way | yes | yes | write + read weight |
| Smart-scale import | via Health | via Health | Withings, Garmin, Fitbit | Withings, Fitbit | **native Mi Scale BLE** |
| Widget | no | Premium | icon badge | no | ✔ |
| Watch | no | yes + complications | yes (weak) | no | ✔ |
| Control Center | no | no | no | no | ✔ |
| Reminders | yes | smart (skips logged days) | ? | no | no |
| CSV export/import | no | yes | export | yes | no |
| Multi-user | yes | no | yes | Family Sharing | owner + "not me" attribution |
| Notes / photos | no | Premium | notes | notes (paid) | no |
| Pricing | ads + IAP tiers | freemium sub | ads + $0.99 | $7.99 paid | free / open source |

## Feature ideas, ranked by value ÷ effort

1. ~~Raw daily points under a dominant trend line~~ — **done** (Weight Diary's signature, most-praised feature).
2. ~~Trend-based summary numbers~~ — **done** for the 30-day pill (aktiBMI's drifting average shows users notice inconsistency).
3. Time ranges 1W/3M/All + full-history access (aktiBMI is criticised for month-only detail).
4. Smart weigh-in reminder that skips days already measured (WeightFit).
5. CSV export/import — expected by all three; fits an own-your-data app.
6. Maintenance goal *range* drawn as a shaded band (Weight Diary v11).
7. Plateau / rate insight ("trend flat for 14 days", "−0.4 kg/week").
8. Multiple user profiles on one scale (impedance signature already exists).
9. Trend charts for fat %, lean mass, water — data no competitor gets natively.
10. Watch complication / Lock Screen widget showing trend + delta; keep it phone-independent.

## Chart lessons for ±0.3–1 kg daily fluctuation

1. Trend is the hero line; raw weigh-ins are small low-contrast dots.
2. Exponentially weighted average (Hacker's Diet style), robust to missing days; summary numbers must use the same series.
3. Fit Y to the data with a minimum span (~3–5 kg) so noise doesn't fill the plot; goal line only when nearby.
4. Round ticks (0.5/1/2/5 kg), ≤ 5 gridlines.
5. Scale smoothing and dot density with the range (weekly mean dots for 1Y).
6. Consider a shaded band (weekly min–max or goal range) to show "normal fluctuation".
7. Show the trend delta in the header, not the raw delta.
8. Portrait scrubbing showing date, raw value and trend value — no forced landscape.

## Sources

- https://apps.apple.com/de/app/bmi-rechner-gewichtstagebuch/id1097820600
- https://apps.apple.com/de/app/weightfit-gewichtstagebuch/id1400029246
- https://apps.apple.com/de/app/gewichtstagebuch/id982346439
- https://apps.apple.com/de/app/bmi-rechner-gewichtstagebuch/id1585396256
- https://apps.apple.com/de/app/gewichtstagebuch-bmi-rechner/id1597663731
- https://apps.apple.com/us/app/-/id413313086 (Monitor Your Weight)
- https://www.healthify.nz/monitor-your-weight-app
- https://unitq.com/unitq-scorecards/monitoryourweight
- https://apps.apple.com/lu/app/mein-gewicht/id410413185?l=de-DE
- https://apps.apple.com/us/app/-/id410413185 (Weight Diary)
- https://blog.withings.com/2010/07/06/its-now-even-easier-to-follow-your-weight-trend
