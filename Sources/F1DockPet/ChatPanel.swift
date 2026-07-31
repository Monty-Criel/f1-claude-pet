import AppKit

/// Borderless panels refuse key status by default; typing needs it.
final class ChatPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

/// The pit-wall radio: a panel above the car showing the live conversation and
/// letting you reply into the last Claude Code session the hooks reported.
///
/// Two properties worth knowing:
///  * It talks to the *real* session (`claude -r <id> -p`), not a fork — so it
///    only sends while the session is idle or waiting for input. Sending into
///    a session that is mid-turn would race the terminal that owns it.
///  * Unlike everything else in this app, sending a message here costs tokens,
///    exactly like typing the same thing into Claude Code.
@MainActor
final class ChatController: NSObject {

    private let panel: ChatPanel
    private let transcript = NSTextView()
    private let scroll = NSScrollView()
    private let input = NSTextField()
    private let header = NSTextField(labelWithString: "PIT WALL")
    private let subheader = NSTextField(labelWithString: "")
    private let statusDot = NSView()
    private var lamps: [NSView] = []

    private let pinButton = NSButton()
    private let closeButton = NSButton()
    private let spinner = WheelSpinner(frame: .zero)
    private let workLabel = NSTextField(labelWithString: "")

    private weak var trackView: TrackView?
    private var running = false
    private var refresh: Timer?
    private var follow: Timer?
    /// What is currently on screen, so identical refreshes are skipped.
    private var lastRendered = ""

    /// The three most recently active sessions, and which one is showing.
    private var sessions: [Transcript.SessionRef] = []
    private var selected: Transcript.SessionRef?
    private let tabBar = NSView()
    /// The Usage tab replaces the transcript with plan-limit bars.
    private var showingUsage = false

    /// A panel dedicated to one session (the second car's). No tabs, no
    /// following the hooks — it is that conversation, permanently.
    var fixedSession: Transcript.SessionRef?

    /// Sessions owned by another car, hidden from this panel's tabs.
    var excludedSessionIds: () -> Set<String> = { [] }

    /// Pinned panels ride above the car; unpinned ones stay where you drop them.
    private var isPinned: Bool {
        get { UserDefaults.standard.object(forKey: "chatPinned") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "chatPinned") }
    }

    private static let width: CGFloat = 460
    /// Tall enough that the Usage tab fits its bars, histogram and stats
    /// without scrolling.
    private static let height: CGFloat = 560

    // Claude orange, everywhere the panel needs an accent.
    private var accent: NSColor { Theme.accent }

    init(trackView: TrackView) {
        self.trackView = trackView
        panel = ChatPanel(contentRect: CGRect(x: 0, y: 0, width: Self.width, height: Self.height),
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        super.init()
        buildUI()
        NotificationCenter.default.addObserver(
            forName: Theme.changed, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyTheme() }
            }
    }

    /// Repaint everything that carries the accent, after a theme change.
    private func applyTheme() {
        panel.contentView?.layer?.backgroundColor = Theme.panelBackground.cgColor
        stripe?.layer?.backgroundColor = accent.cgColor
        rebuildTabs()
        applyPinState()
        lastRendered = ""            // role tags and bars are accent-coloured
        spinner.needsDisplay = true
        reload()
    }

    // MARK: - chrome

    private func buildUI() {
        panel.level = OverlayWindow.petLevel + 2
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)

        let content = NSView(frame: CGRect(x: 0, y: 0, width: Self.width, height: Self.height))
        content.wantsLayer = true
        content.layer?.backgroundColor = Theme.panelBackground.cgColor
        content.layer?.cornerRadius = 14
        content.layer?.borderWidth = 1
        content.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor

        let inset: CGFloat = 12

        // Header band — carries the team colour so the panel matches the car.
        let band = NSView(frame: CGRect(x: 0, y: Self.height - 44, width: Self.width, height: 44))
        band.wantsLayer = true
        band.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
        content.addSubview(band)

        let stripe = NSView(frame: CGRect(x: 0, y: Self.height - 46, width: Self.width, height: 2))
        stripe.wantsLayer = true
        content.addSubview(stripe)
        self.stripe = stripe

        // Marshalling lights: green / yellow / red, read left to right like a
        // trackside panel. Exactly one is lit at a time; the others sit dark.
        statusDot.frame = CGRect(x: inset, y: Self.height - 26, width: 34, height: 12)
        statusDot.wantsLayer = true
        statusDot.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        statusDot.layer?.cornerRadius = 3
        for i in 0..<3 {
            let lamp = NSView(frame: CGRect(x: 3 + CGFloat(i) * 11, y: 2, width: 8, height: 8))
            lamp.wantsLayer = true
            lamp.layer?.cornerRadius = 4
            statusDot.addSubview(lamp)
            lamps.append(lamp)
        }
        content.addSubview(statusDot)

        header.frame = CGRect(x: inset + 42, y: Self.height - 25, width: Self.width - inset * 2 - 100, height: 15)
        header.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
        header.textColor = .white
        header.lineBreakMode = .byTruncatingTail
        content.addSubview(header)

        // Pin / unpin and close, top right of the header band.
        closeButton.frame = CGRect(x: Self.width - inset - 20, y: Self.height - 30, width: 20, height: 20)
        closeButton.isBordered = false
        closeButton.bezelStyle = .accessoryBarAction
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        closeButton.contentTintColor = NSColor.white.withAlphaComponent(0.5)
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        content.addSubview(closeButton)

        pinButton.frame = CGRect(x: Self.width - inset - 46, y: Self.height - 30, width: 20, height: 20)
        pinButton.isBordered = false
        pinButton.bezelStyle = .accessoryBarAction
        pinButton.target = self
        pinButton.action = #selector(togglePin)
        content.addSubview(pinButton)

        // Working indicator: a spinning Pirelli wheel trailing themed smoke,
        // with the same numbers Claude Code shows beside its own spinner —
        // all read off the transcript, so it costs nothing to display.
        spinner.frame = CGRect(x: inset, y: 46, width: 26, height: 22)
        content.addSubview(spinner)

        workLabel.frame = CGRect(x: inset + 30, y: 48, width: Self.width - inset * 2 - 30, height: 16)
        workLabel.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        workLabel.lineBreakMode = .byTruncatingTail
        workLabel.isHidden = true
        content.addSubview(workLabel)

        subheader.frame = CGRect(x: inset + 42, y: Self.height - 40, width: Self.width - inset * 2 - 100, height: 13)
        subheader.font = .monospacedSystemFont(ofSize: 9, weight: .regular)
        subheader.textColor = NSColor.white.withAlphaComponent(0.45)
        subheader.lineBreakMode = .byTruncatingTail
        content.addSubview(subheader)

        // Session switcher: the three most recently active conversations.
        tabBar.frame = CGRect(x: inset, y: Self.height - 72, width: Self.width - inset * 2, height: 22)
        content.addSubview(tabBar)

        // Conversation.
        scroll.frame = CGRect(x: inset, y: 48, width: Self.width - inset * 2,
                              height: Self.height - 48 - 78)
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true

        // A hand-built NSTextView needs this whole incantation to behave in a
        // scroll view. Without `isVerticallyResizable` it keeps the fixed frame
        // it was given, so text lays out from the bottom of that frame upwards
        // and every new message appears to shove the view around.
        transcript.frame = CGRect(origin: .zero, size: scroll.contentSize)
        transcript.minSize = NSSize(width: 0, height: 0)
        transcript.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                    height: CGFloat.greatestFiniteMagnitude)
        transcript.isVerticallyResizable = true
        transcript.isHorizontallyResizable = false
        transcript.autoresizingMask = [.width]
        transcript.textContainer?.containerSize = NSSize(width: scroll.contentSize.width,
                                                         height: CGFloat.greatestFiniteMagnitude)
        transcript.textContainer?.widthTracksTextView = true
        transcript.isEditable = false
        transcript.isSelectable = true
        transcript.drawsBackground = false
        transcript.textContainerInset = NSSize(width: 2, height: 4)

        scroll.documentView = transcript
        content.addSubview(scroll)

        // Input.
        input.frame = CGRect(x: inset, y: 12, width: Self.width - inset * 2, height: 28)
        input.placeholderString = "Message Claude…  ⏎ send   esc close"
        input.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        input.bezelStyle = .roundedBezel
        input.focusRingType = .none
        input.target = self
        input.action = #selector(send)
        content.addSubview(input)

        panel.contentView = content
    }

    private var stripe: NSView?

    // MARK: - open / close

    func toggle() { panel.isVisible ? close() : open() }

    func close() {
        refresh?.invalidate(); refresh = nil
        follow?.invalidate(); follow = nil
        trackView?.isChatOpen = false
        panel.orderOut(nil)
    }

    private func open() {
        // Park the car while you read — a panel pinned to a moving car is
        // unreadable.
        trackView?.isChatOpen = true
        showingUsage = false
        if let fixed = fixedSession {
            sessions = [fixed]
            selected = fixed
        } else {
            let excluded = excludedSessionIds()
            sessions = Array(Transcript.recentSessions(limit: 2 + excluded.count)
                .filter { !excluded.contains($0.id) }
                .prefix(2))
            selected = sessions.first { $0.id == StateChannel.readSession()?.id } ?? sessions.first
        }
        rebuildTabs()
        applyLayout()
        applyPinState()
        stripe?.layer?.backgroundColor = accent.cgColor
        reload()

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(input)

        // Follow the session while the panel is open.
        refresh = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload(preserveScroll: true) }
        }
        // Ride above the car. 20Hz is plenty — the car is usually parked, and
        // this only runs while the panel is actually open.
        follow = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.followCar() }
        }
    }

    // MARK: - anchoring

    /// One button per recent session plus the Usage tab, laid out evenly.
    private func rebuildTabs() {
        tabBar.subviews.forEach { $0.removeFromSuperview() }
        let includeUsage = fixedSession == nil   // the second car's panel stays single-purpose
        let count = sessions.count + (includeUsage ? 1 : 0)
        guard count > 1 else { return }

        let gap: CGFloat = 6
        let usageWidth: CGFloat = includeUsage ? 58 : 0
        let sessionWidth = (tabBar.bounds.width - usageWidth - gap * CGFloat(count - 1))
            / CGFloat(max(sessions.count, 1))

        func makeTab(x: CGFloat, width: CGFloat, title: String, current: Bool) -> NSButton {
            let button = NSButton(frame: CGRect(x: x, y: 0, width: width, height: 22))
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 5
            button.layer?.backgroundColor = current
                ? accent.withAlphaComponent(0.22).cgColor
                : NSColor.white.withAlphaComponent(0.05).cgColor
            button.layer?.borderWidth = current ? 1 : 0
            button.layer?.borderColor = accent.withAlphaComponent(0.55).cgColor
            button.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 9, weight: current ? .bold : .regular),
                .foregroundColor: current ? NSColor.white : NSColor.white.withAlphaComponent(0.55),
            ])
            button.target = self
            tabBar.addSubview(button)
            return button
        }

        for (index, session) in sessions.enumerated() {
            let button = makeTab(x: (sessionWidth + gap) * CGFloat(index), width: sessionWidth,
                                 title: session.label,
                                 current: !showingUsage && session.id == selected?.id)
            var tip = "\(session.title.isEmpty ? "(untitled)" : session.title)\n\(session.cwd)"
            if let info = Transcript.contextInfo(id: session.id, cwd: session.cwd) {
                tip += "\n\(info.summary)"
            }
            button.toolTip = tip
            button.tag = index
            button.action = #selector(selectSession(_:))
        }

        if includeUsage {
            let button = makeTab(x: tabBar.bounds.width - usageWidth, width: usageWidth,
                                 title: "Usage", current: showingUsage)
            button.toolTip = "Plan usage limits — 5-hour and weekly"
            button.action = #selector(selectUsage)
        }
    }

    @objc private func selectSession(_ sender: NSButton) {
        guard sessions.indices.contains(sender.tag) else { return }
        showingUsage = false
        selected = sessions[sender.tag]
        lastRendered = ""          // force a redraw of the new conversation
        rebuildTabs()
        applyLayout()
        reload()
    }

    @objc private func selectUsage() {
        // ⌥-click forces a live refetch; a plain click uses the cache, which
        // avoids a keychain prompt.
        let force = NSEvent.modifierFlags.contains(.option)
        showingUsage = true
        lastRendered = ""
        rebuildTabs()
        applyLayout()
        reloadUsage(force: force)
    }

    /// The Usage tab has nothing to type into, so it gets the composer's space
    /// and runs full height.
    private func applyLayout() {
        input.isHidden = showingUsage
        let bottom: CGFloat = showingUsage ? 14 : 48
        scroll.frame = CGRect(x: 12, y: bottom, width: Self.width - 24,
                              height: Self.height - bottom - 78)
        transcript.frame = CGRect(origin: .zero, size: scroll.contentSize)
        transcript.textContainer?.containerSize = NSSize(width: scroll.contentSize.width,
                                                         height: CGFloat.greatestFiniteMagnitude)
    }

    @objc private func togglePin() {
        isPinned.toggle()
        applyPinState()
    }

    @objc private func closeClicked() { close() }

    private func applyPinState() {
        let pinned = isPinned
        pinButton.image = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin.slash",
                                  accessibilityDescription: pinned ? "Unpin" : "Pin to car")
        pinButton.contentTintColor = pinned ? accent : NSColor.white.withAlphaComponent(0.45)
        pinButton.toolTip = pinned
            ? "Pinned to the car — click to move it freely"
            : "Free — click to pin it back above the car"

        // Dragging is only allowed when unpinned; otherwise the panel would
        // fight the car for position every frame.
        panel.isMovableByWindowBackground = !pinned

        if pinned { followCar(force: true) }
    }

    /// Keep the panel sitting just above the car, clamped on screen.
    private func followCar(force: Bool = false) {
        guard isPinned, force || panel.isVisible else { return }
        guard let car = trackView?.carScreenRect else { return }

        let screen = trackView?.window?.screen ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

        // Align the panel's near edge with the car rather than centring, so it
        // reads as hanging off the car. Which edge depends on where the car
        // lives: a left-parked car takes a left-aligned panel, otherwise the
        // panel would hang off the screen and get clamped back anyway.
        //
        // Clear the radio bubble as well as the car: when a bubble is up it is
        // taller than the car, and anchoring to the car alone buries it.
        let parksLeft = car.midX < bounds.midX
        var x = parksLeft ? car.minX - 18 : car.maxX - Self.width + 18
        var y = (trackView?.contentTopScreenY ?? car.maxY) + 12
        x = max(bounds.minX + 8, min(x, bounds.maxX - Self.width - 8))
        y = min(y, bounds.maxY - Self.height - 8)

        let origin = CGPoint(x: x.rounded(), y: y.rounded())
        if force || panel.frame.origin != origin {
            panel.setFrameOrigin(origin)
        }
    }

    // MARK: - content

    /// The session the panel is showing: whichever tab is selected, falling
    /// back to whatever the hooks last reported.
    private var activeSession: (id: String, cwd: String)? {
        if let selected { return (selected.id, selected.cwd) }
        return StateChannel.readSession()
    }

    private func reload(preserveScroll: Bool = false) {
        // A send in flight has an optimistic echo on screen that is not in the
        // transcript yet; rebuilding now would delete it under the user.
        if running && preserveScroll { return }

        if showingUsage { reloadUsage(preserveScroll: preserveScroll); return }

        guard let (id, cwd) = activeSession else {
            header.stringValue = "PIT WALL"
            subheader.stringValue = "no session yet"
            updateLamps(for: .idle)
            setBody(preserveScroll: preserveScroll, NSAttributedString(
                string: "No Claude Code session seen yet.\n\nThe hooks register one the moment you use Claude Code — then this panel shows the conversation and you can reply from here.",
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                             .foregroundColor: NSColor.white.withAlphaComponent(0.5)]))
            return
        }

        let title = StateChannel.readSessionTitle(id: id, cwd: cwd)
        header.stringValue = title ?? "PIT WALL"
        var sub = "\((cwd as NSString).lastPathComponent) · \(id.prefix(8))…"
        if let info = Transcript.contextInfo(id: id, cwd: cwd) {
            sub += " · " + info.summary
        }
        subheader.stringValue = sub

        let state = trackView?.currentState ?? .idle
        updateLamps(for: state)
        updateWorkingRow(id: id, cwd: cwd, state: state)

        setBody(preserveScroll: preserveScroll, render(Transcript.recent(id: id, cwd: cwd, limit: 40)))
    }

    /// The spinner row: wheel, verb, elapsed, tokens — shown only while the
    /// session the hooks are watching is actually mid-turn.
    private func updateWorkingRow(id: String, cwd: String, state: PetState) {
        let isLive = id == StateChannel.readSession()?.id
        let working = isLive && (state == .launch || state == .racing || state == .boost)

        spinner.isSpinning = working
        workLabel.isHidden = !working
        guard working else {
            // Give the conversation its space back.
            scroll.frame.origin.y = showingUsage ? 14 : 48
            scroll.frame.size.height = Self.height - scroll.frame.origin.y - 78
            return
        }

        // Sit the conversation above the spinner row.
        scroll.frame.origin.y = 72
        scroll.frame.size.height = Self.height - 72 - 78

        let stats = Transcript.turnStats(id: id, cwd: cwd)
        var text = stats.verb
        if let start = StateChannel.turnStart() {
            let elapsed = Int(Date().timeIntervalSince(start))
            if elapsed >= 0, elapsed < 86_400 {
                text += elapsed < 60 ? "  \(elapsed)s"
                    : "  \(elapsed / 60)m \(elapsed % 60)s"
            }
        }
        if stats.outputTokens > 0 { text += "  ·  " + stats.tokenText }

        workLabel.attributedStringValue = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: accent.withAlphaComponent(0.9)])
    }

    // MARK: - usage tab

    private func reloadUsage(preserveScroll: Bool = false, force: Bool = false) {
        header.stringValue = "PLAN USAGE"
        subheader.stringValue = "plan limits \(UsageService.freshnessNote) · ⌥-click the tab to refresh now"
        spinner.isSpinning = false
        workLabel.isHidden = true
        updateLamps(for: trackView?.currentState ?? .idle)
        setBody(preserveScroll: preserveScroll, renderUsage())

        UsageService.refresh(force: force) { [weak self] in
            guard let self, self.showingUsage else { return }
            self.subheader.stringValue =
                "plan limits \(UsageService.freshnessNote) · ⌥-click the tab to refresh now"
            self.setBody(preserveScroll: true, self.renderUsage())
        }
    }

    private func renderUsage() -> NSAttributedString {
        let body = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let dim: [NSAttributedString.Key: Any] = [
            .font: body, .foregroundColor: NSColor.white.withAlphaComponent(0.5)]

        let out = NSMutableAttributedString()

        if UsageService.rows.isEmpty {
            let message = UsageService.error
                ?? "Fetching plan limits…\n\nIf nothing appears, ⌥-click the Usage tab to try again."
            out.append(NSAttributedString(string: message + "\n\n", attributes: dim))
        }

        for row in UsageService.rows {
            let filled = min(14, max(0, Int((Double(row.percent) / 100 * 14).rounded())))
            let barColor: NSColor = row.percent >= 90 ? .systemRed
                : row.percent >= 70 ? .systemOrange
                : accent

            out.append(NSAttributedString(string: row.label + "\n", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.88)]))
            out.append(NSAttributedString(string: String(repeating: "█", count: filled), attributes: [
                .font: body, .foregroundColor: barColor]))
            out.append(NSAttributedString(string: String(repeating: "░", count: 14 - filled), attributes: [
                .font: body, .foregroundColor: NSColor.white.withAlphaComponent(0.18)]))
            out.append(NSAttributedString(string: "  " + (row.valueText ?? "\(row.percent)%"),
                                          attributes: [
                .font: body, .foregroundColor: NSColor.white.withAlphaComponent(0.88)]))
            out.append(NSAttributedString(string: row.resets.isEmpty ? "\n\n" : "   \(row.resets)\n\n",
                                          attributes: dim))
        }
        if let error = UsageService.error {
            out.append(NSAttributedString(string: "last refresh failed: \(error)\n\n", attributes: dim))
        }

        // Weekly histogram: real counts up to today, estimates beyond.
        let bars = UsageService.weekHistogram()
        if !bars.isEmpty {
            out.append(NSAttributedString(string: "THIS WEEK · prompts\n", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .bold),
                .foregroundColor: accent]))
            let peak = max(bars.map(\.count).max() ?? 1, 1)
            for bar in bars {
                let filled = min(12, Int((Double(bar.count) / Double(peak) * 12).rounded()))
                out.append(NSAttributedString(string: bar.label + "  ", attributes: [
                    .font: body, .foregroundColor: NSColor.white.withAlphaComponent(0.55)]))
                out.append(NSAttributedString(string: String(repeating: "█", count: filled), attributes: [
                    .font: body,
                    .foregroundColor: bar.projected ? accent.withAlphaComponent(0.35) : accent]))
                out.append(NSAttributedString(string: String(repeating: "░", count: 12 - filled), attributes: [
                    .font: body, .foregroundColor: NSColor.white.withAlphaComponent(0.12)]))
                let suffix = bar.projected ? "  ~\(bar.count) est"
                    : "  \(bar.count)" + (bar.isToday ? " · today" : "")
                out.append(NSAttributedString(string: suffix + "\n", attributes: [
                    .font: body,
                    .foregroundColor: NSColor.white.withAlphaComponent(bar.projected ? 0.45 : 0.88)]))
            }
            out.append(NSAttributedString(string: "\n", attributes: dim))
        }

        // Local activity KPIs under the plan bars.
        out.append(NSAttributedString(string: "ACTIVITY\n", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .bold),
            .foregroundColor: accent]))
        for stat in UsageService.stats() {
            out.append(NSAttributedString(string: stat.label.padding(toLength: 17, withPad: " ",
                                                                     startingAt: 0), attributes: [
                .font: body, .foregroundColor: NSColor.white.withAlphaComponent(0.55)]))
            out.append(NSAttributedString(string: stat.value + "\n", attributes: [
                .font: body, .foregroundColor: NSColor.white.withAlphaComponent(0.88)]))
        }
        return out
    }

    /// Which marshalling light is showing.
    ///
    /// Trackside meaning, not decoration: green = running, yellow = needs you,
    /// red = stopped. "Done" is green too — the session is healthy and the work
    /// finished — while idle leaves the whole panel dark, like an unused board.
    private enum Lamp: Int { case green = 0, yellow = 1, red = 2, none = -1 }

    private func lamp(for state: PetState) -> Lamp {
        switch state {
        case .racing, .launch, .boost: return .green    // working
        case .victory:                 return .green    // done, all well
        case .waiting:                 return .yellow   // waiting on you
        case .spin:                    return .red      // failed
        case .idle:                    return .none     // board dark
        }
    }

    private func updateLamps(for state: PetState) {
        let lit = lamp(for: state)
        let colors: [NSColor] = [
            NSColor(srgbRed: 0.10, green: 0.85, blue: 0.25, alpha: 1),
            NSColor(srgbRed: 1.00, green: 0.78, blue: 0.05, alpha: 1),
            NSColor(srgbRed: 1.00, green: 0.20, blue: 0.15, alpha: 1),
        ]
        for (index, lampView) in lamps.enumerated() {
            let isLit = index == lit.rawValue
            let color = colors[index]
            lampView.layer?.backgroundColor = isLit
                ? color.cgColor
                : color.withAlphaComponent(0.13).cgColor
            // Only the lit lamp glows.
            lampView.layer?.shadowColor = color.cgColor
            lampView.layer?.shadowOpacity = isLit ? 0.9 : 0
            lampView.layer?.shadowRadius = isLit ? 4 : 0
            lampView.layer?.shadowOffset = .zero
        }
        statusDot.toolTip = {
            switch lit {
            case .green:  return state == .victory ? "Done" : "Working"
            case .yellow: return "Waiting for you"
            case .red:    return "Failed"
            case .none:   return "Idle"
            }
        }()
    }

    /// Within a couple of lines of the end. Measured against the laid-out text,
    /// not the view frame, which lags behind a content change.
    private var isScrolledToBottom: Bool {
        guard let layout = transcript.layoutManager, let container = transcript.textContainer
        else { return true }
        layout.ensureLayout(for: container)
        let contentHeight = layout.usedRect(for: container).height
        let visible = scroll.contentView.documentVisibleRect
        return visible.maxY >= contentHeight - 28
    }

    /// Replace the transcript without yanking the reader around.
    ///
    /// `setAttributedString` resets an NSTextView's scroll position to the top,
    /// so the offset has to be captured beforehand and restored afterwards —
    /// otherwise every refresh throws you back to the start of the session.
    private func setBody(preserveScroll: Bool, _ text: NSAttributedString) {
        // Nothing to do if the content is identical — this runs every 2s.
        if preserveScroll, text.string == lastRendered { return }
        lastRendered = text.string

        let clip = scroll.contentView
        let stickToBottom = !preserveScroll || isScrolledToBottom
        let previousOrigin = clip.bounds.origin

        transcript.textStorage?.setAttributedString(text)
        if let container = transcript.textContainer {
            transcript.layoutManager?.ensureLayout(for: container)
        }

        if stickToBottom {
            // Scroll after the run loop has laid the new text out, otherwise
            // it scrolls to the end of the *previous* content height.
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.transcript.scrollToEndOfDocument(nil) }
            }
        } else {
            clip.scroll(to: previousOrigin)
            scroll.reflectScrolledClipView(clip)
        }
    }

    /// Turn transcript entries into something worth looking at: coloured role
    /// tags, tool steps as a dim indented run, Claude's prose in full.
    private func render(_ entries: [Transcript.Entry]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let body = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let tag = NSFont.monospacedSystemFont(ofSize: 10, weight: .bold)

        if entries.isEmpty {
            return NSAttributedString(string: "Nothing in this session yet.",
                                      attributes: [.font: body,
                                                   .foregroundColor: NSColor.white.withAlphaComponent(0.4)])
        }

        for entry in entries {
            switch entry.role {
            case .user:
                out.append(NSAttributedString(string: "YOU  ", attributes: [
                    .font: tag, .foregroundColor: NSColor(srgbRed: 0.45, green: 0.72, blue: 1, alpha: 1)]))
                out.append(NSAttributedString(string: entry.text + "\n\n", attributes: [
                    .font: body, .foregroundColor: NSColor.white.withAlphaComponent(0.92)]))

            case .assistant:
                out.append(NSAttributedString(string: "CLAUDE  ", attributes: [
                    .font: tag, .foregroundColor: accent]))
                out.append(NSAttributedString(string: entry.text + "\n\n", attributes: [
                    .font: body, .foregroundColor: NSColor.white.withAlphaComponent(0.85)]))

            case .tool:
                out.append(NSAttributedString(string: "   ▸ " + entry.text + "\n", attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.38)]))
            }
        }
        return out
    }

    // MARK: - sending

    @objc private func send() {
        let text = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !running else { return }

        if showingUsage {
            flashSubheader("pick a session tab to reply")
            return
        }

        guard let (sessionId, cwd) = activeSession else {
            flashSubheader("no session to reply to")
            return
        }

        // Don't race a session that is mid-turn — the terminal owns it. This
        // only applies to the session the hooks are actually watching; the car
        // says nothing about the state of the others.
        let isLiveSession = sessionId == StateChannel.readSession()?.id
        if isLiveSession, let state = trackView?.currentState,
           state == .launch || state == .racing || state == .spin {
            flashSubheader("session is mid-turn — wait for the car to stop")
            return
        }

        input.stringValue = ""
        running = true
        subheader.stringValue = "sending…"

        appendLive(role: "YOU", text: text, color: NSColor(srgbRed: 0.45, green: 0.72, blue: 1, alpha: 1))

        let task = Process()
        task.executableURL = URL(fileURLWithPath: NSHomeDirectory() + "/.local/bin/claude")
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
                    self.subheader.stringValue = ""
                    self.reload()
                    _ = reply       // the transcript is the source of truth
                }
            }
        }
    }

    private func appendLive(role: String, text: String, color: NSColor) {
        let out = NSMutableAttributedString()
        out.append(NSAttributedString(string: role + "  ", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .bold), .foregroundColor: color]))
        out.append(NSAttributedString(string: text + "\n\n", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.92)]))
        transcript.textStorage?.append(out)
        transcript.scrollToEndOfDocument(nil)
    }

    private func flashSubheader(_ text: String) {
        subheader.stringValue = text
        subheader.textColor = NSColor.systemOrange
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            MainActor.assumeIsolated {
                self?.subheader.textColor = NSColor.white.withAlphaComponent(0.45)
                self?.reload(preserveScroll: true)
            }
        }
    }
}
