import AppKit

/// Borderless panels refuse key status by default; typing needs it.
final class ChatPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

/// The pit-wall radio: a small panel above the car that resumes the last
/// Claude Code session the hooks reported.
///
/// Two properties worth knowing:
///  * It talks to the *real* session (`claude -r <id> -p`), not a fork — so it
///    only sends while the session is idle or waiting for input. Sending into
///    a session that is mid-turn would race the terminal that owns it.
///  * Unlike everything else in this app, sending a message here costs tokens,
///    exactly like typing the same thing into Claude Code.
@MainActor
final class ChatController: NSObject, NSTextFieldDelegate {

    private let panel: ChatPanel
    private let transcript = NSTextView()
    private let scroll = NSScrollView()
    private let input = NSTextField()
    private let header = NSTextField(labelWithString: "PIT WALL")
    private weak var trackView: TrackView?
    private var running = false

    private static let width: CGFloat = 420
    private static let height: CGFloat = 250

    init(trackView: TrackView) {
        self.trackView = trackView
        panel = ChatPanel(contentRect: CGRect(x: 0, y: 0, width: Self.width, height: Self.height),
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        super.init()
        buildUI()
    }

    private func buildUI() {
        panel.level = OverlayWindow.petLevel + 2
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = NSView(frame: CGRect(x: 0, y: 0, width: Self.width, height: Self.height))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.86).cgColor
        content.layer?.cornerRadius = 12

        // Transcript.
        let inset: CGFloat = 10
        scroll.frame = CGRect(x: inset, y: 46, width: Self.width - inset * 2,
                              height: Self.height - 46 - inset - 18)
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        transcript.frame = scroll.bounds
        transcript.isEditable = false
        transcript.drawsBackground = false
        transcript.textColor = .white
        transcript.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        transcript.autoresizingMask = [.width]
        scroll.documentView = transcript
        content.addSubview(scroll)

        // Title strip — shows the live session name.
        header.frame = CGRect(x: inset, y: Self.height - 24, width: Self.width - inset * 2, height: 16)
        header.font = .monospacedSystemFont(ofSize: 10, weight: .bold)
        header.textColor = NSColor.white.withAlphaComponent(0.55)
        header.lineBreakMode = .byTruncatingTail
        content.addSubview(header)

        // Input.
        input.frame = CGRect(x: inset, y: inset, width: Self.width - inset * 2, height: 26)
        input.placeholderString = "Message Claude… (Enter to send, Esc to close)"
        input.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        input.bezelStyle = .roundedBezel
        input.target = self
        input.action = #selector(send)
        content.addSubview(input)

        panel.contentView = content
        panel.appearance = NSAppearance(named: .darkAqua)
    }

    // MARK: - open / close

    func toggle() {
        panel.isVisible ? close() : open()
    }

    func close() { panel.orderOut(nil) }

    private func open() {
        // Sit just above the car's window, hugging the right edge.
        if let overlay = trackView?.window {
            let f = overlay.frame
            panel.setFrameOrigin(CGPoint(x: f.maxX - Self.width - 16, y: f.maxY + 6))
        }
        header.stringValue = headerText()
        if transcript.string.isEmpty {
            appendSystem(sessionSummary())
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(input)
    }

    private func sessionSummary() -> String {
        guard let (id, cwd) = StateChannel.readSession() else {
            return "No Claude Code session seen yet — the hooks report one as soon as you use Claude Code."
        }
        let project = (cwd as NSString).lastPathComponent
        if let title = StateChannel.readSessionTitle(id: id, cwd: cwd) {
            return "\u{201C}\(title)\u{201D}\n\(project) · \(id.prefix(8))…"
        }
        return "\(project) · \(id.prefix(8))…"
    }

    /// Session title for the panel's header strip, refreshed each time it opens
    /// — Claude Code renames sessions as they develop.
    private func headerText() -> String {
        guard let (id, cwd) = StateChannel.readSession(),
              let title = StateChannel.readSessionTitle(id: id, cwd: cwd) else {
            return "PIT WALL — reply to last session"
        }
        return "PIT WALL — " + title.uppercased()
    }

    // MARK: - sending

    @objc private func send() {
        let text = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !running else { return }

        guard let (sessionId, cwd) = StateChannel.readSession() else {
            appendSystem("No session to reply to yet.")
            return
        }

        // Don't race a session that is mid-turn — the terminal owns it.
        if let state = trackView?.currentState, state == .launch || state == .racing || state == .spin {
            appendSystem("Session is mid-turn — wait for the car to stop.")
            return
        }

        input.stringValue = ""
        appendUser(text)
        appendSystem("…")
        running = true

        let claude = NSHomeDirectory() + "/.local/bin/claude"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: claude)
        task.arguments = ["-r", sessionId, "-p", text]
        task.currentDirectoryURL = URL(fileURLWithPath: cwd)

        let out = Pipe(), err = Pipe()
        task.standardOutput = out
        task.standardError = err

        DispatchQueue.global().async { [weak self] in
            var reply = ""
            do {
                try task.run()
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let errData = err.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                reply = String(data: data, encoding: .utf8) ?? ""
                if reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let errText = String(data: errData, encoding: .utf8) ?? ""
                    reply = errText.isEmpty ? "(no reply)" : errText
                }
            } catch {
                reply = "failed to run claude: \(error.localizedDescription)"
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.running = false
                    self.replaceLastSystemLine(with: reply.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
    }

    // MARK: - transcript

    private func append(_ text: String, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: color,
        ]
        transcript.textStorage?.append(NSAttributedString(string: text + "\n", attributes: attrs))
        transcript.scrollToEndOfDocument(nil)
    }

    private func appendUser(_ text: String) {
        append("you  > " + text, color: NSColor(srgbRed: 0.55, green: 0.78, blue: 1, alpha: 1))
    }

    private func appendSystem(_ text: String) {
        append(text, color: NSColor.white.withAlphaComponent(0.75))
    }

    private func replaceLastSystemLine(with text: String) {
        // Drop the trailing "…" placeholder line, then append the reply.
        if let storage = transcript.textStorage {
            let full = storage.string as NSString
            let lastLine = full.range(of: "…\n", options: .backwards)
            if lastLine.location != NSNotFound {
                storage.deleteCharacters(in: lastLine)
            }
        }
        appendSystem(text)
    }
}
