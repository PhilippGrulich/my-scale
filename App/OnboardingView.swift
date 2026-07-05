import SwiftUI
import MyOpenScaleCore

/// First-launch welcome flow: intro → connect Apple Health (pre-fill) → confirm
/// details → find & remember the scale → done. Driven entirely by `AppModel`
/// (which already owns Health + BLE). `onFinish` flips the app to the dashboard.
struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    let onFinish: () -> Void

    enum Step { case welcome, health, profile, scale, done }

    @State private var step: Step = .welcome
    @State private var draft = StoredProfile.makeDefault()
    @State private var healthBusy = false

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            content
                .padding(.horizontal, 24)
                .frame(maxWidth: 520)
        }
        .animation(.snappy, value: step)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcomeStep
        case .health: healthStep
        case .profile: profileStep
        case .scale: scaleStep
        case .done: doneStep
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()
            header(icon: "scalemass.fill",
                   title: "Welcome",
                   subtitle: "Step on your body-composition scale and your weigh-ins flow straight into Apple Health — body fat, lean mass and BMI computed on-device. No accounts, no cloud.")
            Spacer()
            VStack(spacing: 12) {
                primaryButton("Get Started") { step = .health }
                Text("Body-composition values are estimates, not medical advice. Works with the Xiaomi Mi Body Composition Scale 2 — not affiliated with or endorsed by Xiaomi.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 40)
    }

    private var healthStep: some View {
        VStack(spacing: 0) {
            Spacer()
            header(icon: "heart.text.square.fill",
                   title: "Connect Apple Health",
                   subtitle: "We'll read your age, height and biological sex to calculate body composition, and save each weigh-in back to Health.")
            Spacer()
            VStack(spacing: 12) {
                if healthBusy {
                    ProgressView().padding(.bottom, 4)
                }
                primaryButton("Connect Apple Health", disabled: healthBusy) {
                    healthBusy = true
                    model.startOnboardingHealthPrefill {
                        healthBusy = false
                        goToProfile()
                    }
                }
                secondaryButton("Not now") { goToProfile() }
            }
        }
        .padding(.vertical, 40)
    }

    private var profileStep: some View {
        VStack(spacing: 0) {
            stepTitle("Confirm your details", subtitle: "Pre-filled from Apple Health where available — adjust anything that's off.")
            Form {
                ProfileFieldsView(draft: $draft)
            }
            .scrollContentBackground(.hidden)
            primaryButton("Continue", disabled: nameEmpty) {
                model.saveConfirmedProfile(draft)
                step = .scale
            }
        }
        .padding(.top, 32)
        .padding(.bottom, 32)
    }

    private var scaleStep: some View {
        VStack(spacing: 0) {
            Spacer()
            if bleUnavailable {
                header(icon: "antenna.radiowaves.left.and.right.slash",
                       title: "Bluetooth needed",
                       subtitle: model.bleStatus.label)
            } else if let candidate = model.scaleCandidate {
                VStack(spacing: 16) {
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
                    Text(model.bleStatus.label)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(spacing: 12) {
                if let candidate = model.scaleCandidate, !bleUnavailable {
                    primaryButton("Yes, pair this scale") {
                        model.pairScale(candidate.peripheralID)
                        step = .done
                    }
                }
                secondaryButton(model.scaleCandidate == nil ? "Skip for now" : "Not my scale") {
                    step = .done
                }
            }
        }
        .padding(.vertical, 40)
        .onAppear { model.beginOnboardingScan() }
        .onDisappear { model.endOnboardingScan() }
    }

    private var doneStep: some View {
        VStack(spacing: 0) {
            Spacer()
            header(icon: "checkmark.circle.fill",
                   title: "You're all set",
                   subtitle: "Hi \(draft.name) — step on your scale anytime and your weigh-ins will appear here and in Apple Health.")
            Spacer()
            primaryButton("Start") { onFinish() }
        }
        .padding(.vertical, 40)
    }

    // MARK: - Helpers

    private var nameEmpty: Bool {
        draft.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var bleUnavailable: Bool {
        switch model.bleStatus {
        case .unsupported, .unauthorized, .poweredOff: return true
        default: return false
        }
    }

    private func goToProfile() {
        draft = model.profile
        step = .profile
    }

    private func header(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func stepTitle(_ title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private func primaryButton(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .controlSize(.large)
        .clipShape(.capsule)
        .disabled(disabled)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .tint(.secondary)
    }
}
