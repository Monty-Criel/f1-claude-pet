import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Vertical room above the Dock: the car, plus headroom for tyre smoke
    /// and the radio bubble.
    static let trackHeight: CGFloat = 150

    private var window: OverlayWindow!
    private var trackView: TrackView!
    private var dockWatcher: Timer?
    private var stateWatcher: StateWatcher?
    private var menuBar: MenuBarController?
    private var chat: ChatController?

    func applicationDidFinishLaunching(_ note: Notification) {
        let dock = DockGeometry.current()
        let frame = trackFrame(for: dock)

        window = OverlayWindow(contentRect: frame)
        trackView = TrackView(frame: CGRect(origin: .zero, size: frame.size))
        trackView.autoresizingMask = [.width, .height]
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

        if let existing = StateChannel.read() { trackView.apply(existing) }
        trackView.start()
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

    private func followDock() {
        let target = trackFrame(for: DockGeometry.current())
        guard window.frame != target else { return }
        window.setFrame(target, display: true)
    }
}
