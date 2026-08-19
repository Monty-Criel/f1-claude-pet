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
        dockScaling()
        boxBoxEscalation()
        gifChoreography()
        conversationParsing()
        stateChannel()
        sessionDiscovery()
        usageFormatting()
        usageCacheAndStats()
        histogram()
        sessionTitles()
        stateWatcher()
        themeNotifications()

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

    /// The box-box escalation decision: once per waiting episode, after the
    /// threshold, only while enabled.
    private static func boxBoxEscalation() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let early = start.addingTimeInterval(BoxBoxAlert.threshold - 1)
        let late = start.addingTimeInterval(BoxBoxAlert.threshold + 1)

        equal(BoxBoxAlert.shouldEscalate(waitingSince: start, alreadyFired: false,
                                         enabled: true, now: late),
              true, "boxbox: fires after the threshold")
        equal(BoxBoxAlert.shouldEscalate(waitingSince: start, alreadyFired: false,
                                         enabled: true, now: early),
              false, "boxbox: quiet before the threshold")
        equal(BoxBoxAlert.shouldEscalate(waitingSince: start, alreadyFired: true,
                                         enabled: true, now: late),
              false, "boxbox: fires once per episode")
        equal(BoxBoxAlert.shouldEscalate(waitingSince: start, alreadyFired: false,
                                         enabled: false, now: late),
              false, "boxbox: disabled means silent")
        equal(BoxBoxAlert.shouldEscalate(waitingSince: nil, alreadyFired: false,
                                         enabled: true, now: late),
              false, "boxbox: nothing waiting, nothing fired")
    }

    /// Conversation parsing off fixture lines — the panel's actual diet.
    private static func conversationParsing() {
        func msg(_ type: String, _ content: String) -> String {
            #"{"type":"\#(type)","message":{"content":\#(content)}}"#
        }

        // Plain-string content, block content, tool folding, reminder skips.
        let lines = [
            msg("user", #""Fix the bug""#),
            msg("user", #""<system-reminder>ignore me</system-reminder>""#),
            msg("assistant", #"[{"type":"text","text":"On it."},{"type":"tool_use","id":"t1","name":"Edit","input":{"file_path":"/a/b/Car.swift"}}]"#),
            msg("assistant", #"[{"type":"text","text":"Done."}]"#),
            "not json at all",
        ]
        let entries = Transcript.recent(fromLines: lines)
        equal(entries.count, 4, "recent: four entries survive the noise")
        equal(entries.first?.role == .user, true, "recent: user first")
        check(entries.contains { $0.role == .tool && $0.text == "Edit Car.swift" },
              "recent: tool call folds to name + basename")
        check(!entries.contains { $0.text.contains("system-reminder") },
              "recent: harness reminders are not conversation")

        // The finished-message source: last assistant prose.
        equal(entries.last { $0.role == .assistant }?.text, "Done.",
              "recent: the last word is Claude's")

        // Context info off the same shape of lines.
        let usage = #"{"type":"assistant","message":{"model":"claude-fable-5","usage":{"input_tokens":2,"cache_read_input_tokens":100000,"cache_creation_input_tokens":500,"output_tokens":1500}}}"#
        let info = Transcript.contextInfo(fromLines: [usage])
        equal(info?.tokens, 102_002, "context: token components summed")
        equal(info?.modelName, "Fable 5", "context: model name resolved")
        check(Transcript.contextInfo(fromLines: ["{}"]) == nil,
              "context: nothing usable yields nothing")

        // Turn stats stop at the last user message.
        let turn = [
            msg("assistant", #"[{"type":"tool_use","id":"x","name":"Bash","input":{}}]"#) 
                .replacingOccurrences(of: #""message":{"#, with: #""message":{"usage":{"output_tokens":900},"#),
            msg("user", #""next question""#),
            msg("assistant", #"[{"type":"tool_use","id":"y","name":"Write","input":{}}]"#)
                .replacingOccurrences(of: #""message":{"#, with: #""message":{"usage":{"output_tokens":300},"#),
        ]
        let stats = Transcript.turnStats(fromLines: turn)
        equal(stats.outputTokens, 300, "turn: counts only after the last user message")
        equal(stats.verb, "Creating", "turn: verb from the last tool")
    }

    /// The state channel, against a scratch directory.
    private static func stateChannel() {
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("f1-selftest-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        StateChannel.rootOverride = scratch
        defer {
            StateChannel.rootOverride = nil
            try? FileManager.default.removeItem(at: scratch)
        }

        StateChannel.write(.racing, message: "flat out")
        equal(StateChannel.read(), .racing, "channel: state round-trips")
        equal(StateChannel.readMessage(), "flat out", "channel: message round-trips")
        check(StateChannel.modified() != nil, "channel: write stamps a mtime")

        StateChannel.write(.idle, message: nil)
        equal(StateChannel.read(), .idle, "channel: overwrite wins")

        // The session pointer's two-line format, as the hook writes it.
        try? "abc-123\n/tmp/somewhere".write(
            to: scratch.appendingPathComponent("session"), atomically: true, encoding: .utf8)
        let session = StateChannel.readSession()
        equal(session?.id, "abc-123", "channel: session id parsed")
        equal(session?.cwd, "/tmp/somewhere", "channel: session cwd parsed")

        // The turn-start stamp, as `date +%s` writes it.
        try? "1700000000\n".write(
            to: scratch.appendingPathComponent("turn-start"), atomically: true, encoding: .utf8)
        equal(StateChannel.turnStart()?.timeIntervalSince1970, 1_700_000_000,
              "channel: turn start parsed")
    }

    /// Session discovery over a fixture project tree: recency order, observer
    /// filtering, look-alike dedupe — the exact bugs this code has had.
    private static func sessionDiscovery() {
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("f1-sessions-\(ProcessInfo.processInfo.processIdentifier)")
        let saved = Transcript.projectsRoot
        Transcript.projectsRoot = scratch
        defer {
            Transcript.projectsRoot = saved
            try? FileManager.default.removeItem(at: scratch)
        }

        func plant(_ folder: String, _ id: String, title: String, cwd: String, age: TimeInterval) {
            let dir = scratch.appendingPathComponent(folder)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("\(id).jsonl")
            let line = #"{"customTitle":"\#(title)","cwd":"\#(cwd)"}"# + "\n"
            try? line.write(to: file, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: file.path)
        }

        plant("proj-a", "s1", title: "Newest chat", cwd: "/tmp/a", age: 10)
        plant("proj-a", "s2", title: "Older chat", cwd: "/tmp/a", age: 100)
        plant("proj-b", "s3", title: "Observer", cwd: "/tmp/.claude-mem/x", age: 5)
        plant("proj-c", "s4", title: "Newest chat", cwd: "/tmp/c", age: 50)   // duplicate label

        let sessions = Transcript.recentSessions(limit: 3)
        equal(sessions.count, 2, "sessions: observers and look-alikes filtered")
        equal(sessions.first?.id, "s1", "sessions: newest first")
        check(!sessions.contains { $0.id == "s3" }, "sessions: claude-mem machinery excluded")
        check(!sessions.contains { $0.id == "s4" }, "sessions: duplicate label keeps the newest")

        // Direct URL resolution through the same root.
        check(Transcript.url(id: "s1", cwd: "/anything") != nil,
              "sessions: url falls back to scanning folders")
    }

    /// The usage cache codec and the local stats, against fixture roots.
    private static func usageCacheAndStats() {
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("f1-usage-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let savedProjects = Transcript.projectsRoot
        let savedHistory = UsageService.historyFile
        StateChannel.rootOverride = scratch
        defer {
            StateChannel.rootOverride = nil
            Transcript.projectsRoot = savedProjects
            UsageService.historyFile = savedHistory
            UsageService.invalidateStats()
            try? FileManager.default.removeItem(at: scratch)
        }

        // Cache round-trip, including the money row's value text.
        let cachePayload: [String: Any] = [
            "fetchedAt": Date().timeIntervalSince1970 - 300,
            "rows": [
                ["label": "5-hour limit", "percent": 35, "resets": "resets in 3 h"],
                ["label": "Usage credits", "percent": 25, "resets": "",
                 "valueText": "$2.50 of $10.00"],
            ],
        ]
        let data = try? JSONSerialization.data(withJSONObject: cachePayload)
        try? data?.write(to: scratch.appendingPathComponent("usage.json"))
        UsageService.loadCache()
        equal(UsageService.rows.count, 2, "cache: rows load from disk")
        equal(UsageService.rows.last?.valueText, "$2.50 of $10.00",
              "cache: money text survives the round-trip")
        check(UsageService.freshnessNote.contains("min ago"),
              "cache: freshness note reflects the load")
        UsageService.saveCache()
        UsageService.loadCache()
        equal(UsageService.rows.count, 2, "cache: save and reload is stable")

        // Local stats over fixture history + projects.
        let projects = scratch.appendingPathComponent("projects/proj-x")
        try? FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        try? #"{"customTitle":"Fixture","cwd":"/tmp/x"}"#
            .write(to: projects.appendingPathComponent("s9.jsonl"),
                   atomically: true, encoding: .utf8)
        Transcript.projectsRoot = scratch.appendingPathComponent("projects")

        let now = Date().timeIntervalSince1970
        let history = (0..<3).map {
            #"{"display":"p\#($0)","timestamp":\#(Int((now - Double($0) * 40) * 1000))}"#
        } + [#"{"display":"old","timestamp":\#(Int((now - 3 * 86_400) * 1000))}"#]
        UsageService.historyFile = scratch.appendingPathComponent("history.jsonl")
        try? history.joined(separator: "\n")
            .write(to: UsageService.historyFile, atomically: true, encoding: .utf8)

        UsageService.invalidateStats()
        let stats = UsageService.stats()
        let prompts = stats.first { $0.label == "Prompts" }
        equal(prompts?.value.hasPrefix("3 today") ?? false, true,
              "stats: today's prompts counted")
        check(prompts?.value.contains("4 this week") ?? false,
              "stats: the week includes older days")
        let sessions = stats.first { $0.label == "Sessions" }
        check(sessions?.value.contains("1 total") ?? false,
              "stats: fixture session counted")
        check(stats.contains { $0.label == "Busiest day" }, "stats: busiest day present")
        check(stats.contains { $0.label == "Current car" }, "stats: pet colour included")
    }

    /// The Monday-to-Sunday histogram over synthetic per-day counts.
    private static func histogram() {
        var calendar = Calendar.current
        calendar.firstWeekday = 2

        // Activity today and further back, so past and future rows both exist.
        let today = calendar.startOfDay(for: Date())
        var perDay: [Date: Int] = [today: 5]
        for daysBack in 1...21 {
            if let day = calendar.date(byAdding: .day, value: -daysBack, to: today) {
                perDay[day] = 3
            }
        }
        let bars = UsageService.buildHistogram(perDay: perDay, calendar: calendar)
        equal(bars.count, 7, "histogram: seven days, always")
        equal(bars.filter(\.isToday).count, 1, "histogram: exactly one today")
        check(bars.allSatisfy { $0.count >= 0 }, "histogram: no negative bars")
        // Whatever is after today must be a projection, never a count.
        if let todayIndex = bars.firstIndex(where: \.isToday) {
            check(bars.suffix(from: bars.index(after: todayIndex)).allSatisfy(\.projected),
                  "histogram: future days are estimates")
        }
        // Empty history: no crash, and projections are all zero.
        let empty = UsageService.buildHistogram(perDay: [:], calendar: calendar)
        equal(empty.count, 7, "histogram: empty history still shapes a week")
        check(empty.allSatisfy { $0.count == 0 }, "histogram: nothing means zero")
    }

    /// Session titles resolved from a fixture transcript.
    private static func sessionTitles() {
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("f1-titles-\(ProcessInfo.processInfo.processIdentifier)")
        let saved = Transcript.projectsRoot
        Transcript.projectsRoot = scratch
        defer {
            Transcript.projectsRoot = saved
            try? FileManager.default.removeItem(at: scratch)
        }
        let dir = scratch.appendingPathComponent("proj-t")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? #"{"customTitle":"Named session","cwd":"/tmp/t"}"#
            .write(to: dir.appendingPathComponent("t1.jsonl"),
                   atomically: true, encoding: .utf8)

        equal(StateChannel.readSessionTitle(id: "t1", cwd: "/tmp/t"), "Named session",
              "titles: customTitle wins")
        check(StateChannel.readSessionTitle(id: "missing", cwd: "/tmp/t") == nil
              || StateChannel.readSessionTitle(id: "missing", cwd: "/tmp/t")?.isEmpty == false,
              "titles: a missing session does not crash")
    }

    /// The watcher actually fires when the state file changes.
    private static func stateWatcher() {
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("f1-watch-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        StateChannel.rootOverride = scratch
        defer {
            StateChannel.rootOverride = nil
            try? FileManager.default.removeItem(at: scratch)
        }

        var seen: [PetState] = []
        let watcher = StateWatcher { state, _ in seen.append(state) }
        watcher.start()
        StateChannel.write(.boost, message: "tool ran")
        let deadline = Date().addingTimeInterval(2)
        while seen.isEmpty && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        watcher.stop()
        equal(seen.first, .boost, "watcher: a state write reaches the callback")
    }

    /// Changing the theme announces itself; the palette stays self-consistent.
    private static func themeNotifications() {
        let saved = ThemeColor.selected
        defer { ThemeColor.selected = saved }

        var announced = false
        let token = NotificationCenter.default.addObserver(
            forName: Theme.changed, object: nil, queue: nil) { _ in announced = true }
        defer { NotificationCenter.default.removeObserver(token) }

        ThemeColor.selected = .teal
        check(announced, "theme: selection posts the change notification")
        equal(ThemeColor.selected, .teal, "theme: selection persists")
        check(Theme.accent == ThemeColor.teal.color, "theme: accent follows selection")
        check(Theme.accentBright != Theme.accent, "theme: bright variant differs")
    }

    /// Reset-time formatting for the usage rows.
    private static func usageFormatting() {
        equal(UsageService.resetText(nil), "", "resets: nothing in, nothing out")
        equal(UsageService.resetText("garbage"), "", "resets: unparseable in, nothing out")

        let soon = ISO8601DateFormatter().string(from: Date().addingTimeInterval(600))
        equal(UsageService.resetText(soon), "resets in 9 min", "resets: minutes")

        let hours = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3 * 3600 + 120))
        equal(UsageService.resetText(hours), "resets in 3 h 1 min", "resets: hours and minutes")

        let past = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-60))
        equal(UsageService.resetText(past), "resetting…", "resets: already elapsed")

        let epoch = Date().addingTimeInterval(120).timeIntervalSince1970
        check(UsageService.resetText(epoch).hasPrefix("resets in "),
              "resets: epoch numbers accepted")

        check(UsageService.resetText(
            ISO8601DateFormatter().string(from: Date().addingTimeInterval(3 * 86_400)))
            .hasPrefix("resets "), "resets: far dates show the weekday")
    }

    /// The gif show: ordered cues, opening with lights out, captions fixed —
    /// never read from the user's transcript.
    private static func gifChoreography() {
        let cues = GifRecorder.choreography
        check(cues.first?.state == .launch, "gif: the show opens with lights out")
        check(cues.contains { $0.state == .victory }, "gif: the show ends on a win")
        let times = cues.map(\.time)
        equal(times, times.sorted(), "gif: cues are in playing order")
        check(times.allSatisfy { $0 < 9 }, "gif: every cue fits the default duration")
    }

    /// The Dock-height → sprite-scale mapping.
    private static func dockScaling() {
        // The anchor: the size the art was tuned at.
        equal(TrackView.scale(forDockHeight: 84), 2.25, "scale: 84pt Dock is the 2.25 anchor")
        // Clamps at both ends — a tiny or giant Dock still gets a usable car.
        equal(TrackView.scale(forDockHeight: 20), 1.0, "scale: floor at 1.0")
        equal(TrackView.scale(forDockHeight: 400), 3.5, "scale: ceiling at 3.5")
        // Quantised to 0.25 steps so magnification twitch can't flap the raster.
        equal(TrackView.scale(forDockHeight: 90), 2.5, "scale: quantised to quarter steps")
        let steps = TrackView.scale(forDockHeight: 60) * 4
        equal(steps, steps.rounded(), "scale: always lands on a quarter step")

        // The user's size preference sits on top of the Dock-derived base.
        let saved = TrackView.sizeFactor
        defer { TrackView.sizeFactor = saved }
        TrackView.sizeFactor = 1.0
        equal(TrackView.effectiveScale(dockHeight: 84), 2.25,
              "size: default preference leaves the base alone")
        equal(TrackView.effectiveScale(dockHeight: nil), 2.25,
              "size: no measurement falls back to the tuned base")
        TrackView.sizeFactor = 2.0
        equal(TrackView.effectiveScale(dockHeight: 84), 4.5,
              "size: doubled preference doubles the car")
        TrackView.sizeFactor = 5.0   // setter clamps
        equal(TrackView.sizeFactor, 2.0, "size: preference clamped to sane range")
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
