import SwiftUI
import Charts
import MyOpenScaleCore

/// The goal page, left of the weight page in Overview: how far along the user
/// is, what the current trend predicts, and the path there.
struct GoalPageView: View {
    @EnvironmentObject var model: AppModel
    @State private var editingGoal = false

    private var goal: Double? { model.profile.goalWeightKg }
    private var current: Double? { model.currentWeightKg }

    /// The weight the goal was set at; older profiles (before this was stored)
    /// fall back to the earliest reading of the last 90 days.
    private var start: Double? {
        if let s = model.profile.goalStartKg { return s }
        return WeightHistory.filter(model.weightHistory, lastDays: 90, now: Date()).first?.weightKg ?? current
    }

    private var weeklyRate: Double? { WeightHistory.weeklyRateKg(model.weightHistory, lastDays: 30, now: Date()) }

    private var weeksLeft: Double? {
        guard let c = current, let g = goal, let r = weeklyRate else { return nil }
        return WeightHistory.weeksToGoal(currentKg: c, goalKg: g, weeklyRateKg: r)
    }

    private var etaDate: Date? {
        guard let w = weeksLeft, w <= 104 else { return nil }   // beyond 2 years isn't a forecast
        return Date().addingTimeInterval(w * 7 * 86_400)
    }

    private var reached: Bool {
        guard let c = current, let g = goal, let s = start else { return false }
        return abs(c - g) < 0.1 || (s > g ? c <= g : c >= g)
    }

    var body: some View {
        NavigationStack {
            content
                .background(Theme.backgroundGradient.ignoresSafeArea())
                .toolbarVisibility(.hidden, for: .navigationBar)
        }
    }

    private var content: some View {
        ScrollView {
            GlassEffectContainer(spacing: 16) {
                VStack(spacing: 16) {
                    if let g = goal, let c = current {
                        progressRing(goal: g, current: c)
                        milestones(goal: g, current: c)
                        forecastCard(goal: g, current: c)
                        pathChart(goal: g)
                        Button { editingGoal = true } label: {
                            Label("Change goal", systemImage: "pencil")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .tint(Theme.accent)
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $editingGoal) {
            GoalEditorView().environmentObject(model)
        }
    }

    // MARK: - Progress

    private func progressRing(goal: Double, current: Double) -> some View {
        let progress = start.flatMap { WeightHistory.goalProgress(startKg: $0, currentKg: current, goalKg: goal) } ?? 0
        return ZStack {
            Circle()
                .stroke(Theme.accent.opacity(0.15), lineWidth: 18)
            Circle()
                .trim(from: 0, to: reached ? 1 : progress)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.snappy, value: progress)
            VStack(spacing: 2) {
                if reached {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Theme.accent)
                    Text("Goal reached")
                        .font(.title3.weight(.semibold))
                } else {
                    Text("\(abs(goal - current).formatted(1))")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .contentTransition(.numericText(value: abs(goal - current)))
                    Text("kg to go")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("\(Int((progress * 100).rounded())) %")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 2)
                }
            }
        }
        .frame(width: 220, height: 220)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    private func milestones(goal: Double, current: Double) -> some View {
        HStack(spacing: 0) {
            milestone("Start", start, detail: model.profile.goalSetAt.map {
                Text($0, format: .dateTime.day().month(.abbreviated))
            })
            Rectangle().fill(.secondary.opacity(0.25)).frame(width: 1, height: 36)
            milestone("Current", current, detail: nil)
            Rectangle().fill(.secondary.opacity(0.25)).frame(width: 1, height: 36)
            // The goal itself is the obvious place to change it.
            Button { editingGoal = true } label: {
                milestone("Goal", goal,
                          detail: Text("\(Image(systemName: "pencil")) Change"),
                          tint: Theme.accentSecondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edit your goal weight")
        }
        .padding(.vertical, 14)
        .glassEffect(in: .rect(cornerRadius: 22))
    }

    private func milestone(_ title: LocalizedStringKey, _ kg: Double?, detail: Text?, tint: Color = .primary) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(kg.map { "\($0.formatted(1)) kg" } ?? "—")
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
            if let detail { detail.font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Forecast

    private func forecastCard(goal: Double, current: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Forecast", systemImage: "calendar")
                .font(.headline)
            Group {
                if reached {
                    Text("You've reached your goal. Keep your weight here, or set a new goal.")
                } else if let eta = etaDate, let rate = weeklyRate {
                    Text("At \(abs(rate).formatted(1)) kg per week you'll reach \(goal.formatted(1)) kg around \(eta, format: .dateTime.day().month(.wide).year()).")
                } else if weeksLeft != nil, let rate = weeklyRate {
                    Text("At \(abs(rate).formatted(1)) kg per week, reaching \(goal.formatted(1)) kg would take more than two years.")
                } else if weeklyRate == nil {
                    Text("Weigh in for a few more days to get a forecast.")
                } else {
                    Text("Your 30-day trend is currently moving away from your goal.")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 22))
    }

    // MARK: - Path chart

    /// Smoothed trend since the goal was set (at least the last 30 days), the
    /// goal line, and a dashed projection to the forecast date.
    @ViewBuilder
    private func pathChart(goal: Double) -> some View {
        let since = model.profile.goalSetAt.map { min($0, Date().addingTimeInterval(-30 * 86_400)) }
            ?? Date().addingTimeInterval(-90 * 86_400)
        let days = max(30, Int(Date().timeIntervalSince(since) / 86_400) + 1)
        let trend = WeightHistory.filter(
            WeightHistory.trend(WeightHistory.bucketed(model.weightHistory), halfLifeDays: 6, centered: true),
            lastDays: days, now: Date())
        if trend.count >= 2, let last = trend.last {
            let projection = etaDate.map { [(last.date, last.weightKg), ($0, goal)] } ?? []
            let axis = WeightHistory.chartAxis(for: trend + [WeightSample(id: UUID(), date: last.date, weightKg: goal)])
            VStack(alignment: .leading, spacing: 10) {
                Label("Your path", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.headline)
                Chart {
                    ForEach(trend) { t in
                        LineMark(x: .value("Date", t.date), y: .value("Weight", t.weightKg),
                                 series: .value("Series", "Trend"))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Theme.accent)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    }
                    ForEach(Array(projection.enumerated()), id: \.offset) { _, p in
                        LineMark(x: .value("Date", p.0), y: .value("Weight", p.1),
                                 series: .value("Series", "Forecast"))
                            .foregroundStyle(Theme.accent.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    }
                    RuleMark(y: .value("Goal", goal))
                        .foregroundStyle(Theme.accentSecondary.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
                .chartYScale(domain: axis.domain)
                .chartYAxis {
                    AxisMarks(position: .leading, values: axis.ticks) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let kg = value.as(Double.self) { Text(kg.formatted(axis.strideKg < 1 ? 1 : 0)) }
                        }
                    }
                }
                .frame(height: 180)
            }
            .padding(16)
            .glassEffect(in: .rect(cornerRadius: 26))
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "target")
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)
            Text("Set a goal")
                .font(.title2.weight(.bold))
            Text("Pick a target weight and see your progress, a forecast and the path there.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { editingGoal = true } label: {
                Text("Set goal")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Theme.accent)
            .padding(.top, 6)
            .disabled(current == nil)
            if current == nil {
                Text("Add a first weigh-in to set a goal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassEffect(in: .rect(cornerRadius: 26))
        .padding(.top, 40)
    }
}
