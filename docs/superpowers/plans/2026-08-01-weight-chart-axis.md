# Weight Chart Axis Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the weight chart a calm, readable Y-axis with a minimum 6 kg span, rounded bounds, and uncluttered whole-kilogram labels.

**Architecture:** Add a pure `WeightChartAxis` value and deterministic axis calculation to `MyOpenScaleCore.WeightHistory`. `WeightChartView` consumes that value for its Swift Charts domain and labels, while rendering the goal rule only when it is already inside the sample-derived domain.

**Tech Stack:** Swift 5.7, XCTest, SwiftUI, Swift Charts, XcodeGen, Xcode device tooling

## Global Constraints

- The visible Y-axis span is at least 6 kg.
- The desired span is `max(6 kg, observed spread × 1.3)` and is centered on the observed midpoint.
- Domain bounds are rounded outward to whole kilograms and contain every visible sample.
- Label stride is the smallest of 1, 2, 5, 10, 20, 25, or 50 kg that is at least one quarter of the final span.
- Empty input returns `0...100` with a 25 kg stride.
- Goal weight never participates in domain calculation and is drawn only when contained by the domain.
- Existing raw line, area fill, moving average, date ranges, and selection behavior remain unchanged.
- No new dependencies.

---

### Task 1: Pure axis calculation

**Files:**
- Modify: `Sources/MyOpenScaleCore/WeightHistory.swift`
- Test: `Tests/MyOpenScaleCoreTests/WeightHistoryTests.swift`

**Interfaces:**
- Consumes: `[WeightSample]` already filtered to the visible chart window.
- Produces: `public struct WeightChartAxis: Equatable, Sendable` with `domain: ClosedRange<Double>` and `strideKg: Double`; `public static func chartAxis(for samples: [WeightSample], minimumSpanKg: Double = 6) -> WeightChartAxis`.

- [ ] **Step 1: Add focused failing tests**

Append tests that specify the public behavior:

```swift
func testChartAxisUsesSafeFallbackForEmptySamples() {
    let axis = WeightHistory.chartAxis(for: [])
    XCTAssertEqual(axis.domain, 0...100)
    XCTAssertEqual(axis.strideKg, 25)
}

func testChartAxisGivesStableReadingsAtLeastSixKilograms() {
    let axis = WeightHistory.chartAxis(for: [
        sample(daysAgo: 2, kg: 79.8),
        sample(daysAgo: 1, kg: 80.2),
    ])
    XCTAssertGreaterThanOrEqual(axis.domain.upperBound - axis.domain.lowerBound, 6)
    XCTAssertLessThanOrEqual(axis.domain.lowerBound, 79.8)
    XCTAssertGreaterThanOrEqual(axis.domain.upperBound, 80.2)
    XCTAssertEqual(axis.strideKg, 2)
}

func testChartAxisCentersIdenticalReadingsWithoutDegenerating() {
    let axis = WeightHistory.chartAxis(for: [
        sample(daysAgo: 2, kg: 80),
        sample(daysAgo: 1, kg: 80),
    ])
    XCTAssertEqual(axis.domain, 77...83)
}

func testChartAxisPadsLargeSpreadAndRoundsOutward() {
    let axis = WeightHistory.chartAxis(for: [
        sample(daysAgo: 2, kg: 70.4),
        sample(daysAgo: 1, kg: 80.6),
    ])
    XCTAssertEqual(axis.domain, 68...83)
    XCTAssertEqual(axis.strideKg, 5)
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
swift test --filter WeightHistoryTests
```

Expected: compilation fails because `WeightHistory.chartAxis` does not exist.

- [ ] **Step 3: Implement the minimal calculation**

Add the public value near `WeightHistory` and the calculation inside the enum:

```swift
public struct WeightChartAxis: Equatable, Sendable {
    public let domain: ClosedRange<Double>
    public let strideKg: Double

    public init(domain: ClosedRange<Double>, strideKg: Double) {
        self.domain = domain
        self.strideKg = strideKg
    }
}

public static func chartAxis(
    for samples: [WeightSample],
    minimumSpanKg: Double = 6
) -> WeightChartAxis {
    let weights = samples.map(\.weightKg)
    guard let minimum = weights.min(), let maximum = weights.max() else {
        return WeightChartAxis(domain: 0...100, strideKg: 25)
    }

    let midpoint = (minimum + maximum) / 2
    let desiredSpan = max(minimumSpanKg, (maximum - minimum) * 1.3)
    let lower = floor(midpoint - desiredSpan / 2)
    let upper = ceil(midpoint + desiredSpan / 2)
    let domain = lower...upper
    let targetStride = (upper - lower) / 4
    let niceStrides: [Double] = [1, 2, 5, 10, 20, 25, 50]
    let stride = niceStrides.first { $0 >= targetStride } ?? ceil(targetStride / 50) * 50
    return WeightChartAxis(domain: domain, strideKg: stride)
}
```

- [ ] **Step 4: Run focused and complete core tests**

Run:

```bash
swift test --filter WeightHistoryTests
swift test
```

Expected: all tests pass with zero failures.

- [ ] **Step 5: Commit the core behavior**

```bash
git add Sources/MyOpenScaleCore/WeightHistory.swift Tests/MyOpenScaleCoreTests/WeightHistoryTests.swift
git commit -m "feat: add calm weight chart axis calculation"
```

### Task 2: Apply the axis to the SwiftUI chart

**Files:**
- Modify: `App/WeightChartView.swift`

**Interfaces:**
- Consumes: `WeightHistory.chartAxis(for:) -> WeightChartAxis` from Task 1 and the existing optional `goalKg`.
- Produces: sample-only chart scaling, explicit label stride, and a conditional goal rule.

- [ ] **Step 1: Replace the view-local domain calculation**

Add:

```swift
private var yAxis: WeightChartAxis {
    WeightHistory.chartAxis(for: samples)
}
```

Replace both uses of `yDomain` with `yAxis.domain`, remove the old `yDomain` property, and leave all chart series untouched.

- [ ] **Step 2: Limit the goal rule to the visible domain**

Change the goal condition to:

```swift
if let goalKg, yAxis.domain.contains(goalKg) {
    RuleMark(y: .value("Goal", goalKg))
    // Keep the existing styling and annotation unchanged.
}
```

- [ ] **Step 3: Give the Y-axis explicit whole-kilogram marks**

Replace the default Y-axis with:

```swift
.chartYAxis {
    AxisMarks(position: .leading, values: .stride(by: yAxis.strideKg))
}
```

- [ ] **Step 4: Generate and build the iOS project**

Run:

```bash
xcodegen generate
xcodebuild -project MyOpenScaleApp.xcodeproj -scheme MyOpenScaleApp -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **` with no Swift compilation errors.

- [ ] **Step 5: Run the complete core test suite again**

Run:

```bash
swift test
```

Expected: all tests pass with zero failures.

- [ ] **Step 6: Commit the chart integration**

```bash
git add App/WeightChartView.swift MyOpenScaleApp.xcodeproj/project.pbxproj
git commit -m "feat: improve weight chart scaling"
```

### Task 3: Build, install, and launch on the iPhone

**Files:**
- No source changes.

**Interfaces:**
- Consumes: the connected and trusted iPhone with identifier `00008120-00166DC836E0A01E` and the development signing team already configured in `project.yml`.
- Produces: a development-signed `MyOpenScaleApp.app` installed and launched on that iPhone.

- [ ] **Step 1: Confirm that the iPhone is online**

Run:

```bash
xcrun xctrace list devices
```

Expected: `iPhone von Philipp` appears under `Devices`, not `Devices Offline`.

- [ ] **Step 2: Build for the physical device**

Run:

```bash
xcodebuild -project MyOpenScaleApp.xcodeproj -scheme MyOpenScaleApp -configuration Debug -destination 'id=00008120-00166DC836E0A01E' -derivedDataPath .build/device -allowProvisioningUpdates build
```

Expected: `** BUILD SUCCEEDED **` and `.build/device/Build/Products/Debug-iphoneos/MyOpenScaleApp.app` exists.

- [ ] **Step 3: Install the built application**

Run:

```bash
xcrun devicectl device install app --device 00008120-00166DC836E0A01E .build/device/Build/Products/Debug-iphoneos/MyOpenScaleApp.app
```

Expected: device tooling reports a successful installation of `com.philippgrulich.myopenscale.app`.

- [ ] **Step 4: Launch the installed application**

Run:

```bash
xcrun devicectl device process launch --device 00008120-00166DC836E0A01E com.philippgrulich.myopenscale.app
```

Expected: device tooling reports that the application launched. If the iPhone is locked, unlock it and repeat this command.

- [ ] **Step 5: Review the final repository state**

Run:

```bash
git status --short
git log -4 --oneline
```

Expected: only intentional source, test, spec, and plan changes are present; no build products are tracked.
