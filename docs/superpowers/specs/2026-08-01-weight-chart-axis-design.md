# Weight Chart Axis Design

## Goal

Make the weight chart calm, readable, and visually honest when the recorded
weights are close together. Small day-to-day fluctuations must not fill nearly
the entire chart height.

## Current behavior

`WeightChartView` derives its Y-axis directly from the minimum and maximum
visible weights. It adds 15% padding, with a minimum of 1 kg on each side. A
stable series can therefore use a total range of only about 2 kg, exaggerating
normal measurement noise. The goal weight is also included in the domain,
which can compress the readings when the goal is far away.

## Chosen design

The chart uses an adaptive, calm Y-axis derived only from the samples visible in
the selected time range.

- The visible Y-axis span is at least 6 kg.
- The desired span is the larger of 6 kg and 130% of the observed spread,
  centered on the midpoint of the observed minimum and maximum. This provides
  15% padding on each side when the observed spread exceeds the minimum.
- The lower and upper bounds are rounded outward to whole kilograms.
- The domain always contains every visible sample.
- Empty input returns a safe fallback domain.
- The goal weight does not participate in domain calculation.
- A goal rule is rendered only when the goal lies within the calculated domain.
- Axis labels use an explicit stride: the smallest value from
  1, 2, 5, 10, 20, 25, or 50 kg that is at least one quarter of the final
  domain span. This produces about four intervals and avoids decimal labels.

The existing raw line, area fill, moving-average trend, date ranges, and chart
selection interaction remain unchanged.

## Architecture

Axis calculation belongs in `MyOpenScaleCore.WeightHistory` as pure logic. It
returns the domain and label stride needed by the SwiftUI view. Keeping this
logic outside `WeightChartView` makes edge cases deterministic and testable
without an iOS simulator.

`WeightChartView` filters samples for the selected range, asks
`WeightHistory` for the axis configuration, supplies the returned domain and
stride to Swift Charts, and conditionally renders the goal rule.

## Data flow

1. The selected chart range filters the HealthKit weight history.
2. Visible weight values are passed to the axis calculation.
3. The calculation centers a span of `max(6 kg, observed spread × 1.3)` on the
   observed midpoint and rounds both bounds outward to whole kilograms.
4. The view applies the domain and label stride.
5. The view renders the goal rule only if the goal is inside that domain.

## Edge cases

- No samples: return the existing safe fallback range.
- Identical or nearly identical samples: center a minimum 6 kg range around
  the values, then round outward.
- Large changes: preserve all values and proportional padding.
- Goal outside the domain: omit the goal rule without changing the scale.
- Goal on either domain boundary: treat it as visible.

## Testing

Core unit tests cover:

- stable readings receiving at least a 6 kg span;
- identical readings producing a non-degenerate centered domain;
- large ranges containing all values with padding;
- outward whole-kilogram rounding;
- deterministic stride selection;
- empty-input fallback behavior.

The implementation will be verified with the complete Swift package test suite
and an iOS application build before installation on the connected iPhone.

## Deployment

Generate the Xcode project if required, build a development-signed application
for the connected iPhone, install it using Apple's device tooling, and launch it
when the device is available and trusted.
