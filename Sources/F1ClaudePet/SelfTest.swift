import Foundation

/// The test suite, run with `pet test` (or `F1ClaudePet --self-test`).
///
/// Tests live inside the app module rather than in an XCTest bundle on
/// purpose: XCTest ships with Xcode, and this project builds with the Command
/// Line Tools alone, so an XCTest target would mean nobody could run the tests
/// on a machine that can perfectly well build the app. Being in-module also
/// means the tests reach internal types without any of them being made public
/// just to be observable.
///
/// What is covered is the logic that can be wrong quietly: transcript parsing,
/// usage arithmetic, formatting. The drawing and window code is left alone —
/// asserting on pixels would be busywork, and you can see it on the Dock.
@MainActor
enum SelfTest {

    private static var passed = 0
    private static var failures: [String] = []

    // MARK: - assertions

    private static func check(_ condition: Bool, _ what: String,
                              _ detail: @autoclosure () -> String = "") {
        if condition {
            passed += 1
        } else {
            let extra = detail()
            failures.append(extra.isEmpty ? what : "\(what) — \(extra)")
        }
    }

    private static func equal<T: Equatable>(_ actual: T, _ expected: T, _ what: String) {
        check(actual == expected, what, "expected \(expected), got \(actual)")
    }

    // MARK: - runner

    /// Returns the process exit code: 0 when everything passed.
    static func run() -> Int32 {
        passed = 0
        failures = []

        modelNames()
        contextWindows()
        contextSummaries()
        tokenFormatting()
        agentRunParsing()
        toolVerbs()
        usageParsing()
        creditParsing()
        tyreCompounds()
        themePalette()
        petStates()
        carRegistry()

        let total = passed + failures.count
        for failure in failures { print("FAIL  \(failure)") }
        print("\(passed)/\(total) checks passed")
        return failures.isEmpty ? 0 : 1
    }

    // MARK: - Transcript.ContextInfo

    private static func modelNames() {
        equal(Transcript.ContextInfo(modelId: "claude-fable-5", tokens: 1).modelName,
              "Fable 5", "model name: fable")
        equal(Transcript.ContextInfo(modelId: "claude-opus-5", tokens: 1).modelName,
              "Opus 5", "model name: opus")
        // The build date suffix is noise and must not become part of the name.
        equal(Transcript.ContextInfo(modelId: "claude-haiku-4-5-20251001", tokens: 1).modelName,
              "Haiku 4.5", "model name: dated build")
        equal(Transcript.ContextInfo(modelId: "something-odd", tokens: 1).modelName,
              "Something odd", "model name: unknown id still readable")
    }

    private static func contextWindows() {
        equal(Transcript.ContextInfo(modelId: "claude-fable-5", tokens: 10).window,
              1_000_000, "window: fable is 1M")
        equal(Transcript.ContextInfo(modelId: "claude-opus-5", tokens: 10).window,
              200_000, "window: default is 200k")
        // A session already past 200k proves it is not on a 200k window,
        // whatever the model id suggests — this produced "276k/200k" before.
        equal(Transcript.ContextInfo(modelId: "claude-opus-5", tokens: 276_500).window,
              1_000_000, "window: usage above 200k implies the 1M window")
    }

    private static func contextSummaries() {
        equal(Transcript.ContextInfo(modelId: "claude-fable-5", tokens: 216_600).summary,
              "Fable 5 · 216k/1M (22%)", "summary: large count loses the decimal")
        equal(Transcript.ContextInfo(modelId: "claude-opus-5", tokens: 12_300).summary,
              "Opus 5 · 12.3k/200k (6%)", "summary: small count keeps one decimal")
    }

    private static func tokenFormatting() {
        equal(Transcript.TurnStats(outputTokens: 323, verb: "Creating").tokenText,
              "323 tokens", "turn tokens: below 1k")
        equal(Transcript.TurnStats(outputTokens: 2_700, verb: "Creating").tokenText,
              "2.7k tokens", "turn tokens: thousands")
    }

    // MARK: - agents and background work

    private static func agentRunParsing() {
        func use(_ id: String, _ name: String, _ input: String) -> String {
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"\#(id)","name":"\#(name)","input":\#(input)}]}}"#
        }
        func result(_ id: String) -> String {
            #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"\#(id)"}]}}"#
        }

        // A subagent with no result yet is still running.
        var runs = Transcript.agentRuns(fromLines: [
            use("a1", "Task", #"{"description":"Audit the smoke system"}"#),
        ])
        equal(runs.count, 1, "agents: one subagent found")
        equal(runs.first?.label, "Audit the smoke system", "agents: label from description")
        equal(runs.first?.isRunning, true, "agents: subagent without a result is running")

        // ...and settles once its result arrives.
        runs = Transcript.agentRuns(fromLines: [
            use("a1", "Task", #"{"description":"Audit the smoke system"}"#),
            result("a1"),
        ])
        equal(runs.first?.isRunning, false, "agents: subagent with a result is done")

        // A background shell gets its result immediately — that is only the
        // acknowledgement, so it must still read as running.
        let bg = use("b1", "Bash", #"{"command":"sleep 30","run_in_background":true}"#)
        runs = Transcript.agentRuns(fromLines: [bg, result("b1")])
        equal(runs.count, 1, "agents: background shell found")
        equal(runs.first?.isRunning, true,
              "agents: background shell is not done just because it was acknowledged")

        // It is done only when a task notification quotes the original call.
        runs = Transcript.agentRuns(fromLines: [
            bg, result("b1"),
            #"{"type":"user","message":{"content":"<task-notification><tool-use-id>b1</tool-use-id><status>completed</status></task-notification>"}}"#,
        ])
        equal(runs.first?.isRunning, false, "agents: notification completes a background shell")

        // An ordinary foreground Bash call is not background work at all.
        runs = Transcript.agentRuns(fromLines: [use("c1", "Bash", #"{"command":"ls"}"#)])
        equal(runs.count, 0, "agents: foreground commands are not listed")

        // Finished work goes stale: an old job left on screen reads as current
        // activity when it is nothing of the sort. Running work never does.
        let stamped = #"{"type":"assistant","timestamp":"2020-01-01T00:00:00.000Z","message":{"content":[{"type":"tool_use","id":"d1","name":"Task","input":{"description":"Ancient audit"}}]}}"#
        runs = Transcript.agentRuns(fromLines: [stamped, result("d1")])
        equal(runs.count, 0, "agents: work finished long ago is dropped")

        runs = Transcript.agentRuns(fromLines: [stamped])
        equal(runs.count, 1, "agents: still-running work is kept however old")
    }

    private static func toolVerbs() {
        equal(Transcript.verb(for: "Write"), "Creating", "verb: Write")
        equal(Transcript.verb(for: "Edit"), "Editing", "verb: Edit")
        equal(Transcript.verb(for: "Grep"), "Searching", "verb: Grep")
        equal(Transcript.verb(for: "mcp__figma__get_metadata"), "Connecting", "verb: MCP tools")
        equal(Transcript.verb(for: nil), "Thinking", "verb: nothing running")
    }

    // MARK: - UsageService

    private static func usageParsing() {
        let payload: [String: Any] = [
            "five_hour": ["utilization": 0.35, "resets_at": "2099-01-01T00:00:00Z"],
            "seven_day": ["utilization": 31.0],
        ]
        let rows = UsageService.parse(payload)
        equal(rows.count, 2, "usage: both limits parsed")
        // Five-hour sorts first regardless of dictionary order.
        equal(rows.first?.label, "5-hour limit", "usage: known keys get friendly names")
        // A fraction and a percentage must both land on the same number.
        equal(rows.first?.percent, 35, "usage: fractional utilisation scaled to percent")
        equal(rows.last?.percent, 31, "usage: percentage utilisation left alone")
    }

    private static func creditParsing() {
        var rows = UsageService.parse(["credits": ["used": 2.5, "limit": 10.0]])
        equal(rows.count, 1, "credits: row parsed")
        equal(rows.first?.valueText, "$2.50 of $10.00", "credits: rendered as money")
        equal(rows.first?.percent, 25, "credits: percentage derived from the amounts")

        // Cents, and only two of the three amounts present.
        rows = UsageService.parse(["usage_credits": ["remaining_cents": 750, "limit_cents": 1000]])
        equal(rows.first?.valueText, "$2.50 of $10.00", "credits: cents and a missing field")

        // Nothing usable must not invent a row.
        rows = UsageService.parse(["credits": ["currency": "USD"]])
        equal(rows.count, 0, "credits: unparseable payload yields nothing")
    }

    // MARK: - small value types

    private static func tyreCompounds() {
        equal(TyreCompound.allCases.count, 5, "tyres: five Pirelli compounds")
        check(TyreCompound(rawValue: "soft") != nil, "tyres: soft round-trips from its raw value")
        check(TyreCompound(rawValue: "gravel") == nil, "tyres: unknown compound rejected")

        // Every compound needs a name and a colour distinct from its
        // neighbours, or the sidewall ring stops telling you anything.
        var seen: [String] = []
        for compound in TyreCompound.allCases {
            check(!compound.displayName.isEmpty, "tyres: \(compound.rawValue) has a name")
            let rgb = compound.color.usingColorSpace(.sRGB)
            let key = String(format: "%.2f-%.2f-%.2f",
                             rgb?.redComponent ?? 0, rgb?.greenComponent ?? 0,
                             rgb?.blueComponent ?? 0)
            check(!seen.contains(key), "tyres: \(compound.rawValue) has its own colour")
            seen.append(key)
        }
    }

    /// The states the hooks can push, and the labels the menu shows for them.
    private static func petStates() {
        for state in PetState.allCases {
            equal(PetState(rawValue: state.rawValue), state,
                  "state: \(state.rawValue) round-trips")
            check(!state.displayName.isEmpty, "state: \(state.rawValue) has a display name")
            check(!state.summary.isEmpty, "state: \(state.rawValue) has a summary")
        }
        // A failure is called a crash in the menu — "spin" reads as recovery.
        equal(PetState.spin.displayName, "Crash", "state: spin presents as Crash")
        check(PetState.allCases.count >= 7, "state: every hook event has a state")
    }

    /// The garage: ids have to be unique, since the menu and the saved
    /// preference both key off them.
    private static func carRegistry() {
        var ids = Set<String>()
        for car in CarRegistry.all {
            check(ids.insert(car.id).inserted, "cars: \(car.id) is unique")
            check(!car.displayName.isEmpty, "cars: \(car.id) has a name")
            check(car.pixelSize.width > 0 && car.pixelSize.height > 0,
                  "cars: \(car.id) has a drawable size")
            check(car.wheels.count >= 2, "cars: \(car.id) has at least two wheels")
            check(car.wheels.contains { $0.isDriven }, "cars: \(car.id) has a driven axle")
        }
        check(CarRegistry.car(id: "rb22") != nil, "cars: the RB22 is present")
        check(CarRegistry.car(id: "not-a-car") == nil, "cars: unknown id returns nothing")
        equal(CarRegistry.fallback.id, "rb22", "cars: the RB22 is the default")
        // Both categories must be represented, or a menu group renders empty.
        equal(CarRegistry.byCategory.count, CarCategory.allCases.count,
              "cars: every category has entries")
    }

    private static func themePalette() {
        check(ThemeColor(rawValue: "claude") == .claude, "theme: default round-trips")
        check(ThemeColor(rawValue: "chartreuse") == nil, "theme: unknown colour rejected")
        for choice in ThemeColor.allCases {
            check(!choice.displayName.isEmpty, "theme: \(choice.rawValue) has a name")
            // The panel background is derived from the accent; it must stay
            // dark enough to read white text on.
            var brightness: CGFloat = 0
            choice.background.usingColorSpace(.sRGB)?
                .getHue(nil, saturation: nil, brightness: &brightness, alpha: nil)
            check(brightness < 0.2, "theme: \(choice.rawValue) background stays dark",
                  "brightness \(brightness)")
        }
    }
}
