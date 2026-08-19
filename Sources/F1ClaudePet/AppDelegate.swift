import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    /// Vertical room above the Dock: the car, plus headroom for tyre smoke
    /// and the radio bubble.
    static let trackHeight: CGFloat = 150

    private var window: OverlayWindow!
    private var trackView: TrackView!
    private var dockWatcher: Timer?
    private var stateWatcher: StateWatcher?
    private var menuBar: MenuBarController?
    private var chat: ChatController?

    // The optional second car: same Dock, parked at the left end, drawn
    // behind the primary, bound to one chosen session.
    private var secondWindow: OverlayWindow?
    private var secondView: TrackView?
    private var secondChat: ChatController?
    private var secondSession: Transcript.SessionRef?

    func applicationDidFinishLaunching(_ note: Notification) {
        // Ask for Accessibility once. Without it we can only see the Dock's
        // height, not its width or which display it is on — so the car has to
        // fall back to the middle of the screen.
        DockGeometry.requestAccessibilityIfNeeded()

        let dock = DockGeometry.current()
        let frame = trackFrame(for: dock)

        window = OverlayWindow(contentRect: frame)
        trackView = TrackView(frame: CGRect(origin: .zero, size: frame.size))
        trackView.autoresizingMask = [.width, .height]
        trackView.pitHome = TrackView.preferredPitHome
        window.contentView = trackView
        window.orderFrontRegardless()

        // The Dock moves: hiding, changing size, hopping displays. Re-measure
        // periodically and follow it rather than assuming launch-time geometry.
        dockWatcher = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.followDock() }
        }

        // Listen for state pushed in by Claude Code hooks.
        let watcher = StateWatcher { [weak self] state, message in
            self?.trackView.apply(state, message: message)
            self?.noteStateForAlerts(state)
            SoundEngine.shared.play(for: state)
        }
        watcher.start()
        stateWatcher = watcher

        menuBar = MenuBarController(trackView: trackView) {
            NSApp.terminate(nil)
        }

        // The pit-wall chat: click the car, or use the menu bar item.
        let chatController = ChatController(trackView: trackView)
        chat = chatController
        trackView.onCarClicked = { chatController.toggle() }
        menuBar?.onReply = { chatController.toggle() }

        // Second car wiring. Its session's tab disappears from the primary
        // panel — one conversation, one car.
        chatController.excludedSessionIds = { [weak self] in
            self?.secondSession.map { Set([$0.id]) } ?? []
        }
        menuBar?.onSecondCar = { [weak self] in self?.setSecondCar($0) }
        menuBar?.currentSecondaryId = { [weak self] in self?.secondSession?.id }
        menuBar?.onPitHomeChanged = { [weak self] home in
            self?.secondView?.pitHome = (home == .left) ? .right : .left
        }
        // Right-clicking the car does the same thing as the menu item.
        trackView.onPitHomeToggled = { [weak self] in self?.togglePitHome() }
        menuBar?.onChatSizeChanged = { [weak self] size in
            self?.chat?.setSize(size)
            self?.secondChat?.setSize(size)
        }

        if let saved = UserDefaults.standard.string(forKey: "secondCarSession"),
           let ref = Transcript.recentSessions(limit: 10).first(where: { $0.id == saved }) {
            setSecondCar(ref)
        }

        UNUserNotificationCenter.current().delegate = self

        SoundEngine.shared.warmUp()

        if let existing = StateChannel.read() { trackView.apply(existing) }
        trackView.start()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completion: @escaping () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                NSApp.activate(ignoringOtherApps: true)
                self.chat?.show()
            }
        }
        completion()
    }

    /// The window rectangle: full width of the Dock straight, sitting directly
    /// on top of it.
    private func trackFrame(for dock: DockFrame) -> CGRect {
        let s = dock.straight
        return CGRect(x: s.minX,
                      y: s.y,
                      width: max(s.maxX - s.minX, 1),
                      height: Self.trackHeight)
    }

    /// Persisted from the menu: hide the pet entirely while a full-screen app
    /// covers the display, instead of riding along its bottom edge.
    static var hideInFullScreen: Bool {
        get { UserDefaults.standard.bool(forKey: "hideInFullScreen") }
        set { UserDefaults.standard.set(newValue, forKey: "hideInFullScreen") }
    }
    private var hiddenForFullScreen = false

    // MARK: - box box escalation

    private var waitingSince: Date?
    private var boxBoxFired = false

    /// Track how long the live session has been waiting on the user.
    private func noteStateForAlerts(_ state: PetState) {
        if state == .waiting {
            if waitingSince == nil { waitingSince = Date() }
        } else {
            waitingSince = nil
            boxBoxFired = false
            menuBar?.setAlert(false)
        }
    }

    /// Checked from the existing 1 Hz tick. Fires once per waiting episode.
    private func checkBoxBox() {
        guard BoxBoxAlert.shouldEscalate(waitingSince: waitingSince,
                                         alreadyFired: boxBoxFired,
                                         enabled: BoxBoxAlert.isEnabled) else { return }
        boxBoxFired = true
        menuBar?.setAlert(true)

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }   // degrade to the icon alone
            let content = UNMutableNotificationContent()
            content.title = "Box box — Claude is waiting"
            let session = StateChannel.readSession()
            let title = session.flatMap { StateChannel.readSessionTitle(id: $0.id, cwd: $0.cwd) }
            content.body = (title ?? "A session") + " has been waiting over 2 minutes for your input."
            center.add(UNNotificationRequest(identifier: "boxbox",
                                             content: content, trigger: nil))
        }
    }

    private func followDock() {
        let dock = DockGeometry.current()

        // Optionally disappear while an app is full screen. Ordering out and
        // back loses relative z, so the second window is re-slotted on return.
        let shouldHide = Self.hideInFullScreen && dock.fullScreen
        if shouldHide != hiddenForFullScreen {
            hiddenForFullScreen = shouldHide
            if shouldHide {
                window.orderOut(nil)
                secondWindow?.orderOut(nil)
            } else {
                window.orderFrontRegardless()
                secondWindow?.orderFrontRegardless()
                secondWindow?.order(.below, relativeTo: window.windowNumber)
            }
        }
        if shouldHide { return }

        // The car wears the Dock's size: a small Dock gets a small car. The
        // last measured height sticks while the Dock is hidden or covered, so
        // the car never balloons or vanishes on transient states.
        if let height = dock.tileHeight {
            let scale = TrackView.scale(forDockHeight: height)
            trackView.setScale(scale)
            secondView?.setScale(scale)
        }

        // Without an exact measurement the window spans the whole screen and
        // we cannot know where the Dock actually starts and ends — so keep the
        // car centred, where a centred Dock always is.
        trackView.laneAnchor = dock.measured ? .right : .centre

        writeStatus(dock)
        checkBoxBox()

        let target = trackFrame(for: dock)
        if window.frame != target {
            window.setFrame(target, display: true)
        }

        // The second car shares the strip but yields the foreground.
        if let secondWindow, let secondView {
            secondView.laneAnchor = trackView.laneAnchor
            if secondWindow.frame != target {
                secondWindow.setFrame(target, display: true)
            }
            secondWindow.order(.below, relativeTo: window.windowNumber)
        }
    }

    /// Create, replace or remove the second car.
    /// Move the car to the other end of the Dock, taking the second car and
    /// the menu's checkmarks with it.
    private func togglePitHome() {
        let home: TrackView.PitHome = trackView.pitHome == .left ? .right : .left
        trackView.pitHome = home
        TrackView.preferredPitHome = home
        secondView?.pitHome = (home == .left) ? .right : .left
        menuBar?.rebuild()
    }

    func setSecondCar(_ session: Transcript.SessionRef?) {
        secondChat?.close(); secondChat = nil
        secondView?.stop(); secondView = nil
        secondWindow?.orderOut(nil); secondWindow = nil
        secondSession = session
        UserDefaults.standard.set(session?.id, forKey: "secondCarSession")
        guard let session else { return }

        let w = OverlayWindow(contentRect: window.frame)
        let v = TrackView(frame: CGRect(origin: .zero, size: window.frame.size))
        v.autoresizingMask = [.width, .height]
        v.laneAnchor = trackView.laneAnchor
        // Always the opposite end from the primary, so they never fight over
        // the same box.
        v.pitHome = trackView.pitHome == .left ? .right : .left
        // Right-clicking either car swaps both ends, so they never end up
        // sharing a box.
        v.onPitHomeToggled = { [weak self] in self?.togglePitHome() }
        // A different livery from the primary, so the two are tellable apart.
        if let alt = CarRegistry.all.first(where: { $0.id != trackView.car.id }) { v.car = alt }
        w.contentView = v
        // Slightly ghosted: this is the background car.
        w.alphaValue = 0.92
        w.orderFrontRegardless()
        w.order(.below, relativeTo: window.windowNumber)
        // Start it in the pit box at its own end, so it is immediately
        // obvious where the second car lives.
        v.apply(.waiting)

        let panelChat = ChatController(trackView: v)
        panelChat.fixedSession = session
        v.onCarClicked = { panelChat.toggle() }
        v.showInfo(session.title.isEmpty ? session.project : session.title)
        v.start()

        secondWindow = w
        secondView = v
        secondChat = panelChat
    }

    /// Report what the *running* app can see, for diagnosis.
    ///
    /// The CLI binary and the bundled app have different Accessibility grants,
    /// so `--probe` from a terminal does not tell you what the pet itself is
    /// working with. This does.
    private func writeStatus(_ dock: DockFrame) {
        let status = """
        accessibility: \(DockGeometry.isTrusted)
        measured:      \(dock.measured)
        dockRect:      \(dock.rect)
        screen:        \(dock.screen.frame)
        laneAnchor:    \(dock.measured ? "right" : "centre")
        window:        \(window.frame)
        """
        try? FileManager.default.createDirectory(at: StateChannel.directory,
                                                 withIntermediateDirectories: true)
        try? status.write(to: StateChannel.directory.appendingPathComponent("status"),
                          atomically: true, encoding: .utf8)
    }
}
