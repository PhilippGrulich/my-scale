import SwiftUI
import Charts
import MyOpenScaleCore

/// The watch app as vertical pages (scroll with the Digital Crown), each one
/// self-contained — no sheets or pushed screens: Today (Mochi + weight +
/// trend), Goal (ring), Body (values + chart), Manual (enter a weight here) and,
/// when a scale is paired on the phone, Scale (scans while the page is shown —
/// watchOS only allows Bluetooth in the foreground — and shows the result).
struct WatchDashboardView: View {
    @EnvironmentObject var model: WatchAppModel
    @State private var didRequestAuth = false

    enum Page: Hashable { case today, goal, body, manual, scale }
    @State private var page: Page = .today

    var body: some View {
        NavigationStack {
            Group {
                if model.needsSetup {
                    setupPage
                } else {
                    TabView(selection: $page) {
                        todayPage.tag(Page.today)
                        if model.goal.targetKg != nil, model.currentWeightKg != nil { goalPage.tag(Page.goal) }
                        if model.latestBodyFat != nil || model.bmi != nil || model.history.count >= 2 {
                            bodyPage.tag(Page.body)
                        }
                        manualPage.tag(Page.manual)
                        if model.hasScale { scalePage.tag(Page.scale) }
                    }
                    .tabViewStyle(.verticalPage)
                    .onChange(of: page) { old, new in pageChanged(from: old, to: new) }
                }
            }
        }
        .task {
            if !didRequestAuth {
                didRequestAuth = true
                model.requestAuthorizationAndSync()
            }
        }
    }

    // MARK: - Manual / Scale

    private var manualPage: some View {
        WatchManualEntryView()
            .containerBackground(Theme.accent.gradient.opacity(0.25), for: .tabView)
            .navigationTitle("Manual")
    }

    private var scalePage: some View {
        WatchWeighInView(onDone: {
            // Ready for the next person / weigh-in while the page stays open.
            model.done()
            model.startWeighIn()
        })
        .containerBackground(Theme.accentSecondary.gradient.opacity(0.25), for: .tabView)
        .navigationTitle("Scale")
    }

    /// Bluetooth only runs while the Scale page is on screen.
    private func pageChanged(from old: Page, to new: Page) {
        // Leaving the Manual page with its result showing resets it.
        if old == .manual, model.source == .manual, model.phase != .saving { model.done() }
        if new == .scale {
            if model.source == .manual, model.phase != .saving { model.done() }
            if model.phase == .idle { model.startWeighIn() }
        }
        if old == .scale, model.source == .scale {
            switch model.phase {
            case .saving: break          // let the Health write finish
            case .saved, .error: model.done()
            default: model.cancel()
            }
        }
    }

    // MARK: - Today

    private var todayPage: some View {
        VStack(spacing: 6) {
            if model.mochiEnabled, let home = model.mochi.home {
                WatchMochiRow(presentation: home, onTap: { model.refreshMochi(force: true) })
            }
            Spacer(minLength: 0)
            if let weight = model.currentWeightKg {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(weight.formatted(1))
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .contentTransition(.numericText(value: weight))
                        .minimumScaleFactor(0.7)
                    Text("kg").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                }
                trendLabel(weight)
            } else {
                Text("No weigh-ins yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .containerBackground(Theme.accent.gradient.opacity(0.35), for: .tabView)
    }

    @ViewBuilder
    private func trendLabel(_ weight: Double) -> some View {
        if let month = model.monthTrendKg {
            let flat = abs(month) < 0.05
            let toward = model.goal.isToward(fromKg: weight - month, toKg: weight)
            Label("\(abs(month).formatted(1)) kg / 30d",
                  systemImage: flat ? "arrow.right" : (month < 0 ? "arrow.down.right" : "arrow.up.right"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(flat ? .secondary : (toward ? Theme.accent : .orange))
        }
    }

    // MARK: - Goal

    private var goalPage: some View {
        let goal = model.goal
        let current = model.currentWeightKg ?? 0
        let target = goal.targetKg ?? current
        let reached = goal.isReached(current)
        let progress = reached ? 1 : (goal.progressFraction(current) ?? 0)
        return VStack(spacing: 8) {
            ZStack {
                Circle().stroke(Theme.accent.opacity(0.2), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: max(0.001, progress))
                    .stroke(AngularGradient(colors: [Theme.accentSecondary, Theme.accent], center: .center,
                                            startAngle: .degrees(0), endAngle: .degrees(360 * max(0.05, progress))),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    if reached {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.accent)
                    } else {
                        // Just the number in the ring; the words go below it.
                        Text(abs(target - current).formatted(1))
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.7)
                        Text("kg left")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: 128, height: 128)
            HStack(spacing: 4) {
                Text(reached ? String(localized: "Goal reached") : String(localized: "Goal \(target.formatted(1)) kg"))
                if !reached, goal.progressFraction(current) != nil {
                    Text(verbatim: "· \(Int((progress * 100).rounded())) %").foregroundStyle(Theme.accent)
                }
            }
            .font(.footnote.weight(.semibold))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .containerBackground(Theme.accentSecondary.gradient.opacity(0.35), for: .tabView)
        .navigationTitle("Goal")
    }

    // MARK: - Body

    private var bodyPage: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                if let fat = model.latestBodyFat {
                    value(icon: "drop.fill", tint: .orange, title: "Body Fat", text: "\(fat.formatted(1)) %")
                }
                if let bmi = model.bmi {
                    value(icon: "ruler.fill", tint: Theme.accent, title: "BMI", text: bmi.formatted(1))
                }
            }
            miniChart
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .containerBackground(Color.orange.gradient.opacity(0.25), for: .tabView)
        .navigationTitle("Body")
    }

    private func value(icon: String, tint: Color, title: LocalizedStringKey, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(text).font(.title3.weight(.bold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
    }

    /// 30-day smoothed trend, same maths as the phone chart.
    @ViewBuilder
    private var miniChart: some View {
        let trend = WeightHistory.filter(
            WeightHistory.trend(WeightHistory.bucketed(model.history), halfLifeDays: 3, centered: true),
            lastDays: 30, now: Date())
        if trend.count >= 2 {
            let axis = WeightHistory.chartAxis(for: trend)
            Chart(trend) { t in
                AreaMark(x: .value("Date", t.date), yStart: .value("Base", axis.domain.lowerBound),
                         yEnd: .value("Weight", t.weightKg))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Theme.accent.opacity(0.25))
                LineMark(x: .value("Date", t.date), y: .value("Weight", t.weightKg))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            .chartYScale(domain: axis.domain)
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Setup

    private var setupPage: some View {
        ScrollView {
            VStack(spacing: 10) {
                if model.mochiEnabled {
                    WatchMochiRow(presentation: MochiPresentation(
                        pose: .helloWave, text: String(localized: "Hi! I just need your height."), display: ""))
                }
                Text("We need your height to compute weight and body composition.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                NavigationLink {
                    WatchSetupView().environmentObject(model)
                } label: {
                    Text("Set Up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
        }
        .navigationTitle("Set your height")
    }
}
