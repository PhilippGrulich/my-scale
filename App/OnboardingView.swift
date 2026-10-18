import SwiftUI
import MyOpenScaleCore

/// First-launch welcome flow: meet Mochi (yes / no) → intro → connect Apple Health
/// (pre-fill) → confirm details & goal → find & remember the scale → reminders (Mochi
/// only) → done. Driven entirely by `AppModel` (which already owns Health + BLE).
/// With Mochi on, Mochi and a speech bubble replace each step's header icon; with
/// Mochi off, the steps look as they always did. `onFinish` flips the app to the dashboard.
struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    let onFinish: () -> Void

    enum Step: String { case meetMochi, welcome, health, profile, scale, reminders, done }

    @State private var step: Step = .meetMochi
    @State private var draft = StoredProfile.makeDefault()
    @State private var healthBusy = false
    /// Mirrors `model.mochi.settings.enabled` as decided on the first step.
    @State private var mochiEnabled = false
    /// "No thanks" was tapped: Mochi waves sadly, then fades out.
    @State private var declined = false
    @State private var mochiFading = false

    private static let declineHold: Duration = .milliseconds(2500)

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            content
                .padding(.horizontal, 24)
                .frame(maxWidth: 520)
        }
        .animation(.snappy, value: step)
        #if DEBUG
        .onAppear(perform: applyDebugLaunchStep)
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .meetMochi: meetMochiStep
        case .welcome: welcomeStep
        case .health: healthStep
        case .profile: profileStep
        case .scale: scaleStep
        case .reminders: remindersStep
        case .done: doneStep
        }
    }

    // MARK: - Steps

    private var meetMochiStep: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(alignment: .center, spacing: 4) {
                MochiView(pose: declined ? .sadWave : .helloWave, size: 130,
                          onTap: declined ? { leaveDecline() } : nil)
                MochiSpeechBubble(text: declined
                                  ? String(localized: "Okay! If you ever want me, I'm in Settings 💚")
                                  : String(localized: "Hi, I'm Mochi! Want me to help you reach your goal?"),
                                  maxWidth: 210)
                    .id(declined)
                    .accessibilityElement(children: .combine)
            }
            .opacity(mochiFading ? 0 : 1)
            Spacer()
            VStack(spacing: 12) {
                primaryButton("Yes, let's go!") { acceptMochi() }
                secondaryButton("No thanks") { declineMochi() }
            }
            .opacity(declined ? 0 : 1)
            .disabled(declined)
        }
        .padding(.vertical, 40)
        .contentShape(Rectangle())
        .onTapGesture { if declined { leaveDecline() } }
        .task(id: declined) {
            guard declined else { return }
            try? await Task.sleep(for: Self.declineHold)
            guard !Task.isCancelled else { return }
            leaveDecline()
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()
            header(icon: "scalemass.fill",
                   mochi: .helloWave, says: "Let's get you set up!",
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
                   mochi: .idle, says: "I'll read a few details from Apple Health so the maths is right.",
                   title: "Connect Apple Health",
                   subtitle: mochiEnabled
                   ? "Age, height and biological sex for body composition. Each weigh-in is saved back to Health."
                   : "We'll read your age, height and biological sex to calculate body composition, and save each weigh-in back to Health.")
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
            if mochiEnabled {
                mochiHost(.idle, says: "Tell me a bit about you!")
                    .padding(.bottom, 8)
            }
            stepTitle("Confirm your details", subtitle: "Pre-filled from Apple Health where available — adjust anything that's off.")
            Form {
                ProfileFieldsView(draft: $draft)
                GoalFieldsView(draft: $draft, currentWeightKg: model.currentWeightKg)
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
            if mochiEnabled {
                mochiHost(model.scaleCandidate == nil ? .waiting : .thumbsUp,
                          says: "Hop on your scale, I'll look for it!")
                    .padding(.bottom, 24)
            }
            if bleUnavailable {
                header(icon: "antenna.radiowaves.left.and.right.slash",
                       title: "Bluetooth needed",
                       subtitle: "\(model.bleStatus.label)")
            } else if let candidate = model.scaleCandidate {
                VStack(spacing: 16) {
                    if !mochiEnabled {
                        Image(systemName: "scalemass.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(Theme.accent)
                            .symbolEffect(.pulse)
                    }
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
                    Text(mochiEnabled ? "Looking for your scale…" : "Step on your scale now")
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
                        step = stepAfterScale
                    }
                }
                secondaryButton(model.scaleCandidate == nil ? "Skip for now" : "Not my scale") {
                    step = stepAfterScale
                }
            }
        }
        .padding(.vertical, 40)
        .onAppear { model.beginPairingScan() }
        .onDisappear { model.endPairingScan() }
    }

    /// Mochi-only: may Mochi send weigh-in reminders?
    private var remindersStep: some View {
        VStack(spacing: 0) {
            Spacer()
            header(icon: "bell.badge.fill",
                   mochi: .bellRing, says: "Can I nudge you when it's time to weigh in?",
                   title: "Reminders",
                   subtitle: "A gentle nudge around your usual weigh-in time. You can change it anytime in Settings.")
            Spacer()
            VStack(spacing: 12) {
                primaryButton("Yes, remind me") {
                    model.mochi.settings.remindersEnabled = true
                    model.requestNotificationAuthorization()
                    step = .done
                }
                secondaryButton("Not now") {
                    model.mochi.settings.remindersEnabled = false
                    step = .done
                }
            }
        }
        .padding(.vertical, 40)
    }

    private var doneStep: some View {
        VStack(spacing: 0) {
            Spacer()
            header(icon: "checkmark.circle.fill",
                   mochi: .confetti, says: "We're a team now! 🎉",
                   title: "You're all set",
                   subtitle: "Hi \(draft.name) — step on your scale anytime and your weigh-ins will appear here and in Apple Health.")
            Spacer()
            primaryButton("Start") { onFinish() }
        }
        .padding(.vertical, 40)
    }

    // MARK: - Mochi

    private func acceptMochi() {
        model.mochi.settings.enabled = true
        mochiEnabled = true
        step = .welcome
    }

    private func declineMochi() {
        model.mochi.settings.enabled = false
        mochiEnabled = false
        withAnimation(.easeInOut(duration: 0.3)) { declined = true }
    }

    /// End of the sad wave (timer or tap): fade Mochi out (opacity only), then carry on.
    private func leaveDecline() {
        guard step == .meetMochi, declined, !mochiFading else { return }
        withAnimation(.easeOut(duration: 0.5)) {
            mochiFading = true
        } completion: {
            step = .welcome
        }
    }

    private var stepAfterScale: Step { mochiEnabled ? .reminders : .done }

    /// Small Mochi with a step-specific line, used in place of a step's header icon.
    private func mochiHost(_ pose: MochiPose, says line: LocalizedStringResource) -> some View {
        HStack(alignment: .center, spacing: 4) {
            MochiView(pose: pose, size: 90)
            MochiSpeechBubble(text: String(localized: line), maxWidth: 230)
                .accessibilityElement(children: .combine)
        }
    }

    #if DEBUG
    /// `-onboardingStep <step>|declined` on launch jumps to that step (simulator screenshots);
    /// `-mochiEnabled YES|NO` alongside it sets Mochi on or off.
    private func applyDebugLaunchStep() {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: "onboardingStep") else { return }
        if defaults.object(forKey: "mochiEnabled") != nil {
            model.mochi.settings.enabled = defaults.bool(forKey: "mochiEnabled")
        }
        mochiEnabled = model.mochi.settings.enabled
        if raw == "declined" {
            declineMochi()
        } else if let jump = Step(rawValue: raw) {
            if jump == .profile || jump == .done { draft = model.profile }
            step = jump
        }
    }
    #endif

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

    /// Step header: with Mochi on, Mochi saying `line` replaces the icon (no line: the
    /// step shows its own Mochi elsewhere, so neither is drawn here).
    private func header(icon: String, mochi pose: MochiPose = .idle, says line: LocalizedStringResource? = nil,
                        title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(spacing: 18) {
            if mochiEnabled {
                if let line { mochiHost(pose, says: line) }
            } else {
                Image(systemName: icon)
                    .font(.system(size: 60))
                    .foregroundStyle(Theme.accent)
            }
            Text(title)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func stepTitle(_ title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
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

    private func primaryButton(_ title: LocalizedStringKey, disabled: Bool = false, action: @escaping () -> Void) -> some View {
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

    private func secondaryButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
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
