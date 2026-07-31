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
    static func recentSessions(limit: Int = 3) -> [SessionRef] {
        let projects = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
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

        // Only the top few get their contents read — stat is cheap, tailing is
        // not — so take a few extra to survive filtering.
        var found: [SessionRef] = []
        for (file, date) in candidates.sorted(by: { $0.1 > $1.1 }).prefix(limit * 3) {
            let (title, cwd) = titleAndCwd(in: file)

            // Background machinery, not conversations you would want to reply to.
            if cwd.contains("/.claude-mem/") || cwd.contains("observer-sessions") { continue }

            found.append(SessionRef(id: file.deletingPathExtension().lastPathComponent,
                                    cwd: cwd, title: title, modified: date))
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
        let projects = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")

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
        var entries: [Entry] = []

        for line in tailLines(id: id, cwd: cwd) {
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
