import SwiftUI
import MyOpenScaleCore

/// Watch overview: Mochi's greeting, the latest weight with its 30-day trend,
/// goal progress (from the phone), body fat / BMI, and the two ways to add a
/// weight — the scale (foreground only on watchOS) or the Digital Crown.
struct WatchDashboardView: View {
    @EnvironmentObject var model: WatchAppModel
    @State private var didRequestAuth = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if model.needsSetup {
                        setupPrompt
                    } else {
                        if model.mochiEnabled, let home = model.mochi.home {
                            WatchMochiRow(presentation: home, onTap: { model.refreshMochi(force: true) })
                        }
                        latestWeight
                        if let goalKg = model.goal.targetKg, let current = model.currentWeightKg {
                            goalRow(goalKg: goalKg, current: current)
                        }
                        bodyValues
                        weighInButton
                        NavigationLink {
                            WatchManualEntryView().environmentObject(model)
                        } label: {
                            Label("Enter manually", systemImage: "digitalcrown.horizontal.arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("MyOpenScale")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            if !didRequestAuth {
                didRequestAuth = true
                model.requestAuthorizationAndSync()
            }
        }
        .sheet(isPresented: Binding(
            get: { model.phase.isActive },
            set: { active in if !active { model.done() } }
        )) {
            WatchWeighInView().environmentObject(model)
        }
    }

    // MARK: - Latest weight

    private var latestWeight: some View {
        VStack(spacing: 2) {
            if let weight = model.currentWeightKg {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(weight.formatted(1))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .contentTransition(.numericText(value: weight))
                    Text("kg").font(.caption).foregroundStyle(.secondary)
                }
                if let month = model.monthTrendKg {
                    let toward = model.goal.isToward(fromKg: weight - month, toKg: weight)
                    let flat = abs(month) < 0.05
                    Label("\(abs(month).formatted(1)) kg / 30d",
                          systemImage: flat ? "arrow.right" : (month < 0 ? "arrow.down.right" : "arrow.up.right"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(flat ? .secondary : (toward ? Theme.accent : .orange))
                }
            } else {
                Image(systemName: "scalemass")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text("No weigh-ins yet")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Goal

    private func goalRow(goalKg: Double, current: Double) -> some View {
        let progress = model.goal.progressFraction(current)
        let toGo = abs(goalKg - current)
        return HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Theme.accent.opacity(0.2), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: max(0.001, progress ?? (model.goal.isReached(current) ? 1 : 0)))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "target").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accent)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 0) {
                if model.goal.isReached(current) {
                    Text("Goal reached").font(.footnote.weight(.semibold))
                } else {
                    Text("\(toGo.formatted(1)) kg to go").font(.footnote.weight(.semibold))
                }
                Text("Goal \(goalKg.formatted(1)) kg").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(.gray.opacity(0.15), in: .rect(cornerRadius: 12))
    }

    // MARK: - Body values

    @ViewBuilder
    private var bodyValues: some View {
        if model.latestBodyFat != nil || model.bmi != nil {
            HStack(spacing: 6) {
                if let fat = model.latestBodyFat {
                    tile(icon: "drop.fill", tint: .orange, title: "Body Fat", value: "\(fat.formatted(1)) %")
                }
                if let bmi = model.bmi {
                    tile(icon: "ruler.fill", tint: Theme.accent, title: "BMI", value: bmi.formatted(1))
                }
            }
        }
    }

    private func tile(icon: String, tint: Color, title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(title, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value).font(.footnote.weight(.bold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.gray.opacity(0.15), in: .rect(cornerRadius: 12))
    }

    private var weighInButton: some View {
        Button {
            model.startWeighIn()
        } label: {
            Label("Weigh In", systemImage: "scalemass.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
    }

    // MARK: - Setup prompt

    private var setupPrompt: some View {
        VStack(spacing: 10) {
            if model.mochiEnabled {
                WatchMochiRow(presentation: MochiPresentation(
                    pose: .helloWave, text: String(localized: "Hi! I just need your height."), display: ""))
            } else {
                Image(systemName: "ruler")
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.accent)
            }
            Text("Set your height")
                .font(.headline)
            Text("We need your height to compute weight and body composition.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            NavigationLink {
                WatchSetupView().environmentObject(model)
            } label: {
                Text("Set Up")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .padding(.top, 4)
    }
}
