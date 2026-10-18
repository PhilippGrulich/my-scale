import XCTest
@testable import MyOpenScaleCore

/// Validates the shipped Mochi line libraries in `App/Mochi`.
final class MochiLibraryFileTests: XCTestCase {
    private func load(_ lang: String) throws -> MochiLibrary {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../App/Mochi/MochiLines-\(lang).json")
            .standardized
        return try JSONDecoder().decode(MochiLibrary.self, from: Data(contentsOf: url))
    }

    func testBothLanguagesDecodeAndShareIDs() throws {
        let en = try load("en"), de = try load("de")
        XCTAssertEqual(Set(en.lines.map(\.id)), Set(de.lines.map(\.id)))
        XCTAssertEqual(en.lines.count, Set(en.lines.map(\.id)).count, "duplicate ids")
        XCTAssertGreaterThanOrEqual(en.lines.count, 150)
    }

    func testFiltersMatchAcrossLanguages() throws {
        let de = Dictionary(uniqueKeysWithValues: try load("de").lines.map { ($0.id, $0) })
        for l in try load("en").lines {
            let t = try XCTUnwrap(de[l.id])
            XCTAssertEqual([l.events, l.tags ?? []], [t.events, t.tags ?? []], l.id)
            XCTAssertEqual(l.goals, t.goals, l.id); XCTAssertEqual(l.minStreak, t.minStreak, l.id)
            XCTAssertEqual(MochiMessageSelector.placeholders(in: l.text), MochiMessageSelector.placeholders(in: t.text), l.id)
        }
    }

    func testOnlyKnownPlaceholders() throws {
        let allowed: Set = ["name", "weight", "change", "left", "percent", "streak", "weeks", "days", "target"]
        for lang in ["en", "de"] { for l in try load(lang).lines {
            XCTAssertTrue(MochiMessageSelector.placeholders(in: l.text).isSubset(of: allowed), "\(lang) \(l.id)")
        } }
    }

    func testEventCoverage() throws {
        let minimums: [String: Int] = ["toward": 25, "away": 20, "newBest": 8, "streak": 8, "goodWeek": 6, "daysInRange": 4,
            "milestonePercent": 6, "milestoneKg": 6, "goalReached": 6, "welcomeBack": 8, "notYou": 4, "home": 30, "homeIdle": 6,
            "birthday": 4, "anniversary": 4, "saved": 6, "reminder1": 5, "reminder2": 5, "reminder4": 5, "reminder8": 5, "reminderWeekly": 5,
            "goalNone": 6, "goalProgress": 12, "goalReachedHome": 6]
        let en = try load("en")
        for (event, min) in minimums { XCTAssertGreaterThanOrEqual(en.lines.filter { $0.events.contains(event) }.count, min, event) }
    }

    func testEveryGoalTypeHasPlaceholderFreeFallback() throws {
        // With no values at all, every reaction event must still find a line for every goal type.
        for event in ["toward", "away", "newBest", "goodWeek", "goalReached", "notYou", "home",
                      "goalNone", "goalProgress", "goalReachedHome"] {
            for goal in GoalType.allCases where !(goal == .maintain && event == "newBest") {
                var rng = SystemRandomNumberGenerator()
                let s = MochiSituation(event: event, goalType: goal, tags: [], streakDays: 0, values: [:])
                XCTAssertNotNil(MochiMessageSelector.select(from: try load("en").lines, situation: s, history: .init(used: [:]), now: Date(), random: &rng), "\(event)/\(goal)")
            }
        }
    }

    /// The dashboard and Goal page corner bubble wraps but must stay a few lines tall: every line it can show
    /// (greetings, and a stashed reaction with its welcome-back prefix) fits a character budget.
    /// Placeholders count at a generous rendered width (a long name, a number).
    func testCornerLinesFitTheBubble() throws {
        func rendered(_ text: String) -> Int {
            var n = text.count
            for key in MochiMessageSelector.placeholders(in: text) {
                n += (key == "name" ? 12 : 6) - (key.count + 2)
            }
            return n
        }
        let greetings: Set = ["home", "homeIdle", "birthday", "anniversary", "goalNone", "goalProgress", "goalReachedHome"]
        let reactions: Set = ["toward", "away", "newBest", "streak", "goodWeek", "daysInRange",
                              "milestonePercent", "milestoneKg", "goalReached"]
        for lang in ["en", "de"] {
            let lines = try load(lang).lines
            func longest(_ events: Set<String>) -> Int {
                lines.filter { !events.isDisjoint(with: $0.events) }.map { rendered($0.text) }.max() ?? 0
            }
            for l in lines where !greetings.union(reactions).isDisjoint(with: l.events) {
                XCTAssertLessThanOrEqual(rendered(l.text), 70, "\(lang) \(l.id): \(l.text)")
            }
            XCTAssertLessThanOrEqual(longest(["welcomeBack"]) + 1 + longest(reactions), 130, lang)
        }
    }

    func testNoShamingWords() throws {
        let banned = ["calorie", "kalorie", "diet", "diät", "careful", "vorsicht", "what did you eat", "was hast du gegessen", "fat", "fett"]
        for lang in ["en", "de"] { for l in try load(lang).lines {
            let t = l.text.lowercased()
            XCTAssertFalse(banned.contains { t.contains($0) }, "\(lang) \(l.id): \(l.text)")
        } }
    }
}
