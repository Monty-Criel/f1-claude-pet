import AppKit

/// A click-through, chrome-free window that floats just above the Dock.
///
/// Window levels on macOS: the Dock sits at 20, the menu bar at 24, pop-up
/// menus at 101. Sitting at 21 puts the car on top of the Dock while still
/// letting menus and alerts draw over it, so the pet never blocks real UI.
final class OverlayWindow: NSWindow {

    static let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
    static let petLevel = NSWindow.Level(rawValue: dockLevel + 1)

    init(contentRect: CGRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)

        level = Self.petLevel
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true          // never steals a click from the Dock
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = false

        // Follow the user across Spaces and sit alongside full-screen apps
        // instead of being hidden by them.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        // Excluded from screenshots would be nice, but the pet *should* show up
        // in screen recordings — that is half the fun.
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
