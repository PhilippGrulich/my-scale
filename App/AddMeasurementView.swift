import SwiftUI
import MyOpenScaleCore

/// The Weigh in tab — the one place to add a weigh-in. Each time it's opened
/// it starts in the mode that fits the user:
///
/// - **Scale paired** → `.scale`: live "step on your scale" → reading → result,
///   with "Enter manually" as the way out (prominent when Bluetooth is off).
/// - **No scale yet** → `.manual`: a short form saved to Apple Health, with a
///   "Pair a scale" card that switches to `.pairing` in place.
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
        if mode == .manual {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!Self.weightRange.contains(weightKg) || saving)
            }
        } else if mode == .scale, case .result = model.measurementPhase {
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
        if let fat = model.latestValue(.bodyFat), fat.isFinite { bodyFatPercent = (fat * 2).rounded() / 2 }
        start(mode)
    }

    private func leave() {
        model.endPairingScan()
        model.dismissOverlay()
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

    private var bluetoothUsable: Bool { model.bleStatus == .scanning || model.bleStatus == .idle }

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

    private var manualForm: some View {
        Form {
            Section {
                HStack {
                    Text("Weight")
                    Spacer()
                    TextField("Weight", value: $weightKg,
                              format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .frame(maxWidth: 110)
                    Text("kg").foregroundStyle(.secondary)
                    Stepper("Weight", value: $weightKg, in: Self.weightRange, step: 0.1)
                        .labelsHidden()
                }
                DatePicker("Date", selection: $date, in: ...Date())
            }

            Section {
                Toggle("Body fat", isOn: $includeBodyFat.animation())
                if includeBodyFat {
                    HStack {
                        TextField("Body fat", value: $bodyFatPercent,
                                  format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                            .monospacedDigit()
                        Text("%").foregroundStyle(.secondary)
                        Stepper("Body fat", value: $bodyFatPercent, in: 3...75, step: 0.5)
                            .labelsHidden()
                    }
                }
            } footer: {
                if includeBodyFat {
                    Text("Saved to Apple Health as a manual entry. BMI is calculated from your height, lean mass from your body fat.")
                } else {
                    Text("Saved to Apple Health as a manual entry. BMI is calculated from your height.")
                }
            }

            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            Section { scaleCallToAction }
        }
    }

    /// Paired → one tap back to the live scale. Not paired → invite to pair,
    /// explaining what it buys (automatic readings + body composition).
    @ViewBuilder
    private var scaleCallToAction: some View {
        if model.hasPairedScale {
            Button { switchTo(.scale) } label: {
                Label("Weigh in on the scale", systemImage: "scalemass")
            }
        } else {
            Button { switchTo(.pairing) } label: {
                HStack(spacing: 14) {
                    Image(systemName: "scalemass.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pair a scale")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Weigh-ins with body fat, lean mass and BMI are then saved automatically.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func save() {
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
