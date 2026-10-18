import SwiftUI
import Charts
import MyOpenScaleCore

/// The Goal tab: progress ring (with milestones and the plan marker), where the
/// goal sits on the BMI scale, the plan or forecast, milestones, maintenance
/// once reached, an optional body-fat goal, weigh-in consistency, and the path.
/// All judgements use the smoothed trend, never a single noisy weigh-in.
struct GoalPageView: View {
    @EnvironmentObject var model: AppModel
    @State private var editingGoal = false
    @State private var celebrating: Milestone?
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Derived state

    private var goal: Double? { model.profile.goalWeightKg }
    private var current: Double? { model.currentWeightKg }

    /// One-sided (causal) trend: the honest "where am I now".
    private var trend: [WeightSample] {
        WeightHistory.trend(WeightHistory.bucketed(model.weightHistory))
    }
    private var trendNow: Double? { trend.last?.weightKg ?? current }

    /// The weight/date the goal was set at; older profiles fall back to the
    /// earliest reading of the last 90 days.
    private var start: (kg: Double, date: Date)? {
        if let kg = model.profile.goalStartKg {
            return (kg, model.profile.goalSetAt ?? Date())
        }
        if let first = WeightHistory.filter(model.weightHistory, lastDays: 90, now: Date()).first {
            return (first.weightKg, first.date)
        }
        return current.map { ($0, Date()) }
    }

    private var plan: GoalPlan? {
        guard let g = goal, let s = start, let date = model.profile.goalTargetDate else { return nil }
        return GoalPlan(startKg: s.kg, startDate: s.date, goalKg: g, targetDate: date)
    }

    private var milestones: [Milestone] {
        guard let g = goal, let s = start else { return [] }
        return GoalInsights.milestones(startKg: s.kg, goalKg: g, startDate: s.date, trend: trend)
    }
    private var reachedCount: Int { milestones.filter { $0.reachedAt != nil }.count }

    /// The goal counts as reached once the trend got there (the last milestone
    /// is the goal itself); from then on the page is about keeping it. A goal
    /// set at (about) today's weight is a "keep this weight" goal right away.
    private var reached: Bool {
        if let last = milestones.last { return last.reachedAt != nil }
        guard let g = goal, let c = trendNow else { return false }
        return abs(c - g) < 0.25
    }

    private var weeklyRate: Double? { WeightHistory.weeklyRateKg(model.weightHistory, lastDays: 30, now: Date()) }

    private var weeksLeft: Double? {
        guard let c = trendNow, let g = goal, let r = weeklyRate else { return nil }
        return WeightHistory.weeksToGoal(currentKg: c, goalKg: g, weeklyRateKg: r)
    }

    private var etaDate: Date? {
        guard let w = weeksLeft, w <= 104 else { return nil }   // beyond 2 years isn't a forecast
        return Date().addingTimeInterval(w * 7 * 86_400)
    }

    private var progress: Double {
        guard let g = goal, let s = start, let c = trendNow else { return 0 }
        if reached { return 1 }
        return WeightHistory.goalProgress(startKg: s.kg, currentKg: c, goalKg: g) ?? 0
    }

    /// What Mochi's goal line is based on (only read while Mochi is on).
    private var mochiStatus: MochiGoalStatus {
        let hasGoal = goal != nil && current != nil
        return MochiGoalStatus(currentKg: trendNow,
                               reached: hasGoal && reached,
                               progress: hasGoal ? progress : nil,
                               daysInRange: hasGoal && reached ? goal.flatMap { GoalInsights.daysInRange(trend: trend, goalKg: $0) } : nil)
    }

    /// Changes when the goal, or which kind of line fits it, changes: Mochi then speaks anew.
    private var mochiTrigger: String {
        "\(model.profile.weightGoal.signature())|\(current != nil)|\(reached)"
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                GlassEffectContainer(spacing: 16) {
                    VStack(spacing: 16) {
                        MochiHomeCorner(mochi: model.mochi, presentation: \.goalPresentation,
                                        display: (trendNow ?? current)?.formatted(1) ?? "– –",
                                        onTap: { model.refreshMochiGoal(status: mochiStatus) })
                        if let celebrating { celebrationBanner(celebrating) }
                        if let g = goal, current != nil {
                            GoalRingView(progress: progress,
                                         milestoneFractions: milestoneFractions(goal: g),
                                         planFraction: planFraction(goal: g),
                                         center: AnyView(ringCenter(goal: g)))
                            BMIScaleView(currentKg: trendNow ?? current ?? g, goalKg: g,
                                         heightCm: model.profile.heightCm)
                            if reached { maintenanceCard(goal: g) } else { planCard(goal: g) }
                            if !milestones.isEmpty { milestonesCard }
                            bodyFatCard
                            consistencyCard
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
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $editingGoal) {
            GoalEditorView().environmentObject(model)
        }
        .onAppear {
            checkMilestones()
            model.refreshMochiGoalIfStale(status: mochiStatus)
        }
        .onChange(of: reachedCount) { _, _ in checkMilestones() }
        .onChange(of: mochiTrigger) { _, _ in model.refreshMochiGoal(status: mochiStatus) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshMochiGoalIfStale(status: mochiStatus) }
        }
    }

    // MARK: - Ring

    private func milestoneFractions(goal: Double) -> [(Double, Bool)] {
        guard let s = start, abs(goal - s.kg) >= 0.1 else { return [] }
        return milestones.dropLast().map { m in
            ((m.kg - s.kg) / (goal - s.kg), m.reachedAt != nil)
        }
    }

    private func planFraction(goal: Double) -> Double? {
        guard let plan, !reached else { return nil }
        return WeightHistory.goalProgress(startKg: plan.startKg,
                                          currentKg: plan.expectedKg(at: Date()), goalKg: goal)
    }

    @ViewBuilder
    private func ringCenter(goal: Double) -> some View {
        if reached {
            let days = GoalInsights.daysInRange(trend: trend, goalKg: goal)
            VStack(spacing: 4) {
                Image(systemName: days != nil ? "checkmark.seal.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(days != nil ? Theme.accent : .orange)
                Text(days != nil ? "In goal range" : "Outside goal range")
                    .font(.headline)
                if let days {
                    Text(days == 1 ? String(localized: "for 1 day") : String(localized: "for \(days) days"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } else if let c = trendNow {
            VStack(spacing: 2) {
                Text(abs(goal - c).formatted(1))
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                    .contentTransition(.numericText(value: abs(goal - c)))
                Text("kg to go")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                statusChip
                    .padding(.top, 4)
            }
        }
    }

    /// Plan status when there is a plan, otherwise the progress percentage.
    @ViewBuilder
    private var statusChip: some View {
        if let plan, let c = trendNow {
            let status = PlanStatus(aheadKg: plan.aheadKg(trendKg: c, at: Date()))
            let (text, tint): (String, Color) = {
                switch status {
                case .onPlan: return (String(localized: "On plan"), Theme.accent)
                case .ahead(let kg): return (String(localized: "\(kg.formatted(1)) kg ahead"), Theme.accent)
                case .behind(let kg): return (String(localized: "\(kg.formatted(1)) kg behind"), .orange)
                }
            }()
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(tint.opacity(0.14), in: .capsule)
        } else {
            Text("\(Int((progress * 100).rounded())) %")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
    }

    // MARK: - Plan / forecast

    private func planCard(goal: Double) -> some View {
        card(title: plan != nil ? "Plan" : "Forecast", icon: "calendar") {
            if let plan, let c = trendNow {
                VStack(alignment: .leading, spacing: 6) {
                    row("Target date") { Text(plan.targetDate, format: .dateTime.day().month(.wide).year()) }
                    if let needed = plan.requiredWeeklyRateKg(currentKg: c, now: Date()) {
                        row("Needed from now") { Text("\(signed(needed)) kg/wk") }
                    } else {
                        Text("The target date has passed — set a new one.")
                            .foregroundStyle(.orange)
                    }
                    if let rate = weeklyRate {
                        row("Your 30-day pace") { Text("\(signed(rate)) kg/wk") }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Group {
                        if let eta = etaDate, let rate = weeklyRate {
                            Text("At \(abs(rate).formatted(1)) kg per week you'll reach \(goal.formatted(1)) kg around \(eta, format: .dateTime.day().month(.wide).year()).")
                        } else if weeksLeft != nil, let rate = weeklyRate {
                            Text("At \(abs(rate).formatted(1)) kg per week, reaching \(goal.formatted(1)) kg would take more than two years.")
                        } else if weeklyRate == nil {
                            Text("Weigh in for a few more days to get a forecast.")
                        } else {
                            Text("Your 30-day trend is currently moving away from your goal.")
                        }
                    }
                    .foregroundStyle(.secondary)
                    Button { editingGoal = true } label: {
                        Label("Set a target date", systemImage: "calendar.badge.plus")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    // MARK: - Maintenance

    private func maintenanceCard(goal: Double) -> some View {
        card(title: "Keep it", icon: "shield.checkered") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your goal range is \((goal - 1).formatted(1))–\((goal + 1).formatted(1)) kg.")
                if let c = trendNow, abs(c - goal) > 1 {
                    if c > goal {
                        Text("Your trend is \((c - goal).formatted(1)) kg above your goal.")
                            .foregroundStyle(.orange)
                    } else {
                        Text("Your trend is \((goal - c).formatted(1)) kg below your goal.")
                            .foregroundStyle(.orange)
                    }
                } else {
                    Text("Daily ups and downs inside this range are normal.")
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Milestones

    private var milestonesCard: some View {
        let next = milestones.first { $0.reachedAt == nil }
        return card(title: "Milestones", icon: "flag.checkered",
                    accessory: AnyView(Text("\(reachedCount) of \(milestones.count)")
                        .font(.subheadline).foregroundStyle(.secondary))) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(milestones) { m in
                        milestoneChip(m, isNext: m.id == next?.id)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func milestoneChip(_ m: Milestone, isNext: Bool) -> some View {
        let isGoal = m.kg == goal
        return VStack(spacing: 3) {
            Image(systemName: m.reachedAt != nil ? "checkmark.circle.fill" : (isGoal ? "target" : "circle"))
                .font(.title3)
                .foregroundStyle(m.reachedAt != nil ? Theme.accent : (isNext ? Theme.accentSecondary : .secondary))
            Text("\(m.kg.formatted(1)) kg")
                .font(.caption.weight(.semibold).monospacedDigit())
            Group {
                if let date = m.reachedAt {
                    Text(date, format: .dateTime.day().month(.abbreviated))
                } else if isNext, let c = trendNow {
                    Text("\(abs(c - m.kg).formatted(1)) kg left")
                } else {
                    Text(verbatim: " ")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(minWidth: 64)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(isNext ? Theme.accentSecondary.opacity(0.12) : Color.clear, in: .rect(cornerRadius: 14))
    }

    private func celebrationBanner(_ m: Milestone) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "party.popper.fill")
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .symbolEffect(.bounce, value: m.kg)
            VStack(alignment: .leading, spacing: 2) {
                Text(m.kg == goal ? "Goal reached!" : "Milestone reached!")
                    .font(.headline)
                Text("\(m.kg.formatted(1)) kg")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { withAnimation(.snappy) { celebrating = nil } } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(16)
        .glassEffect(.regular.tint(Theme.accent.opacity(0.15)), in: .rect(cornerRadius: 22))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Celebrate milestones the trend passed since the page last looked. A goal
    /// that never counted before (older profile) starts silently at "all seen".
    private func checkMilestones() {
        guard goal != nil else { return }
        let count = reachedCount
        guard let seen = model.profile.goalMilestonesSeen else {
            markMilestonesSeen(count)
            return
        }
        if count > seen, let newest = milestones.last(where: { $0.reachedAt != nil }) {
            withAnimation(.snappy) { celebrating = newest }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        if count != seen { markMilestonesSeen(count) }
    }

    private func markMilestonesSeen(_ count: Int) {
        var updated = model.profile
        updated.goalMilestonesSeen = count
        model.saveProfile(updated)
    }

    // MARK: - Body fat

    @ViewBuilder
    private var bodyFatCard: some View {
        let fat = model.latestValue(.bodyFat).flatMap { $0.isFinite ? $0 : nil }
        if let target = model.profile.goalBodyFatPercent {
            card(title: "Body-fat goal", icon: "drop.fill") {
                if let fat {
                    let startFat = model.profile.goalBodyFatStartPercent ?? fat
                    let p = GoalInsights.bodyFatProgress(startPercent: startFat, currentPercent: fat,
                                                         goalPercent: target) ?? (abs(fat - target) < 0.1 ? 1 : 0)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(fat.formatted(1)) %").font(.headline.monospacedDigit())
                            Spacer()
                            Text("Goal \(target.formatted(1)) %").foregroundStyle(.secondary)
                        }
                        ProgressView(value: p).tint(.orange)
                        if abs(fat - target) < 0.1 {
                            Text("Body-fat goal reached.").foregroundStyle(.secondary)
                        } else {
                            Text("\(abs(fat - target).formatted(1)) % to go.").foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Weigh in on your scale to track body fat.")
                        .foregroundStyle(.secondary)
                }
            }
        } else if fat != nil {
            Button { editingGoal = true } label: {
                Label("Add a body-fat goal", systemImage: "drop")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .glassEffect(in: .rect(cornerRadius: 22))
        }
    }

    // MARK: - Consistency

    private var consistencyCard: some View {
        let days = GoalInsights.weighInDays(model.weightHistory, days: 14, now: Date())
        let count = days.filter { $0 }.count
        return card(title: "Consistency", icon: "calendar.badge.checkmark") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Weighed in on \(count) of the last 14 days")
                HStack(spacing: 6) {
                    ForEach(Array(days.enumerated()), id: \.offset) { _, logged in
                        Circle()
                            .fill(logged ? Theme.accent : Theme.accent.opacity(0.15))
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
                if count < 7 {
                    Text("Weighing in most days makes your trend and forecast more reliable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Path chart

    /// Smoothed trend since the goal was set (at least 30 days), the goal line,
    /// the plan with its ±0.5 kg corridor (or a dashed forecast without a
    /// plan), and the ±1 kg goal range once reached.
    @ViewBuilder
    private func pathChart(goal: Double) -> some View {
        let since = start.map { min($0.date, Date().addingTimeInterval(-30 * 86_400)) }
            ?? Date().addingTimeInterval(-90 * 86_400)
        let days = max(30, Int(Date().timeIntervalSince(since) / 86_400) + 1)
        let smooth = WeightHistory.filter(
            WeightHistory.trend(WeightHistory.bucketed(model.weightHistory), halfLifeDays: 6, centered: true),
            lastDays: days, now: Date())
        if smooth.count >= 2, let first = smooth.first, let last = smooth.last {
            let planPoints: [(Date, Double)] = plan.map { p in
                [(p.startDate, p.startKg), (p.targetDate, p.goalKg)]
            } ?? []
            let projection: [(Date, Double)] = (plan == nil && !reached)
                ? (etaDate.map { [(last.date, last.weightKg), ($0, goal)] } ?? []) : []
            let extra = (planPoints + projection).map { WeightSample(id: UUID(), date: $0.0, weightKg: $0.1) }
            let axis = WeightHistory.chartAxis(for: smooth + extra
                + [WeightSample(id: UUID(), date: last.date, weightKg: goal)])
            card(title: "Your path", icon: "point.topleft.down.to.point.bottomright.curvepath") {
                Chart {
                    if reached {
                        RectangleMark(xStart: .value("Date", first.date), xEnd: .value("Date", last.date),
                                      yStart: .value("Weight", goal - 1), yEnd: .value("Weight", goal + 1))
                            .foregroundStyle(Theme.accent.opacity(0.1))
                    }
                    ForEach(Array(planPoints.enumerated()), id: \.offset) { _, p in
                        AreaMark(x: .value("Date", p.0),
                                 yStart: .value("Weight", p.1 - 0.5), yEnd: .value("Weight", p.1 + 0.5),
                                 series: .value("Series", "Corridor"))
                            .foregroundStyle(Theme.accentSecondary.opacity(0.12))
                        LineMark(x: .value("Date", p.0), y: .value("Weight", p.1),
                                 series: .value("Series", "Plan"))
                            .foregroundStyle(Theme.accentSecondary.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    }
                    ForEach(smooth) { t in
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

    // MARK: - Helpers

    private func card<Content: View>(title: LocalizedStringKey, icon: String,
                                     accessory: AnyView? = nil,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: icon).font(.headline)
                Spacer()
                accessory
            }
            content()
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 22))
    }

    private func row<V: View>(_ label: LocalizedStringKey, @ViewBuilder value: () -> V) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            value().fontWeight(.semibold)
        }
    }

    private func signed(_ kg: Double) -> String {
        kg.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always(includingZero: false)))
    }
}

// MARK: - Ring

/// Progress ring with milestone dots on the track and an outside marker for
/// where the plan says you should be today.
private struct GoalRingView: View {
    let progress: Double
    let milestoneFractions: [(Double, Bool)]
    let planFraction: Double?
    let center: AnyView

    private let size: CGFloat = 230
    private let line: CGFloat = 18

    var body: some View {
        ZStack {
            Circle().stroke(Theme.accent.opacity(0.15), lineWidth: line)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(AngularGradient(colors: [Theme.accentSecondary, Theme.accent],
                                        center: .center, startAngle: .degrees(0),
                                        endAngle: .degrees(360 * max(0.05, progress))),
                        style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.snappy, value: progress)
            ForEach(Array(milestoneFractions.enumerated()), id: \.offset) { _, m in
                Circle()
                    .fill(m.1 ? Color.white : Theme.accent.opacity(0.35))
                    .frame(width: 7, height: 7)
                    .offset(y: -size / 2)
                    .rotationEffect(.degrees(360 * m.0))
            }
            if let plan = planFraction {
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.accentSecondary)
                    .offset(y: -size / 2 - line)
                    .rotationEffect(.degrees(360 * plan))
                    .accessibilityLabel("Plan for today")
            }
            center
        }
        .frame(width: size, height: size)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
    }
}
