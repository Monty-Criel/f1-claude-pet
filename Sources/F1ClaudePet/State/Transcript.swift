import Foundation

/// Reads Claude Code session transcripts.
///
/// Transcripts are JSONL, one record per line, and run to tens of megabytes —
/// user records can embed whole base64 images on a single line. So everything
/// here works on a bounded tail of the file and skips oversized lines rather
/// than parsing them.
enum Transcript {

    struct Entry {
        enum Role { case user, assistant, tool }
        let role: Role
        let text: String
    }

    /// How much of the file to read. Enough for a good few exchanges without
    /// stalling on a 59MB transcript.
    private static let window: UInt64 = 1_500_000

    /// Lines longer than this are image or tool-result blobs; never worth parsing.
    private static let maxLineLength = 120_000

    /// A session you can switch to in the chat panel.
    struct SessionRef {
        let id: String
        let cwd: String
        let title: String
        let modified: Date

        var project: String { (cwd as NSString).lastPathComponent }
        /// Short label for a tab.
        var label: String {
            let name = title.isEmpty ? project : title
            return name.count > 22 ? String(name.prefix(21)) + "\u{2026}" : name
        }
    }

    /// The most recently active sessions, newest first.
    ///
    /// Ordered by transcript mtime rather than anything Claude Code records,
    /// because that is the only thing guaranteed to move when a session is
    /// actually used.
    /// Overridable for tests; the running app never touches it.
    nonisolated(unsafe) static var projectsRoot =
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")

    static func recentSessions(limit: Int = 3) -> [SessionRef] {
        let projects = projectsRoot
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: projects, includingPropertiesForKeys: nil) else { return [] }

        var candidates: [(URL, Date)] = []
        for folder in folders {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for file in files where file.pathExtension == "jsonl" {
                let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                candidates.append((file, date))
            }
        }

        // Walk the whole list newest-first until enough real chats are found —
        // claude-mem's observer sessions can flood the top of the recency
        // order, so a fixed-depth scan comes up short. Stat is cheap and the
        // tail reads stop as soon as `limit` conversations are in hand.
        var found: [SessionRef] = []
        var seenLabels = Set<String>()
        for (file, date) in candidates.sorted(by: { $0.1 > $1.1 }) {
            let (title, cwd) = titleAndCwd(in: file)

            // Background machinery, not conversations you would want to reply to.
            if cwd.contains("/.claude-mem/") || cwd.contains("observer-sessions") { continue }

            let ref = SessionRef(id: file.deletingPathExtension().lastPathComponent,
                                 cwd: cwd, title: title, modified: date)
            // Two untitled sessions in the same repo would make identical
            // tabs — keep only the newest of each look-alike.
            guard seenLabels.insert(ref.label).inserted else { continue }

            found.append(ref)
            if found.count == limit { break }
        }
        return found
    }

    /// Pull the session title and working directory out of a transcript tail.
    private static func titleAndCwd(in url: URL) -> (title: String, cwd: String) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return ("", NSHomeDirectory()) }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let peek: UInt64 = 400_000
        try? handle.seek(toOffset: size > peek ? size - peek : 0)
        guard let data = try? handle.readToEnd() else { return ("", NSHomeDirectory()) }
        let text = String(decoding: data, as: UTF8.self)

        func lastValue(_ key: String) -> String? {
            let needle = "\"\(key)\":\""
            guard let range = text.range(of: needle, options: .backwards) else { return nil }
            let rest = text[range.upperBound...]
            guard let end = rest.firstIndex(of: "\"") else { return nil }
            let value = String(rest[..<end])
            return value.isEmpty ? nil : value
        }

        return (lastValue("customTitle") ?? "", lastValue("cwd") ?? NSHomeDirectory())
    }

    static func url(id: String, cwd: String) -> URL? {
        let projects = projectsRoot

        // Project folders are the cwd with path separators turned into dashes.
        let direct = projects
            .appendingPathComponent(cwd.replacingOccurrences(of: "/", with: "-"))
            .appendingPathComponent("\(id).jsonl")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }

        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: projects, includingPropertiesForKeys: nil) else { return nil }
        for folder in folders {
            let candidate = folder.appendingPathComponent("\(id).jsonl")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// The tail of the transcript, split into whole lines.
    private static func tailLines(id: String, cwd: String) -> [String] {
        guard let url = url(id: id, cwd: cwd),
              let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let truncated = size > window
        try? handle.seek(toOffset: truncated ? size - window : 0)
        guard let data = try? handle.readToEnd() else { return [] }

        var lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
        // The first line is almost certainly cut in half by the window.
        if truncated, !lines.isEmpty { lines.removeFirst() }
        return lines
    }

    /// Recent conversation, oldest first. Tool calls are folded into single
    /// `.tool` entries so the panel can show what Claude actually did.
    static func recent(id: String, cwd: String, limit: Int = 40) -> [Entry] {
        recent(fromLines: tailLines(id: id, cwd: cwd), limit: limit)
    }

    /// Parsing split from file access so fixtures can exercise it.
    static func recent(fromLines lines: [String], limit: Int = 40) -> [Entry] {
        var entries: [Entry] = []

        for line in lines {
            guard line.count < maxLineLength,
                  let data = line.data(using: .utf8),
                  let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = record["type"] as? String,
                  type == "user" || type == "assistant",
                  let message = record["message"] as? [String: Any]
            else { continue }

            let role: Entry.Role = (type == "user") ? .user : .assistant

            // Content is either a plain string or an array of typed blocks.
            if let text = message["content"] as? String {
                append(&entries, role: role, text: text)
                continue
            }
            guard let blocks = message["content"] as? [[String: Any]] else { continue }

            for block in blocks {
                switch block["type"] as? String {
                case "text":
                    if let text = block["text"] as? String { append(&entries, role: role, text: text) }
                case "tool_use":
                    if let name = block["name"] as? String {
                        entries.append(Entry(role: .tool, text: name + detail(of: block)))
                    }
                default:
                    continue        // images, tool results, thinking
                }
            }
        }

        return Array(entries.suffix(limit))
    }

    /// A short human-readable detail for a tool call, e.g. the file it touched.
    private static func detail(of block: [String: Any]) -> String {
        guard let input = block["input"] as? [String: Any] else { return "" }
        if let path = input["file_path"] as? String {
            return " " + (path as NSString).lastPathComponent
        }
        for key in ["description", "command", "pattern", "query"] {
            if let value = input[key] as? String, !value.isEmpty {
                return " " + value.prefix(60)
            }
        }
        return ""
    }

    private static func append(_ entries: inout [Entry], role: Entry.Role, text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        // Skip the harness's own injected blocks — they are not conversation.
        guard !clean.hasPrefix("<system-reminder>"),
              !clean.hasPrefix("<local-command"),
              !clean.hasPrefix("Caveat:") else { return }
        entries.append(Entry(role: role, text: clean))
    }

    // MARK: - context usage

    /// Model and context-window usage for a session, taken from the last
    /// assistant message that carried API usage numbers.
    struct ContextInfo {
        let modelId: String
        let tokens: Int

        /// "claude-fable-5" → "Fable 5", "claude-haiku-4-5-20251001" → "Haiku 4.5".
        var modelName: String {
            var parts = modelId.replacingOccurrences(of: "claude-", with: "")
                .split(separator: "-").map(String.init)
            parts.removeAll { $0.count == 8 && Int($0) != nil }   // build dates
            guard let family = parts.first else { return modelId }
            let name = family.prefix(1).uppercased() + family.dropFirst()
            let version = parts.dropFirst().joined(separator: ".")
            return version.isEmpty ? name : "\(name) \(version)"
        }

        /// Fable runs a 1M window; everything else defaults to 200k — unless
        /// the observed usage already exceeds that, which proves a 1M session.
        var window: Int {
            if modelId.contains("fable") || modelId.contains("[1m]") { return 1_000_000 }
            return tokens > 200_000 ? 1_000_000 : 200_000
        }

        /// e.g. "Fable 5 · 217k/1M (22%)" — compact, the subheader is narrow.
        var summary: String {
            let used = tokens >= 1_000_000
                ? String(format: "%.2fM", Double(tokens) / 1_000_000)
                : tokens >= 100_000
                    ? "\(tokens / 1000)k"
                    : String(format: "%.1fk", Double(tokens) / 1_000)
            let total = window >= 1_000_000 ? "\(window / 1_000_000)M" : "\(window / 1_000)k"
            let pct = Int((Double(tokens) / Double(window) * 100).rounded())
            return "\(modelName) · \(used)/\(total) (\(pct)%)"
        }
    }

    static func contextInfo(id: String, cwd: String) -> ContextInfo? {
        contextInfo(fromLines: tailLines(id: id, cwd: cwd))
    }

    static func contextInfo(fromLines lines: [String]) -> ContextInfo? {
        for line in lines.reversed() {
            guard line.count < maxLineLength,
                  line.contains("\"usage\""), line.contains("\"assistant\""),
                  let data = line.data(using: .utf8),
                  let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  record["type"] as? String == "assistant",
                  let message = record["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any]
            else { continue }

            let tokens = ["input_tokens", "cache_creation_input_tokens",
                          "cache_read_input_tokens", "output_tokens"]
                .compactMap { usage[$0] as? Int }
                .reduce(0, +)
            guard tokens > 0 else { continue }
            return ContextInfo(modelId: message["model"] as? String ?? "?", tokens: tokens)
        }
        return nil
    }

    /// What the current turn has cost and what it is doing — the numbers
    /// Claude Code shows next to its own spinner.
    ///
    /// All of it comes off the transcript already on disk, so displaying it
    /// costs nothing: output tokens since the last user message, and a verb
    /// derived from the most recent tool call.
    struct TurnStats {
        let outputTokens: Int
        let verb: String

        var tokenText: String {
            outputTokens >= 1000
                ? String(format: "%.1fk tokens", Double(outputTokens) / 1000)
                : "\(outputTokens) tokens"
        }
    }

    // MARK: - agents and background work

    /// A subagent or background shell the session has started.
    ///
    /// Claude Code records these as ordinary tool calls, and their completion
    /// as the matching `tool_result` — so "still running" is simply a call
    /// whose result has not been written yet.
    struct AgentRun {
        enum Kind { case agent, background }
        let kind: Kind
        let label: String
        let isRunning: Bool
        /// When the call was made, where the record carried a timestamp.
        var started: Date?

        var symbol: String { kind == .agent ? "\u{25B8}\u{25B8}" : "\u{2338}" }
    }

    /// Subagents and background shells from the recent transcript, oldest
    /// first. Running ones last, since those are what you are waiting on.
    static func agentRuns(id: String, cwd: String, limit: Int = 8) -> [AgentRun] {
        agentRuns(fromLines: tailLines(id: id, cwd: cwd), limit: limit)
    }

    /// Split out from the file reading so it can be exercised against known
    /// transcript lines rather than whatever happens to be on disk.
    static func agentRuns(fromLines lines: [String], limit: Int = 8,
                          now: Date = Date()) -> [AgentRun] {
        var pending: [(id: String, kind: AgentRun.Kind, label: String, started: Date?)] = []
        var finished = Set<String>()

        for line in lines {
            // Each record carries when it was written; used to drop work that
            // finished long ago rather than let it sit there looking current.
            let started = timestamp(in: line)
            // A background shell gets its tool_result the instant it starts —
            // that is only the acknowledgement. Its real completion arrives
            // later as a task notification quoting the original call's id.
            if line.contains("task-notification") {
                for id in matches(of: "<tool-use-id>", in: line, terminator: "<") {
                    finished.insert(id)
                }
            }

            guard line.count < maxLineLength,
                  line.contains("tool_use") || line.contains("tool_result"),
                  let data = line.data(using: .utf8),
                  let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = record["message"] as? [String: Any],
                  let blocks = message["content"] as? [[String: Any]]
            else { continue }

            for block in blocks {
                switch block["type"] as? String {
                case "tool_use":
                    guard let useId = block["id"] as? String,
                          let name = block["name"] as? String else { continue }
                    let input = block["input"] as? [String: Any] ?? [:]

                    if name == "Task" || name == "Agent" {
                        let label = (input["description"] as? String)
                            ?? (input["subagent_type"] as? String)
                            ?? "subagent"
                        pending.append((useId, .agent, label, started))
                    } else if name == "Bash", input["run_in_background"] as? Bool == true {
                        let label = (input["description"] as? String)
                            ?? (input["command"] as? String)
                            ?? "background shell"
                        pending.append((useId, .background, String(label.prefix(46)), started))
                    }

                case "tool_result":
                    // Only settles a subagent; background shells wait for
                    // their notification, handled above.
                    if let useId = block["tool_use_id"] as? String,
                       pending.last(where: { $0.id == useId })?.kind != .background {
                        finished.insert(useId)
                    }

                default:
                    continue
                }
            }
        }

        let runs = pending.map {
            AgentRun(kind: $0.kind, label: $0.label,
                     isRunning: !finished.contains($0.id), started: $0.started)
        }
        // Anything still going is the point. Finished work is context, and
        // only while it is recent — an hour-old job left on screen reads as
        // current activity when it is nothing of the sort.
        let running = runs.filter(\.isRunning)
        let done = runs.filter { run in
            guard !run.isRunning else { return false }
            // No timestamp is not evidence of age — keep it rather than
            // silently hiding work that may well be relevant.
            guard let started = run.started else { return true }
            return now.timeIntervalSince(started) < staleAfter
        }
        return Array((done.suffix(max(0, limit - running.count)) + running).suffix(limit))
    }

    /// How long finished work stays listed.
    private static let staleAfter: TimeInterval = 30 * 60

    /// The `timestamp` field every transcript record carries.
    private static func timestamp(in line: String) -> Date? {
        guard let range = line.range(of: "\"timestamp\":\"") else { return nil }
        let rest = line[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let text = String(rest[..<end])
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: text)
    }

    /// Every value following `needle` up to `terminator`, for the handful of
    /// places the transcript carries XML-ish blocks rather than JSON.
    private static func matches(of needle: String, in line: String,
                                terminator: Character) -> [String] {
        var found: [String] = []
        var rest = Substring(line)
        while let range = rest.range(of: needle) {
            let tail = rest[range.upperBound...]
            guard let end = tail.firstIndex(of: terminator) else { break }
            found.append(String(tail[..<end]))
            rest = tail[end...]
        }
        return found
    }

    /// Whether a session looks like it is mid-turn right now.
    ///
    /// The hooks only report the session Claude Code is currently driving, so
    /// any other tab has to be judged from its transcript: Claude appends to it
    /// continuously while working and not at all when idle, which makes a
    /// recent write a reliable "still going" signal.
    static func isWorking(id: String, cwd: String) -> Bool {
        guard let url = url(id: id, cwd: cwd),
              let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                  .contentModificationDate
        else { return false }
        return Date().timeIntervalSince(modified) < 12
    }

    static func turnStats(id: String, cwd: String) -> TurnStats {
        turnStats(fromLines: tailLines(id: id, cwd: cwd))
    }

    static func turnStats(fromLines lines: [String]) -> TurnStats {
        var tokens = 0
        var lastTool: String?

        // Walk backwards to the last user message; everything after it belongs
        // to the turn in progress.
        for line in lines.reversed() {
            guard line.count < maxLineLength,
                  let data = line.data(using: .utf8),
                  let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = record["type"] as? String
            else { continue }

            if type == "user" { break }
            guard type == "assistant", let message = record["message"] as? [String: Any] else { continue }

            if let usage = message["usage"] as? [String: Any],
               let out = usage["output_tokens"] as? Int {
                tokens += out
            }
            if lastTool == nil, let blocks = message["content"] as? [[String: Any]] {
                lastTool = blocks.last { $0["type"] as? String == "tool_use" }?["name"] as? String
            }
        }
        return TurnStats(outputTokens: tokens, verb: verb(for: lastTool))
    }

    /// A gerund for what Claude is up to, from the tool it last reached for.
    static func verb(for tool: String?) -> String {
        switch tool ?? "" {
        case "Write":                      return "Creating"
        case "Edit", "NotebookEdit":       return "Editing"
        case "Read":                       return "Reading"
        case "Bash", "BashOutput":         return "Running"
        case "Glob", "Grep":               return "Searching"
        case "WebSearch", "WebFetch":      return "Browsing"
        case "Task", "Agent":              return "Delegating"
        case "TaskCreate", "TaskUpdate":   return "Planning"
        case let name where name.hasPrefix("mcp__"): return "Connecting"
        case "":                           return "Thinking"
        default:                           return "Working"
        }
    }

    /// The most recent thing Claude actually said — used as the bubble text
    /// when a job finishes, instead of a canned "P1".
    static func lastAssistantText(id: String, cwd: String) -> String? {
        recent(id: id, cwd: cwd, limit: 200)
            .last { $0.role == .assistant }?
            .text
    }

    /// Tools Claude ran since its last message, newest last — the "steps".
    static func recentTools(id: String, cwd: String, limit: Int = 6) -> [String] {
        let entries = recent(id: id, cwd: cwd, limit: 200)
        var tools: [String] = []
        for entry in entries.reversed() {
            if entry.role == .assistant, !tools.isEmpty { break }
            if entry.role == .tool { tools.append(entry.text) }
            if tools.count >= limit { break }
        }
        return tools.reversed()
    }
}
