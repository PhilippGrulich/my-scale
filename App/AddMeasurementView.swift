import SwiftUI
import MyOpenScaleCore

/// The Weigh in tab — the one place to add a weigh-in. Each time it's opened
/// it starts in the mode that fits the user:
///
/// - **Scale paired** → `.scale`: live "step on your scale" → reading → result,
///   with "Enter manually" as the way out (prominent when Bluetooth is off).
/// - **No scale yet** → `.manual`: a rolling weight circle saved to Apple Health, with a
///   "Pair a scale" card that switches to `.pairing` in place. Bluetooth stays
///   off (no permission prompt) until that card is tapped.
/// - `.pairing` scans while the user stands on the scale; confirming pairs it
///   and drops straight into `.scale`, so that same stand becomes the first
///   automatic reading.
///
/// Stepping on the paired scale while the manual form is open switches to the
/// live view — the scale is always the better source.
struct AddMeasurementView: View {
    enum Mode { case scale, manual, pairing }

    @EnvironmentObject var model: AppModel
    /// Called when a weigh-in is saved or finished (the shell then shows Overview).
    var onFinished: () -> Void = {}

    @State private var mode: Mode = .manual
    // Manual form
    @State private var weightKg: Double = 75
    @State private var includeBodyFat = false
    @State private var bodyFatPercent: Double = 20
    @State private var date = Date()
    @State private var pickingDate = false
    @State private var wheelDragging = false
    /// The weight the form started from; a late history load may replace it only while untouched.
    @State private var seededWeightKg: Double?
    @State private var saving = false
    @State private var error: String?

    private static let weightRange = 20.0...300.0

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .scale: scaleContent
                case .manual: manualForm
                case .pairing: pairingContent
                }
            }
            .animation(.snappy, value: mode)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .tint(Theme.accent)
        .onAppear(perform: enter)
        .onDisappear(perform: leave)
        .onChange(of: model.measurementPhase) { old, new in
            switch (mode, old, new) {
            // The result auto-dismisses after a few seconds; close with it.
            case (.scale, .result, .idle): finish()
            // Stepped on the paired scale while typing → show it live.
            case (.manual, _, .measuring), (.manual, _, .finalizing):
                if model.hasPairedScale { switchTo(.scale) }
            default: break
            }
        }
        // History loaded after the form opened: start from the last weight, unless the
        // user already changed it.
        .onChange(of: model.currentWeightKg) { _, new in
            guard let new, mode == .manual, weightKg == seededWeightKg else { return }
            weightKg = (new * 10).rounded() / 10
            seededWeightKg = weightKg
        }
    }

    private var title: LocalizedStringKey {
        switch mode {
        case .scale: return "New measurement"
        case .manual: return "Add weight"
        case .pairing: return "Pair scale"
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if mode == .scale, case .result = model.measurementPhase {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { finish() }
            }
        }
    }

    // MARK: - Mode transitions

    private func enter() {
        mode = model.hasPairedScale ? .scale : .manual
        date = Date()
        includeBodyFat = false
        error = nil
        if let current = model.currentWeightKg { weightKg = (current * 10).rounded() / 10 }
        seededWeightKg = weightKg
        if let fat = model.latestValue(.bodyFat), fat.isFinite { bodyFatPercent = (fat * 2).rounded() / 2 }
        start(mode)
    }

    private func leave() {
        model.endPairingScan()
        // A saved manual entry's Mochi reaction shows over Overview; leaving must not close it.
        if mode != .manual { model.dismissOverlay() }
    }

    private func finish() {
        leave()
        onFinished()
    }

    private func switchTo(_ next: Mode) {
        if mode == .pairing { model.endPairingScan() }
        if mode == .scale, next != .scale { model.dismissOverlay() }
        mode = next
        start(next)
    }

    private func start(_ mode: Mode) {
        switch mode {
        case .scale: model.startMeasurement()
        case .pairing: model.beginPairingScan()
        case .manual: break
        }
    }

    // MARK: - Scale

    /// False only when Bluetooth is denied, off or missing — not while it's starting
    /// (e.g. while the first-run permission prompt is up).
    private var bluetoothUsable: Bool { !model.bleStatus.isUnavailable }

    @ViewBuilder
    private var scaleContent: some View {
        VStack {
            Spacer(minLength: 0)
            if model.mochi.settings.enabled {
                // Mochi hosts the weigh-in here just like in the passive overlay.
                MochiWeighInView(phase: model.measurementPhase,
                                 startedAt: model.liveStartedAt,
                                 bleStatus: model.bleStatus,
                                 presentation: model.weighInPresentation,
                                 onAccept: { model.acceptCurrentLiveWeight() },
                                 onEnterManually: { switchTo(.manual) },
                                 showsDismissHint: false)
            } else {
                plainScaleContent
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }

    @ViewBuilder
    private var plainScaleContent: some View {
        switch model.measurementPhase {
        case .idle, .waiting:
            WaitingView(bleStatus: model.bleStatus,
                        onEnterManually: { switchTo(.manual) })
        case .measuring(let w):
            MeasuringView(weightKg: w, label: "Reading weight…",
                          hint: "Stay still on the scale.",
                          startedAt: model.liveStartedAt,
                          onAccept: { model.acceptCurrentLiveWeight() })
        case .finalizing(let w):
            MeasuringView(weightKg: w, label: "Measuring body composition…",
                          hint: "Almost there — keep your feet on the scale.",
                          startedAt: model.liveStartedAt,
                          onAccept: { model.acceptCurrentLiveWeight() })
        case .result(let r):
            ResultView(reading: r, showsDismissHint: false)
        }
    }

    // MARK: - Manual

    /// The rolling weight circle, how it compares to last time, the date and optional
    /// body fat as chips, and a big Save.
    private var manualForm: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 14) {
                        WeightWheel(value: $weightKg, range: Self.weightRange, step: 0.1,
                                    diameter: 240, unit: "kg")
                        deltaLine
                            .frame(minHeight: 20)
                    }
                    .padding(.top, 28)

                    HStack(spacing: 10) {
                        Button { pickingDate = true } label: {
                            Label(dateLabel, systemImage: "calendar")
                        }
                        // Optional: shows / hides the body-fat row below.
                        Button { withAnimation(.snappy) { includeBodyFat.toggle() } } label: {
                            Label {
                                Text("Body fat")
                            } icon: {
                                Image(systemName: includeBodyFat ? "drop.fill" : "drop")
                                    .foregroundStyle(BodyMetric.bodyFat.tint)
                            }
                        }
                        .buttonStyle(ManualChipStyle(tint: includeBodyFat ? BodyMetric.bodyFat.tint : nil))
                        .accessibilityValue(includeBodyFat ? Text("On") : Text("Off"))
                    }
                    .buttonStyle(ManualChipStyle())
                    .padding(.top, 18)

                    if includeBodyFat {
                        BodyFatRow(value: $bodyFatPercent,
                                   onRemove: { withAnimation(.snappy) { includeBodyFat = false } })
                            .padding(.top, 14)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Group {
                        if includeBodyFat {
                            Text("Saved to Apple Health as a manual entry. BMI is calculated from your height, lean mass from your body fat.")
                        } else {
                            Text("Saved to Apple Health as a manual entry. BMI is calculated from your height.")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.top, 20)

                    Spacer(minLength: 24)

                    VStack(spacing: 14) {
                        if let error {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .font(.footnote)
                        }
                        Button(action: save) {
                            ZStack {
                                Text("Save").opacity(saving ? 0 : 1)
                                if saving { ProgressView().tint(.white) }
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .tint(Theme.accent)
                        .disabled(!Self.weightRange.contains(weightKg) || saving)

                        scaleCallToAction
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                .animation(.snappy, value: includeBodyFat)
                // Tapping outside the circle applies a typed value.
                .contentShape(Rectangle())
                .onTapGesture(perform: dismissKeyboard)
            }
            .scrollBounceBehavior(.basedOnSize)
            // A drag on a wheel rolls the value, never the page.
            .scrollDisabled(wheelDragging)
            .onPreferenceChange(WeightWheelDraggingKey.self) { wheelDragging = $0 }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done", action: dismissKeyboard)
            }
        }
        .sheet(isPresented: $pickingDate) { datePicker }
    }

    /// "−0,2 since last": green toward the goal, orange away from it; hidden without a previous weight.
    @ViewBuilder
    private var deltaLine: some View {
        if let unrounded = model.currentWeightKg {
            // Compared as shown (one decimal), so the starting value reads "same as last".
            let last = (unrounded * 10).rounded() / 10
            let delta = ((weightKg - last) * 10).rounded() / 10
            Group {
                if abs(delta) < 0.05 {
                    Text("same as last")
                        .foregroundStyle(.secondary)
                } else {
                    let signed = (delta < 0 ? "−" : "+") + abs(delta).formatted(1)
                    Text("\(signed) since last")
                        .foregroundStyle(model.profile.weightGoal.isToward(fromKg: last, toKg: weightKg)
                                         ? Theme.accent : .orange)
                }
            }
            .font(.subheadline.weight(.semibold))
            .contentTransition(.numericText(value: delta))
        }
    }

    /// "Today, 21:20", "Yesterday, 07:05", or the date.
    private var dateLabel: String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return String(localized: "Today, \(time)") }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday, \(time)") }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var datePicker: some View {
        NavigationStack {
            VStack {
                DatePicker("Date", selection: $date, in: ...Date())
                    .datePickerStyle(.graphical)
                    .tint(Theme.accent)
                    .padding(.horizontal)
                Spacer(minLength: 0)
            }
            .navigationTitle("Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { pickingDate = false }
                }
            }
        }
        .presentationDetents([.height(560), .large])
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// Paired → one tap back to the live scale. Not paired → invite to pair,
    /// explaining what it buys (automatic readings + body composition) and which
    /// scale works.
    @ViewBuilder
    private var scaleCallToAction: some View {
        if model.hasPairedScale {
            Button { switchTo(.scale) } label: {
                Label("Weigh in on the scale", systemImage: "scalemass")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.glass)
            .tint(Theme.accent)
        } else {
            Button { switchTo(.pairing) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "scalemass.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pair a scale")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Weigh-ins with body fat, lean mass and BMI are then saved automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Works with Xiaomi Mi Body Composition Scale 2")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Theme.circleFill, in: RoundedRectangle(cornerRadius: 18))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func save() {
        dismissKeyboard()
        saving = true
        error = nil
        model.addManualMeasurement(weightKg: weightKg,
                                   bodyFatPercent: includeBodyFat ? bodyFatPercent : nil,
                                   date: date) { result in
            saving = false
            switch result {
            case .success: finish()
            case .failure(let e): error = HealthKitSink.userMessage(for: e)
            }
        }
    }

    // MARK: - Pairing

    private var pairingContent: some View {
        VStack(spacing: 0) {
            Spacer()
            if !bluetoothUsable {
                pairingHeader(icon: "antenna.radiowaves.left.and.right.slash",
                              title: "Bluetooth needed",
                              subtitle: "\(model.bleStatus.label)")
            } else if let candidate = model.scaleCandidate {
                VStack(spacing: 14) {
                    Image(systemName: "scalemass.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(Theme.accent)
                        .symbolEffect(.pulse)
                    Text("Scale found")
                        .font(.title2.weight(.semibold))
                    Text("\(candidate.weightKg.formatted(1)) kg")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .contentTransition(.numericText(value: candidate.weightKg))
                        .animation(.snappy, value: candidate.weightKg)
                    Text("Is this your scale?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 16) {
                    ProgressView().controlSize(.large)
                    Text("Step on your scale now")
                        .font(.title3.weight(.semibold))
                    Text("It wakes up when you stand on it and shows up here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer()
            VStack(spacing: 12) {
                if let candidate = model.scaleCandidate, bluetoothUsable {
                    Button {
                        model.pairScale(candidate.peripheralID)
                        switchTo(.scale)   // they're still standing on it
                    } label: {
                        Text("Yes, pair this scale")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.large)
                }
                Button { switchTo(.manual) } label: {
                    Text(model.scaleCandidate == nil ? "Enter manually instead" : "Not my scale")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .tint(.secondary)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }

    private func pairingHeader(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

/// The small white date / body-fat chips under the manual weight circle.
private struct ManualChipStyle: ButtonStyle {
    /// A subtle tint over the white chip, e.g. while the chip's option is on.
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .labelStyle(ChipLabelStyle())
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                Capsule().fill(Theme.circleFill)
                    .overlay(Capsule().fill((tint ?? .clear).opacity(0.14)))
            }
            .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }

    private struct ChipLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 6) {
                configuration.icon.foregroundStyle(Theme.accent)
                configuration.title
            }
        }
    }
}

/// The optional body fat as one compact card: a tap-to-type number (decimal pad, "," or
/// "."), a 0.5 % stepper and an × to remove it. Invalid or out-of-range input keeps the old value.
private struct BodyFatRow: View {
    @Binding var value: Double
    let onRemove: () -> Void

    static let range = 3.0...75.0

    @State private var text = ""
    /// The value when typing began: what invalid input falls back to.
    @State private var valueBeforeTyping: Double?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text("Body fat")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                TextField(value.formatted(1), text: $text)
                    .keyboardType(.decimalPad)
                    .focused($focused)
                    .multilineTextAlignment(.center)
                    .font(.body.weight(.semibold).monospacedDigit())
                    .frame(width: 56)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Body fat")
                Text("%").foregroundStyle(.secondary)
            }
            Stepper("Body fat", value: $value, in: Self.range, step: 0.5)
                .labelsHidden()
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove body fat")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Theme.circleFill, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        .onAppear { text = value.formatted(1) }
        // Typed values apply as they're typed (so Save uses them); the stepper updates the text.
        .onChange(of: text) { _, typed in
            guard focused, let before = valueBeforeTyping else { return }
            let normalized = typed.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
            var next = before
            if let parsed = Double(normalized), parsed.isFinite, Self.range.contains(parsed) {
                next = (parsed * 10).rounded() / 10
            }
            if next != value { value = next }
        }
        .onChange(of: value) { _, new in
            if !focused { text = new.formatted(1) }
        }
        .onChange(of: focused) { _, isFocused in
            if isFocused {
                valueBeforeTyping = value
                text = ""   // the placeholder shows the current value; typing replaces it
            } else {
                valueBeforeTyping = nil
                text = value.formatted(1)   // invalid input shows the kept value again
            }
        }
    }
}
