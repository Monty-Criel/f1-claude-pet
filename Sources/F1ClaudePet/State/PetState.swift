import Foundation

/// What the car is doing. Claude Code's lifecycle maps onto these.
enum PetState: String, CaseIterable {
    /// Parked in the garage, engine idling. Nothing is happening.
    case idle
    /// Lights out — stationary burnout before the launch.
    case launch
    /// Flat out. Claude is working.
    case racing
    /// Sat waiting for the driver, i.e. Claude needs your input.
    case waiting
    /// Job done — victory burnout.
    case victory
    /// Something broke: spin, smoke, limp home.
    case spin
    /// Not a resting state — a one-off burst of speed when a tool fires.
    /// Applying it kicks the car and drops straight back into `racing`.
    case boost

    var isBurningOut: Bool { self == .launch || self == .victory }

    /// Menu label. `spin` predates the breakdown animation — the state is a
    /// crash now, but the raw value stays for CLI and hook compatibility.
    var displayName: String {
        self == .spin ? "Crash" : rawValue.capitalized
    }

    /// One line describing what the car does — shown under each menu item and
    /// used by `--notify --help`.
    var summary: String {
        switch self {
        case .idle:    return "Parked in the pit box, engine ticking over"
        case .launch:  return "Lights out — burnout on the line, then away"
        case .racing:  return "Working: wheels turning, laps in lively mode"
        case .waiting: return "Pits and flashes its rain light for you"
        case .victory: return "Job done — donut and smoke, then parks"
        case .spin:    return "Failure — stops, blows a tyre, catches fire"
        case .boost:   return "A tool just ran — burst of speed and smoke"
        }
    }
}

/// One-way channel from Claude Code hooks into the running pet.
///
/// A file rather than a socket: hooks are short-lived shell commands, and a
/// single atomic write is the simplest thing that survives the pet not running,
/// starting late, or being restarted mid-session.
enum StateChannel {

    /// Overridable for tests, which point it at a scratch directory; the
    /// running app always uses the real one.
    nonisolated(unsafe) static var rootOverride: URL?

    static var directory: URL {
        rootOverride
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".f1-claude-pet")
    }

    static var file: URL {
        directory.appendingPathComponent("state")
    }

    /// Optional caption shown in the radio bubble, e.g. the tool that just ran.
    static var messageFile: URL {
        directory.appendingPathComponent("message")
    }

    /// Called by `--notify`. Writes atomically so a reader never sees a partial value.
    ///
    /// The message is written *before* the state, because the state file's
    /// mtime is what wakes the watcher — writing it last means the message is
    /// already in place by the time anything reads it.
    static func write(_ state: PetState, message: String? = nil) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? (message ?? "").write(to: messageFile, atomically: true, encoding: .utf8)
        try? state.rawValue.write(to: file, atomically: true, encoding: .utf8)
    }

    static func read() -> PetState? {
        guard let raw = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return PetState(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func readMessage() -> String? {
        guard let raw = try? String(contentsOf: messageFile, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Which Claude Code session the hooks are reporting for, captured from
    /// every hook payload: session id on line 1, project cwd on line 2.
    static var sessionFile: URL {
        directory.appendingPathComponent("session")
    }

    /// The session's human-readable title, as shown in Claude Code's sidebar.
    ///
    /// Claude Code stores it as `customTitle` on records inside the session
    /// transcript. Transcripts run to tens of megabytes, so only the tail is
    /// read — the field is written repeatedly throughout a session, so recent
    /// records carry it. Falls back to the derived name in
    /// `~/.claude/sessions/<pid>.json`, then to nothing.
    static func readSessionTitle(id: String, cwd: String) -> String? {
        if let url = transcriptURL(id: id, cwd: cwd),
           let title = lastCustomTitle(in: url) {
            return title
        }
        return derivedName(id: id)
    }

    /// One transcript resolver for the whole app — Transcript owns it.
    private static func transcriptURL(id: String, cwd: String) -> URL? {
        Transcript.url(id: id, cwd: cwd)
    }

    /// Scan the last chunk of a transcript for the most recent `customTitle`.
    private static func lastCustomTitle(in url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let window: UInt64 = 512 * 1024
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > window ? size - window : 0)
        guard let data = try? handle.readToEnd() else { return nil }

        // Lossy decode: the window may start mid-character.
        let text = String(decoding: data, as: UTF8.self)
        let key = "\"customTitle\":\""
        guard let keyRange = text.range(of: key, options: .backwards) else { return nil }
        let rest = text[keyRange.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }

        let title = String(rest[..<end])
        return title.isEmpty ? nil : title
    }

    /// `~/.claude/sessions/<pid>.json` carries a short derived name.
    private static func derivedName(id: String) -> String? {
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/sessions")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return nil }

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["sessionId"] as? String == id else { continue }
            return json["name"] as? String
        }
        return nil
    }

    static func readSession() -> (id: String, cwd: String)? {
        guard let raw = try? String(contentsOf: sessionFile, encoding: .utf8) else { return nil }
        let lines = raw.components(separatedBy: "\n")
        guard let id = lines.first?.trimmingCharacters(in: .whitespaces), !id.isEmpty else { return nil }
        let cwd = lines.count > 1 ? lines[1].trimmingCharacters(in: .whitespaces) : ""
        return (id, cwd.isEmpty ? NSHomeDirectory() : cwd)
    }

    /// When the current turn started, stamped by the `UserPromptSubmit` hook.
    /// Lets the pit wall show elapsed time without polling anything.
    static func turnStart() -> Date? {
        let path = directory.appendingPathComponent("turn-start").path
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8),
              let seconds = TimeInterval(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Modification date, used to notice repeat notifications of the same state
    /// (two `racing` events in a row should still re-trigger the animation).
    static func modified() -> Date? {
        try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
    }
}

/// Polls the state file and reports changes.
///
/// Polling rather than watching a file descriptor, because atomic writes
/// replace the inode and would silently break an fd-based watcher.
@MainActor
final class StateWatcher {
    private var timer: Timer?
    private var lastSeen: Date?
    private let onChange: (PetState, String?) -> Void

    init(onChange: @escaping (PetState, String?) -> Void) {
        self.onChange = onChange
    }

    func start() {
        lastSeen = StateChannel.modified()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard let modified = StateChannel.modified() else { return }
        guard modified != lastSeen else { return }
        lastSeen = modified
        if let state = StateChannel.read() {
            onChange(state, StateChannel.readMessage())
        }
    }
}
