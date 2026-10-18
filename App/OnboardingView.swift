import SwiftUI
import MyOpenScaleCore

/// First-launch welcome flow: welcome (continue with or without Mochi) → connect Apple
/// Health (pre-fill) → confirm details & goal → smart scale? (pair it, or carry on with
/// manual entry) → reminders (Mochi only) → done. Driven entirely by `AppModel` (which already owns Health + BLE).
/// With Mochi on, Mochi and a speech bubble replace each step's header icon; with
/// Mochi off, the steps look as they always did. `onFinish` flips the app to the dashboard.
struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    let onFinish: () -> Void

    enum Step: String { case welcome, health, profile, scale, reminders, done }
    /// The Welcome screen's choice; mirrors `model.mochi.settings.enabled` once made.
    enum MochiChoice { case undecided, with, without }

    @State private var step: Step = .welcome
    @State private var draft = StoredProfile.makeDefault()
    @State private var healthBusy = false
    @State private var choice: MochiChoice = .undecided
    /// "Continue without Mochi" was tapped: Mochi waves sadly, then fades out.
    @State private var declining = false
    @State private var mochiFading = false
    /// The scale step's "Pair my scale" was tapped: Bluetooth is on and we're looking.
    @State private var scaleSearching = false

    private static let declineHold: Duration = .milliseconds(3500)

    private var mochiEnabled: Bool { choice == .with }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            content
                .padding(.horizontal, 24)
                .frame(maxWidth: 520)
        }
        .animation(.snappy, value: step)
        .animation(.snappy, value: choice)
        #if DEBUG
        .onAppear(perform: applyDebugLaunchStep)
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcomeStep
        case .health: healthStep
        case .profile: profileStep
        case .scale: scaleStep
        case .reminders: remindersStep
        case .done: doneStep
        }
    }

    // MARK: - Steps

    /// The normal Welcome screen. Until the user picks, a small Mochi sits next to the
    /// choice; with Mochi it takes over the header and waves hello, without it waves sadly,
    /// fades out, and the plain Welcome remains. Either way "Get Started" then carries on.
    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()
            header(icon: "scalemass.fill",
                   mochi: .helloWave, says: "Hi, I'm Mochi! Let's get you set up together 💚",
                   title: "Welcome",
                   subtitle: "Step on your body-composition scale and your weigh-ins flow straight into Apple Health — body fat, lean mass and BMI computed on-device. No accounts, no cloud.")
            Spacer()
            VStack(spacing: 12) {
                if choice == .undecided {
                    mochiChoice
                } else {
                    primaryButton("Get Started") { step = .health }
                }
                Text("Body-composition values are estimates, not medical advice.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 40)
        .task(id: declining) {
            guard declining else { return }
            try? await Task.sleep(for: Self.declineHold)
            guard !Task.isCancelled else { return }
            leaveDecline()
        }
    }

    /// Small Mochi introducing the choice (or saying goodbye), and the two ways to continue.
    private var mochiChoice: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 6) {
                MochiView(pose: declining ? .sadWave : .helloWave, size: 76,
                          onTap: declining ? { leaveDecline() } : nil)
                Group {
                    if declining {
                        MochiSpeechBubble(text: String(localized: "Okay! If you ever want me, I'm in Settings 💚"),
                                          maxWidth: 240)
                    } else {
                        Text("You can set things up with Mochi, your little scale buddy, or on your own.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .id(declining)
                .accessibilityElement(children: .combine)
            }
            .opacity(mochiFading ? 0 : 1)
            // Tapping Mochi or its goodbye skips the wait (not the whole screen: the
            // "without" button's own tap must not end the sad wave at once).
            .contentShape(Rectangle())
            .onTapGesture { if declining { leaveDecline() } }
            VStack(spacing: 12) {
                primaryButton("Continue with Mochi") { acceptMochi() }
                secondaryButton("Continue without Mochi") { declineMochi() }
            }
            .opacity(declining ? 0 : 1)
            .disabled(declining)
        }
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

    /// Asks first — nothing touches Bluetooth (or its permission prompt) until "Pair my
    /// scale"; "No scale" carries on to manual entry.
    @ViewBuilder
    private var scaleStep: some View {
        if scaleSearching { scaleSearchStep } else { scaleChoiceStep }
    }

    private var scaleChoiceStep: some View {
        VStack(spacing: 0) {
            Spacer()
            header(icon: "scalemass.fill",
                   mochi: .helloWave, says: "Got a scale? I can read it for you!",
                   title: "Do you have a smart scale?",
                   subtitle: "Pair it once and every weigh-in, with body fat, lean mass and BMI, goes to Apple Health by itself.")
            supportedScale
                .padding(.top, 24)
            Spacer()
            VStack(spacing: 12) {
                primaryButton("Pair my scale") {
                    scaleSearching = true
                    model.beginPairingScan()
                }
                secondaryButton("No scale — I'll add weights by hand") { step = stepAfterScale }
            }
        }
        .padding(.vertical, 40)
    }

    /// The one supported scale, and that we're not Xiaomi.
    private var supportedScale: some View {
        HStack(spacing: 14) {
            Image(systemName: "scalemass.fill")
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Works with: Xiaomi Mi Body Composition Scale 2")
                    .font(.subheadline.weight(.semibold))
                Text("Not affiliated with or endorsed by Xiaomi.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .glassEffect(in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private var scaleSearchStep: some View {
        VStack(spacing: 0) {
            Spacer()
            if mochiEnabled {
                if bleUnavailable {
                    mochiHost(.idle, says: "I need Bluetooth to find your scale 💚")
                        .padding(.bottom, 24)
                } else {
                    mochiHost(model.scaleCandidate == nil ? .waiting : .thumbsUp,
                              says: "Hop on your scale, I'll look for it!")
                        .padding(.bottom, 24)
                }
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
                   subtitle: model.hasPairedScale
                   ? "Hi \(draft.name) — step on your scale anytime and your weigh-ins will appear here and in Apple Health."
                   : "Hi \(draft.name) — add your weight anytime in the Weigh in tab and it will appear here and in Apple Health.")
            Spacer()
            primaryButton("Start") { onFinish() }
        }
        .padding(.vertical, 40)
    }

    // MARK: - Mochi

    private func acceptMochi() {
        // Reminders stay off until the reminders step asks (an app kill in between leaves them off).
        model.mochi.settings.remindersEnabled = false
        model.mochi.settings.enabled = true
        choice = .with
    }

    private func declineMochi() {
        model.mochi.settings.enabled = false
        withAnimation(.easeInOut(duration: 0.3)) { declining = true }
    }

    /// End of the sad wave (timer or tap): fade Mochi out (opacity only), then the plain Welcome stays.
    private func leaveDecline() {
        guard step == .welcome, declining, !mochiFading else { return }
        withAnimation(.easeOut(duration: 0.5)) {
            mochiFading = true
        } completion: {
            declining = false
            mochiFading = false
            choice = .without
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
    /// `-onboardingStep <step>|declined|scaleSearch` on launch jumps to that step (simulator
    /// screenshots); `-mochiEnabled YES|NO` alongside it makes the Welcome choice (with /
    /// without Mochi). `welcome` without `-mochiEnabled` shows the undecided choice; `declined`
    /// the sad wave; `scaleSearch` the scale step after "Pair my scale" (starts Bluetooth).
    private func applyDebugLaunchStep() {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: "onboardingStep") else { return }
        if defaults.object(forKey: "mochiEnabled") != nil {
            model.mochi.settings.enabled = defaults.bool(forKey: "mochiEnabled")
            choice = model.mochi.settings.enabled ? .with : .without
        }
        if raw == "declined" {
            choice = .undecided
            declineMochi()
        } else if raw == "scaleSearch" {
            step = .scale
            scaleSearching = true
            model.beginPairingScan()
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

    private var bleUnavailable: Bool { model.bleStatus.isUnavailable }

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
