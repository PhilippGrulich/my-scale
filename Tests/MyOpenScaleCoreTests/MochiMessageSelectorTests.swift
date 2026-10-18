import XCTest
@testable import MyOpenScaleCore

/// Small deterministic generator so selection tests are repeatable.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class MochiMessageSelectorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func line(_ id: String, _ text: String, events: [String],
                      goals: [GoalType]? = nil, tags: [String]? = nil, minStreak: Int? = nil) -> MochiLine {
        MochiLine(id: id, text: text, events: events, goals: goals, tags: tags, minStreak: minStreak)
    }

    private func select(_ lines: [MochiLine], event: String, goal: GoalType = .lose,
                        tags: Set<String> = [], streak: Int = 0, values: [String: String] = [:],
                        history: MochiLineHistory = MochiLineHistory(used: [:])) -> (line: MochiLine, text: String)? {
        var rng = SplitMix64(state: 42)
        let situation = MochiSituation(event: event, goalType: goal, tags: tags, streakDays: streak, values: values)
        return MochiMessageSelector.select(from: lines, situation: situation, history: history, now: now, random: &rng)
    }

    func testMoreSpecificLineWins() {
        let lines = [line("a", "Nice!", events: ["toward"]),
                     line("b", "Monday magic!", events: ["toward"], tags: ["monday"])]
        let r = select(lines, event: "toward", tags: ["monday", "time:morning"])
        XCTAssertEqual(r?.line.id, "b")
    }

    func testMissingPlaceholderSkipsLine() {
        let lines = [line("a", "Only {left} to go!", events: ["toward"]), line("b", "Nice!", events: ["toward"])]
        XCTAssertEqual(select(lines, event: "toward", values: [:])?.line.id, "b")
    }

    func testGoalFilter() {
        let lines = [line("g", "Growing strong 💪", events: ["toward"], goals: [.gain]),
                     line("x", "Nice!", events: ["toward"])]
        XCTAssertEqual(select(lines, event: "toward", goal: .lose)?.line.id, "x")
        XCTAssertEqual(select(lines, event: "toward", goal: .gain)?.line.id, "g")
    }

    func testNoRepeatWithinTwoWeeks() {
        let lines = [line("a", "A", events: ["toward"]), line("b", "B", events: ["toward"])]
        var h = MochiLineHistory(used: [:]); h.record("a", at: now.addingTimeInterval(-3 * 86_400))
        for _ in 0..<20 { XCTAssertEqual(select(lines, event: "toward", history: h)?.line.id, "b") }
    }

    func testFallsBackToLeastRecentlyUsed() {
        let lines = [line("a", "A", events: ["toward"]), line("b", "B", events: ["toward"])]
        var h = MochiLineHistory(used: [:])
        h.record("a", at: now.addingTimeInterval(-2 * 86_400)); h.record("b", at: now.addingTimeInterval(-1 * 86_400))
        XCTAssertEqual(select(lines, event: "toward", history: h)?.line.id, "a")
    }

    func testRender() {
        XCTAssertEqual(MochiMessageSelector.render("Hi {name}, {change} kg!", values: ["name": "Philipp", "change": "−0,6"]), "Hi Philipp, −0,6 kg!")
        XCTAssertNil(MochiMessageSelector.render("{left} left", values: [:]))
    }

    func testMinStreak() {
        let lines = [line("s", "{streak} days!", events: ["home"], minStreak: 3), line("h", "Hi!", events: ["home"])]
        XCTAssertEqual(select(lines, event: "home", streak: 1, values: ["streak": "1"])?.line.id, "h")
        XCTAssertEqual(select(lines, event: "home", streak: 4, values: ["streak": "4"])?.line.id, "s")
    }

    func testFallsBackToLessSpecificWhenSpecificUsedRecently() {
        let lines = [line("a", "Nice!", events: ["toward"]),
                     line("b", "Monday!", events: ["toward"], tags: ["monday"])]
        var h = MochiLineHistory(used: [:]); h.record("b", at: now.addingTimeInterval(-86_400))
        XCTAssertEqual(select(lines, event: "toward", tags: ["monday"], history: h)?.line.id, "a")
    }

    func testTagsMustAllBePresentAndEventMustMatch() {
        let lines = [line("a", "A", events: ["toward"], tags: ["monday", "time:morning"]),
                     line("b", "B", events: ["away"])]
        XCTAssertNil(select(lines, event: "toward", tags: ["monday"]))
    }

    func testRecordDropsEntriesOlderThanSixtyDays() {
        var h = MochiLineHistory(used: [:])
        h.record("old", at: now.addingTimeInterval(-61 * 86_400))
        h.record("new", at: now)
        XCTAssertNil(h.used["old"])
        XCTAssertNotNil(h.used["new"])
    }

    func testPlaceholdersAndLiteralBraces() {
        XCTAssertEqual(MochiMessageSelector.placeholders(in: "{name} lost {change} {x1} {}"), ["name", "change"])
        XCTAssertEqual(MochiMessageSelector.render("{a b} {1}", values: [:]), "{a b} {1}")
    }

    func testLibraryDecodesWithOptionalKeysAbsent() throws {
        let json = #"{"version":1,"lines":[{"id":"a","text":"Hi","events":["home"]}]}"#
        let lib = try JSONDecoder().decode(MochiLibrary.self, from: Data(json.utf8))
        XCTAssertEqual(lib.lines.first, MochiLine(id: "a", text: "Hi", events: ["home"], goals: nil, tags: nil, minStreak: nil))
    }
}
