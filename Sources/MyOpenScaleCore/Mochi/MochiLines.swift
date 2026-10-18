import Foundation

/// One authored line of Mochi dialogue.
///
/// A line matches a situation when its `events` contain the situation's event, its `goals`
/// (if any) contain the goal type, all its `tags` (if any) are in the situation's tags, and
/// `minStreak` (if any) is at most the current streak.
///
/// Text may contain `{key}` placeholders. Allowed keys:
/// `name`, `weight`, `change`, `left`, `percent`, `streak`, `weeks`, `days`, `target`.
/// A placeholder is `{` + one or more ASCII letters + `}`; any other braces are literal.
public struct MochiLine: Codable, Equatable, Sendable {
    public var id: String
    public var text: String
    public var events: [String]
    public var goals: [GoalType]?
    public var tags: [String]?
    public var minStreak: Int?

    public init(id: String, text: String, events: [String],
                goals: [GoalType]? = nil, tags: [String]? = nil, minStreak: Int? = nil) {
        self.id = id
        self.text = text
        self.events = events
        self.goals = goals
        self.tags = tags
        self.minStreak = minStreak
    }

    /// How specific the line is; more specific lines win over generic ones.
    var specificity: Int {
        (goals != nil ? 1 : 0) + (tags?.count ?? 0) + (minStreak != nil ? 1 : 0)
    }
}

/// The versioned set of lines shipped with the app.
public struct MochiLibrary: Codable, Sendable {
    public var version: Int
    public var lines: [MochiLine]

    public init(version: Int, lines: [MochiLine]) {
        self.version = version
        self.lines = lines
    }
}

/// Everything the selector needs to know about the moment Mochi is speaking in.
public struct MochiSituation: Sendable {
    public var event: String
    public var goalType: GoalType
    public var tags: Set<String>
    public var streakDays: Int
    public var values: [String: String]

    public init(event: String, goalType: GoalType, tags: Set<String>, streakDays: Int, values: [String: String]) {
        self.event = event
        self.goalType = goalType
        self.tags = tags
        self.streakDays = streakDays
        self.values = values
    }
}

/// When each line was last shown, so Mochi does not repeat herself.
public struct MochiLineHistory: Codable, Equatable, Sendable {
    /// Entries older than this many days are dropped on `record`.
    static let retentionDays = 60

    public var used: [String: Date]

    public init(used: [String: Date]) {
        self.used = used
    }

    public mutating func record(_ id: String, at date: Date) {
        used[id] = date
        let cutoff = date.addingTimeInterval(-Double(Self.retentionDays) * 86_400)
        used = used.filter { $0.value >= cutoff }
    }
}

public enum MochiMessageSelector {
    /// A line is not repeated within this many days unless nothing else fits.
    public static let noRepeatDays = 14

    /// Picks the most specific matching line that was not used recently, rendered with the situation's values.
    public static func select(
        from lines: [MochiLine],
        situation: MochiSituation,
        history: MochiLineHistory,
        now: Date,
        random: inout some RandomNumberGenerator
    ) -> (line: MochiLine, text: String)? {
        var candidates: [(line: MochiLine, text: String)] = []
        for line in lines where matches(line, situation) {
            if let text = render(line.text, values: situation.values) {
                candidates.append((line, text))
            }
        }
        guard !candidates.isEmpty else { return nil }

        let window = Double(noRepeatDays) * 86_400
        func isFresh(_ line: MochiLine) -> Bool {
            guard let last = history.used[line.id] else { return true }
            return now.timeIntervalSince(last) >= window
        }

        let scores = Set(candidates.map { $0.line.specificity }).sorted(by: >)
        for score in scores {
            let fresh = candidates.filter { $0.line.specificity == score && isFresh($0.line) }
            if let pick = fresh.randomElement(using: &random) { return pick }
        }

        // Everything was used recently: reuse the least recently used line of the top score.
        let top = candidates.filter { $0.line.specificity == scores[0] }
        return top.min { (history.used[$0.line.id] ?? .distantPast) < (history.used[$1.line.id] ?? .distantPast) }
    }

    /// Substitutes `{key}` placeholders. Returns nil if any placeholder has no value.
    public static func render(_ template: String, values: [String: String]) -> String? {
        var output = ""
        var failed = false
        scan(template) { piece in
            switch piece {
            case .literal(let s): output += s
            case .placeholder(let key):
                if let value = values[key] { output += value } else { failed = true }
            }
        }
        return failed ? nil : output
    }

    /// The set of placeholder keys used in `template`.
    public static func placeholders(in template: String) -> Set<String> {
        var keys = Set<String>()
        scan(template) { piece in
            if case .placeholder(let key) = piece { keys.insert(key) }
        }
        return keys
    }

    // MARK: - Private

    private static func matches(_ line: MochiLine, _ situation: MochiSituation) -> Bool {
        guard line.events.contains(situation.event) else { return false }
        if let goals = line.goals, !goals.contains(situation.goalType) { return false }
        if let tags = line.tags, !Set(tags).isSubset(of: situation.tags) { return false }
        if let minStreak = line.minStreak, minStreak > situation.streakDays { return false }
        return true
    }

    private enum Piece {
        case literal(String)
        case placeholder(String)
    }

    private static func isKeyCharacter(_ c: Character) -> Bool {
        c.isASCII && c.isLetter
    }

    /// Splits a template into literal runs and `{key}` placeholders.
    private static func scan(_ template: String, _ emit: (Piece) -> Void) {
        var literal = ""
        var index = template.startIndex
        while index < template.endIndex {
            let c = template[index]
            if c == "{", let close = template[index...].firstIndex(of: "}") {
                let key = template[template.index(after: index)..<close]
                if !key.isEmpty, key.allSatisfy(isKeyCharacter) {
                    if !literal.isEmpty { emit(.literal(literal)); literal = "" }
                    emit(.placeholder(String(key)))
                    index = template.index(after: close)
                    continue
                }
            }
            literal.append(c)
            index = template.index(after: index)
        }
        if !literal.isEmpty { emit(.literal(literal)) }
    }
}
