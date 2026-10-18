import SwiftUI

/// True while a `WeightWheel` inside is being dragged, so a scrolling host can hold still.
struct WeightWheelDraggingKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// What the ring around a weight circle shows.
enum WeightCircleProgress: Equatable {
    case none
    /// Working without a measurable progress value: a short arc runs around the ring.
    case indeterminate
    /// This much (0...1) of the ring is filled.
    case fraction(Double)
}

/// The one look of a weight on screen: a large white circle with a soft mint inner ring
/// and an accent shadow, holding the number. Shared by the manual wheel and the scale
/// screens (waiting, measuring, result).
struct WeightCircleFace<Content: View>: View {
    var diameter: CGFloat = 240
    var progress: WeightCircleProgress = .none
    @ViewBuilder var content: () -> Content

    var body: some View {
        let ring = WeightCircleMetrics(diameter: diameter).ringWidth
        ZStack {
            Circle().fill(Theme.circleFill)
            Circle().strokeBorder(Theme.circleRing, lineWidth: ring)
            WeightCircleRing(progress: progress, lineWidth: ring)
            content()
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .shadow(color: Theme.accent.opacity(0.18), radius: diameter / 16, y: diameter / 40)
    }
}

/// Sizes that scale with the circle (the design is drawn at 240 pt).
struct WeightCircleMetrics {
    let diameter: CGFloat
    private var scale: CGFloat { diameter / 240 }

    var ringWidth: CGFloat { max(6, 10 * scale) }
    var numberFont: Font { .system(size: 58 * scale, weight: .heavy, design: .rounded) }
    var unitFont: Font { .system(size: 16 * scale, weight: .semibold, design: .rounded) }
    func neighbourFont(_ distance: Int) -> Font {
        .system(size: (distance == 1 ? 28 : 20) * scale, weight: .heavy, design: .rounded)
    }
}

/// The big number in a weight circle with its unit beside it.
struct WeightCircleNumber: View {
    let text: String
    var unit: LocalizedStringKey = "kg"
    var diameter: CGFloat = 240
    /// Drives the rolling digit transition when the number changes.
    var value: Double = 0

    var body: some View {
        let metrics = WeightCircleMetrics(diameter: diameter)
        HStack(alignment: .firstTextBaseline, spacing: 4 * diameter / 240) {
            Text(verbatim: text)
                .font(metrics.numberFont)
                .monospacedDigit()
                .contentTransition(.numericText(value: value))
            Text(unit)
                .font(metrics.unitFont)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, metrics.ringWidth * 2)
    }
}

/// The accent ring over the mint one: filled to a fraction, or a running arc.
private struct WeightCircleRing: View {
    let progress: WeightCircleProgress
    let lineWidth: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch progress {
        case .none:
            EmptyView()
        case .fraction(let fraction):
            arc(to: fraction, style: AnyShapeStyle(Theme.accent))
                .animation(reduceMotion ? nil : .snappy, value: fraction)
        case .indeterminate:
            if reduceMotion {
                // No running arc: a calm, evenly tinted ring says "working".
                arc(to: 1, style: AnyShapeStyle(Theme.accent.opacity(0.35)))
            } else {
                TimelineView(.animation) { context in
                    let period = 1.4
                    let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                    arc(to: 0.3, style: AnyShapeStyle(AngularGradient(
                        colors: [Theme.accent.opacity(0), Theme.accent],
                        center: .center, startAngle: .degrees(0), endAngle: .degrees(108))))
                        .rotationEffect(.degrees(turn * 360))
                }
            }
        }
    }

    private func arc(to fraction: Double, style: AnyShapeStyle) -> some View {
        Circle()
            .inset(by: lineWidth / 2)
            .trim(from: 0, to: max(0, min(1, fraction)))
            .stroke(style, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }
}

/// A value picked by rolling it inside a weight circle, like the iOS timer picker: swipe
/// up/down to step it (smaller neighbours above, larger below), tap to type it.
struct WeightWheel: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.1
    var diameter: CGFloat = 240
    var unit: LocalizedStringKey = "kg"
    /// What VoiceOver calls the wheel.
    var label: LocalizedStringKey = "Weight"

    /// Finger travel per step.
    static let pointsPerStep: CGFloat = 14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var consumedTranslation: CGFloat = 0
    @State private var momentum: Task<Void, Never>?
    @State private var typing = false
    /// The value when typing began: what invalid or out-of-range input falls back to.
    @State private var valueBeforeTyping: Double?
    @State private var dragging = false
    @State private var typed = ""
    @FocusState private var focused: Bool

    private var metrics: WeightCircleMetrics { WeightCircleMetrics(diameter: diameter) }

    var body: some View {
        WeightCircleFace(diameter: diameter) {
            if typing { typingField } else { lane }
        }
        .contentShape(Circle())
        // The wheel owns vertical drags; the page doesn't scroll under the finger
        // (the host reads `WeightWheelDraggingKey` and disables its scrolling).
        .highPriorityGesture(drag)
        .onTapGesture(perform: beginTyping)
        .preference(key: WeightWheelDraggingKey.self, value: dragging)
        .sensoryFeedback(.selection, trigger: value) { _, _ in !typing }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { endTyping() }
        }
        .onDisappear { momentum?.cancel() }
        .modifier(accessibility)
    }

    /// An adjustable element (±1 step, "80,3 kg"); double-tap types it in.
    private var accessibility: WheelAccessibility {
        WheelAccessibility(label: label, value: Text(verbatim: value.formatted(1) + " ") + Text(unit),
                           typing: typing,
                           increment: { set(value + step) },
                           decrement: { set(value - step) },
                           type: beginTyping)
    }

    // MARK: - Rolling

    /// The current value big in the middle, two faded neighbours above and below.
    private var lane: some View {
        VStack(spacing: 0) {
            ForEach(-2...2, id: \.self) { offset in
                row(offset).frame(height: rowHeight(offset))
            }
        }
    }

    private func rowHeight(_ offset: Int) -> CGFloat {
        let share: CGFloat
        switch abs(offset) {
        case 0: share = 0.3
        case 1: share = 0.17
        default: share = 0.13
        }
        return diameter * share
    }

    @ViewBuilder
    private func row(_ offset: Int) -> some View {
        if offset == 0 {
            WeightCircleNumber(text: value.formatted(1), unit: unit, diameter: diameter, value: value)
        } else {
            let neighbour = snapped(value + Double(offset) * step)
            if range.contains(neighbour) {
                Text(verbatim: neighbour.formatted(1))
                    .font(metrics.neighbourFont(abs(offset)))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .opacity(abs(offset) == 1 ? 1 : 0.55)
                    .contentTransition(.numericText(value: neighbour))
            } else {
                Color.clear
            }
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { gesture in
                momentum?.cancel()
                guard !typing else { return }
                if !dragging { dragging = true }
                // Upward travel (negative height) not yet turned into steps.
                let pending = consumedTranslation - gesture.translation.height
                let steps = Int((pending / Self.pointsPerStep).rounded(.towardZero))
                guard steps != 0 else { return }
                consumedTranslation -= CGFloat(steps) * Self.pointsPerStep
                set(value + Double(steps) * step)
            }
            .onEnded { gesture in
                consumedTranslation = 0
                dragging = false
                guard !typing, !reduceMotion else { return }
                // A flick keeps rolling a little, slowing down.
                let flick = gesture.translation.height - gesture.predictedEndTranslation.height
                let steps = max(-30, min(30, Int((flick / Self.pointsPerStep / 3).rounded(.towardZero))))
                roll(steps)
            }
    }

    private func roll(_ steps: Int) {
        momentum?.cancel()
        guard steps != 0 else { return }
        let direction = Double(steps.signum())
        let count = abs(steps)
        momentum = Task { @MainActor in
            for index in 0..<count {
                let progress = Double(index) / Double(count)
                try? await Task.sleep(for: .milliseconds(Int(22 + 130 * progress * progress)))
                guard !Task.isCancelled else { return }
                let before = value
                set(value + direction * step)
                if value == before { return }   // hit the end of the range
            }
        }
    }

    /// Clamps to the range and snaps to the step.
    private func set(_ newValue: Double) {
        let next = snapped(min(max(newValue, range.lowerBound), range.upperBound))
        guard next != value else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) { value = next }
    }

    private func snapped(_ raw: Double) -> Double {
        let stepped = (raw / step).rounded() * step
        return (stepped * 10).rounded() / 10   // one decimal, no float noise
    }

    // MARK: - Typing

    private var typingField: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4 * diameter / 240) {
            TextField(value.formatted(1), text: $typed)
                .keyboardType(.decimalPad)
                .focused($focused)
                .font(metrics.numberFont)
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .frame(width: diameter * 0.66)
                .onSubmit { focused = false }
                .onChange(of: typed) { _, _ in
                    // Applies as it's typed, so Save mid-typing uses it.
                    applyTyped()
                }
                .onAppear { focused = true }
            Text(unit)
                .font(metrics.unitFont)
                .foregroundStyle(.secondary)
        }
    }

    private func beginTyping() {
        momentum?.cancel()
        if typing {
            // The keyboard didn't come up (or was lost): try again, else back to the wheel.
            if !focused { focused = true }
            return
        }
        valueBeforeTyping = value
        typed = ""
        typing = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            if typing && !focused { endTyping() }   // focus never took: don't get stuck
        }
    }

    /// The typed value when it's valid and in range; otherwise the value from before typing.
    private func applyTyped() {
        guard let before = valueBeforeTyping else { return }
        if let typedValue = parse(typed), range.contains(typedValue) {
            set(typedValue)
        } else {
            set(before)
        }
    }

    private func endTyping() {
        guard typing else { return }
        applyTyped()
        typing = false
        valueBeforeTyping = nil
    }

    /// Accepts both "," and "." as the decimal separator.
    private func parse(_ text: String) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let parsed = Double(normalized), parsed.isFinite else { return nil }
        return parsed
    }
}

private struct WheelAccessibility: ViewModifier {
    let label: LocalizedStringKey
    let value: Text
    let typing: Bool
    let increment: () -> Void
    let decrement: () -> Void
    let type: () -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: typing ? .contain : .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityHint("Double-tap to type it in.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: increment()
                case .decrement: decrement()
                @unknown default: break
                }
            }
            .accessibilityAction { type() }
    }
}
