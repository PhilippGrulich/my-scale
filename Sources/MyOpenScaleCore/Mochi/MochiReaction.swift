import Foundation

/// Mochi's body poses; the app maps each to an animation.
public enum MochiPose: String, Codable, Sendable, CaseIterable {
    case idle, helloWave, thumbsUp, doubleThumbs, confetti, selfHug, bellRing, snoozing, sadWave, waiting, squishing, birthday
}

/// What Mochi is reacting to after a weigh-in.
public enum MochiEvent: Equatable, Codable, Sendable {
    case goalReached
    case milestonePercent(Int)
    case milestoneKg(Int)
    case newBest
    case streak(Int)
    case goodWeek
    case daysInRange(Int)
    case toward
    case away
    case notYou

    /// Key used to look up the speech line for this event.
    public var lineEvent: String {
        switch self {
        case .goalReached: return "goalReached"
        case .milestonePercent: return "milestonePercent"
        case .milestoneKg: return "milestoneKg"
        case .newBest: return "newBest"
        case .streak: return "streak"
        case .goodWeek: return "goodWeek"
        case .daysInRange: return "daysInRange"
        case .toward: return "toward"
        case .away: return "away"
        case .notYou: return "notYou"
        }
    }
}

/// Mochi's reaction to one weigh-in.
public struct MochiReaction: Equatable, Sendable {
    public var event: MochiEvent
    public var pose: MochiPose
    /// True when the previous weigh-in was 7+ days ago.
    public var isWelcomeBack: Bool
    /// New weight minus the previous reading; nil for the first reading.
    public var changeKg: Double?

    public init(event: MochiEvent, pose: MochiPose, isWelcomeBack: Bool, changeKg: Double?) {
        self.event = event
        self.pose = pose
        self.isWelcomeBack = isWelcomeBack
        self.changeKg = changeKg
    }
}

/// Persisted record of what Mochi already celebrated, so each celebration fires once per goal.
public struct MochiProgressState: Codable, Equatable, Sendable {
    /// `WeightGoal.signature()` this state belongs to; a mismatch resets the state.
    public var goalSignature: String
    public var bestKg: Double?
    /// Ids like `"pct:25"` and `"kg:3"`.
    public var firedMilestones: Set<String>
    public var lastStreakCelebrated: Int
    /// Start of the calendar week whose good week was last celebrated.
    public var lastGoodWeekStart: Date?
    /// Maintain: whether the previous reading was outside the band.
    public var wasOutsideBand: Bool
    public var goalReachedFired: Bool
    /// Maintain: in-range streak lengths already celebrated.
    public var firedRangeStreaks: Set<Int>

    public init(
        goalSignature: String,
        bestKg: Double?,
        firedMilestones: Set<String>,
        lastStreakCelebrated: Int,
        lastGoodWeekStart: Date?,
        wasOutsideBand: Bool,
        goalReachedFired: Bool,
        firedRangeStreaks: Set<Int>
    ) {
        self.goalSignature = goalSignature
        self.bestKg = bestKg
        self.firedMilestones = firedMilestones
        self.lastStreakCelebrated = lastStreakCelebrated
        self.lastGoodWeekStart = lastGoodWeekStart
        self.wasOutsideBand = wasOutsideBand
        self.goalReachedFired = goalReachedFired
        self.firedRangeStreaks = firedRangeStreaks
    }

    public static func fresh(for goal: WeightGoal) -> MochiProgressState {
        MochiProgressState(
            goalSignature: goal.signature(),
            bestKg: goal.startKg,
            firedMilestones: [],
            lastStreakCelebrated: 0,
            lastGoodWeekStart: nil,
            wasOutsideBand: false,
            goalReachedFired: false,
            firedRangeStreaks: []
        )
    }
}

/// Picks Mochi's reaction to a weigh-in. Every rule updates the state; the first rule that fires wins.
public enum MochiReactionEngine {
    /// Readings within this window before the new one are treated as the same weigh-in (e.g. Watch already saved it).
    static let duplicateWindow: TimeInterval = 60
    static let welcomeBackDays = 7
    static let goodWeekKg = 0.3
    static let percentMarks = [25, 50, 75]
    static let streakMarks: Set<Int> = [3, 5, 7, 10, 14, 21, 30]
    static let rangeStreakMarks = [7, 30, 100]
    /// Guards floor() against binary rounding like 75.3 - 74.3 = 0.99999…
    private static let epsilon = 1e-9

    public static func notYou() -> MochiReaction {
        MochiReaction(event: .notYou, pose: .idle, isWelcomeBack: false, changeKg: nil)
    }

    public static func react(
        newKg: Double,
        at date: Date,
        history: [WeightSample],
        goal: WeightGoal,
        state inputState: MochiProgressState,
        calendar: Calendar
    ) -> (MochiReaction, MochiProgressState) {
        var state = inputState.goalSignature == goal.signature() ? inputState : .fresh(for: goal)

        let cutoff = date.addingTimeInterval(-duplicateWindow)
        let prior = history.filter { $0.date < cutoff }
        let previousKg = prior.max(by: { $0.date < $1.date })?.weightKg
        let changeKg = previousKg.map { newKg - $0 }

        let newSample = WeightSample(id: UUID(), date: date, weightKg: newKg)
        let stats = MochiStats.compute(history: prior + [newSample], now: date, firstLaunch: date, goal: goal, calendar: calendar)
        let priorStats = MochiStats.compute(history: prior, now: date, firstLaunch: date, goal: goal, calendar: calendar)
        let isWelcomeBack = (priorStats.daysSinceLastWeighIn ?? 0) >= welcomeBackDays

        var winner: (MochiEvent, MochiPose)?
        func offer(_ event: MochiEvent?, _ pose: MochiPose) {
            if winner == nil, let event { winner = (event, pose) }
        }

        // Goal reached.
        var goalEvent: MochiEvent?
        if goal.type == .maintain {
            let inBand = goal.isInBand(newKg)
            if inBand && state.wasOutsideBand { goalEvent = .goalReached }
            state.wasOutsideBand = !inBand
        } else if goal.isReached(newKg) && !state.goalReachedFired {
            state.goalReachedFired = true
            goalEvent = .goalReached
        }
        offer(goalEvent, .confetti)

        // Milestones: percent of the way, and whole kg moved toward the goal.
        offer(milestone(newKg: newKg, goal: goal, state: &state), .confetti)

        // Maintain: days in range.
        var rangeEvent: MochiEvent?
        if goal.type == .maintain {
            let n = stats.daysInRangeStreak
            // A broken run lets the maintainer earn the same marks again.
            state.firedRangeStreaks = state.firedRangeStreaks.filter { $0 <= n }
            if rangeStreakMarks.contains(n) && !state.firedRangeStreaks.contains(n) {
                state.firedRangeStreaks.insert(n)
                rangeEvent = .daysInRange(n)
            }
        }
        offer(rangeEvent, .doubleThumbs)

        // New best.
        var bestEvent: MochiEvent?
        if let best = state.bestKg {
            if goal.isBetter(newKg, than: best) {
                state.bestKg = newKg
                bestEvent = .newBest
            }
        } else {
            state.bestKg = newKg
        }
        offer(bestEvent, .doubleThumbs)

        // Streak milestones.
        var streakEvent: MochiEvent?
        let streak = stats.streakDays
        if streak < state.lastStreakCelebrated { state.lastStreakCelebrated = 0 }
        if streak > 0, streakMarks.contains(streak) || streak % 30 == 0, streak > state.lastStreakCelebrated {
            state.lastStreakCelebrated = streak
            streakEvent = .streak(streak)
        }
        offer(streakEvent, .doubleThumbs)

        // Good week: at most once per calendar week.
        var weekEvent: MochiEvent?
        if let week = stats.weekChangeKg,
           abs(week) >= goodWeekKg - epsilon,
           goal.isToward(fromKg: newKg - week, toKg: newKg),
           let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start,
           state.lastGoodWeekStart != weekStart {
            state.lastGoodWeekStart = weekStart
            weekEvent = .goodWeek
        }
        offer(weekEvent, .doubleThumbs)

        // Day-to-day direction.
        if let previousKg, !goal.isToward(fromKg: previousKg, toKg: newKg) {
            offer(.away, .selfHug)
        } else {
            offer(.toward, .thumbsUp)
        }

        var (event, pose) = winner ?? (.toward, .thumbsUp)
        if isWelcomeBack && (event == .toward || event == .away) { pose = .helloWave }

        let reaction = MochiReaction(event: event, pose: pose, isWelcomeBack: isWelcomeBack, changeKg: changeKg)
        return (reaction, state)
    }

    /// Marks every newly crossed milestone as fired and returns the event for the most significant one.
    private static func milestone(newKg: Double, goal: WeightGoal, state: inout MochiProgressState) -> MochiEvent? {
        guard goal.type != .maintain, let target = goal.targetKg, let start = goal.startKg else { return nil }

        var newPercents: [Int] = []
        if let fraction = goal.progressFraction(newKg) {
            for mark in percentMarks where fraction * 100 + epsilon >= Double(mark) {
                if state.firedMilestones.insert("pct:\(mark)").inserted { newPercents.append(mark) }
            }
        }

        var newKgMarks: [Int] = []
        let progressKg = goal.type == .lose ? start - newKg : newKg - start
        // Capped at the goal size so readings past the target are not milestones.
        let wholeKg = min(Int(floor(progressKg + epsilon)), Int(floor(abs(target - start) + epsilon)))
        if wholeKg >= 1 {
            for mark in 1...wholeKg where state.firedMilestones.insert("kg:\(mark)").inserted {
                newKgMarks.append(mark)
            }
        }

        if let pct = newPercents.max() { return .milestonePercent(pct) }
        if let kg = newKgMarks.max() { return .milestoneKg(kg) }
        return nil
    }
}
