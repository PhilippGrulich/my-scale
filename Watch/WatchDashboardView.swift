import SwiftUI

/// Watch home screen: latest weight + trend, and the big "Weigh In" button that
/// starts a standalone capture. Falls back to a setup prompt when we still need
/// the user's height.
struct WatchDashboardView: View {
    @EnvironmentObject var model: WatchAppModel
    @State private var didRequestAuth = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if model.needsSetup {
                        setupPrompt
                    } else {
                        latestWeight
                        weighInButton
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
        VStack(spacing: 4) {
            if let weight = model.currentWeightKg {
                Text(weight.formatted(1))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .contentTransition(.numericText(value: weight))
                Text("kg")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let delta = model.trendDeltaKg, abs(delta) >= 0.05 {
                    Label("\(delta > 0 ? "+" : "")\(delta.formatted(1)) kg",
                          systemImage: delta > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2)
                        .foregroundStyle(delta > 0 ? .orange : .green)
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
        .padding(.top, 4)
    }

    private var weighInButton: some View {
        Button {
            model.startWeighIn()
        } label: {
            Label("Weigh In", systemImage: "figure.stand")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
    }

    // MARK: - Setup prompt

    private var setupPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "ruler")
                .font(.system(size: 32))
                .foregroundStyle(.blue)
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
            .tint(.blue)
        }
        .padding(.top, 8)
    }
}
