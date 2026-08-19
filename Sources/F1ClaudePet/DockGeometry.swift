import AppKit
import ApplicationServices

/// Where the Dock currently is, in Cocoa (bottom-left origin) screen coordinates.
struct DockFrame {
    /// The Dock's tile strip — the visible black/translucent pill.
    let rect: CGRect
    /// The screen the Dock is currently on.
    let screen: NSScreen
    /// Which edge the Dock is docked to.
    let edge: Edge
    /// True when the rect was measured for real; false when we fell back to a guess.
    let measured: Bool
    /// The Dock strip's real height when measured — survives the full-screen
    /// substitution below, so the car can keep its size while the Dock is
    /// covered. `nil` when the geometry was guessed.
    var tileHeight: CGFloat?
    /// True when a full-screen app is covering this display.
    var fullScreen: Bool = false

    enum Edge: String {
        case bottom, left, right
    }

    /// True when the Dock is hidden. An auto-hidden Dock still reports a rect
    /// through the Accessibility API, but that rect has slid off the bottom of
    /// the screen — so following it blindly drags the car off-screen with it.
    var isHidden: Bool {
        rect.maxY <= screen.frame.minY + 2
    }

    /// The line the car drives along: the top surface of the Dock strip, or
    /// the bottom edge of the screen when the Dock is hidden or vertical.
    var straight: (y: CGFloat, minX: CGFloat, maxX: CGFloat) {
        let f = screen.frame

        switch edge {
        case .bottom where !isHidden:
            // Never let the car sit below the screen, whatever the Dock says.
            return (max(rect.maxY, f.minY), rect.minX, rect.maxX)
        case .bottom:
            // Dock hidden: sit on the floor, full width.
            return (f.minY, f.minX, f.maxX)
        case .left, .right:
            let v = screen.visibleFrame
            return (max(v.minY, f.minY), v.minX, v.maxX)
        }
    }
}

enum DockGeometry {

    /// Resolve the Dock's current position. Tries the Accessibility API first
    /// (exact, and survives magnification / autohide / display moves), then
    /// degrades gracefully so the pet still runs without the permission.
    static func current() -> DockFrame {
        var base = viaAccessibility() ?? viaVisibleFrame() ?? hiddenFallback()
        // The strip height only means anything when it was actually measured
        // and the Dock is on screen.
        base.tileHeight = (base.measured && !base.isHidden && base.rect.height > 24)
            ? base.rect.height : nil

        // A full-screen app hides the Dock whatever the auto-hide setting says,
        // but the Dock keeps reporting its normal on-screen rect through the
        // Accessibility API. Taking that at face value leaves the car hovering
        // where the Dock *would* be, well above the bottom of the screen.
        if hasFullScreenWindow(on: base.screen) {
            let f = base.screen.frame
            var frame = DockFrame(rect: CGRect(x: f.minX, y: f.minY, width: f.width, height: 0),
                                  screen: base.screen,
                                  edge: .bottom,
                                  measured: base.measured)
            frame.tileHeight = base.tileHeight   // size survives being covered
            frame.fullScreen = true
            return frame
        }
        return base
    }

    /// True when a window is covering this whole display — i.e. an app is in
    /// full screen, so there is no Dock to sit on.
    private static func hasFullScreenWindow(on screen: NSScreen) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return false }

        let f = screen.frame
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0

        for window in list {
            // Only normal application windows; ignore our own overlay, the
            // Dock, menu bar items and other chrome.
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let owner = window[kCGWindowOwnerName as String] as? String,
                  !owner.contains("F1"),
                  let b = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"]
            else { continue }

            // CoreGraphics reports top-left origin anchored on the primary display.
            let rect = CGRect(x: x, y: primaryHeight - (y + h), width: w, height: h)

            // Full-screen AND tiled Split View windows span the screen's full
            // height *below the notch* — on a notched MacBook they are
            // safeAreaInsets.top shorter than the frame, never the full frame.
            // Ordinary desktop windows are shorter still: they also stop at
            // the Dock reservation. So "full height minus safe area" means
            // there is no Dock on screen to sit on. (A width check would break
            // Split View, where each tile is only half the screen wide.)
            let fullHeight = f.height - screen.safeAreaInsets.top - 8
            guard rect.height >= fullHeight, rect.minY <= f.minY + 2 else { continue }

            // Must genuinely be *this* display's window. A midpoint test is too
            // loose with several monitors — a full-screen app on the next
            // display over would drag the car off the Dock's screen. Require
            // most of the window to actually lie within this screen.
            let overlap = rect.intersection(f)
            let overlapArea = overlap.width * overlap.height
            let windowArea = max(rect.width * rect.height, 1)
            if overlapArea / windowArea > 0.8 { return true }
        }
        return false
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Show the system Accessibility prompt if we don't already have it.
    ///
    /// This is what lets the pet read the Dock's exact rect — which display it
    /// is on, where it starts and ends. Everything still works without it, the
    /// car just keeps to the middle of the screen instead of the Dock's own
    /// right-hand end.
    static func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        // The constant is an imported global var, which Swift 6 treats as
        // shared mutable state; its literal value is stable API.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Open the Accessibility pane, for the menu bar item.
    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Ask the Dock process for the bounds of its item list.
    private static func viaAccessibility() -> DockFrame? {
        guard AXIsProcessTrusted() else { return nil }
        guard let dockApp = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }

        let app = AXUIElementCreateApplication(dockApp.processIdentifier)
        guard let list = firstList(in: app) else { return nil }

        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(list, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(list, kAXSizeAttribute as CFString, &sizeRef) == .success
        else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        guard size.width > 1, size.height > 1 else { return nil }

        // AX reports top-left origin; Cocoa wants bottom-left.
        let rect = flipToCocoa(CGRect(origin: origin, size: size))
        guard let screen = screenContaining(rect) else { return nil }

        return DockFrame(rect: rect, screen: screen, edge: edge(of: rect, on: screen), measured: true)
    }

    /// Walk the Dock's AX tree for the list holding the tiles.
    private static func firstList(in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth < 4 else { return nil }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }

        for child in children {
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleRef)
            if (roleRef as? String) == (kAXListRole as String) { return child }
        }
        for child in children {
            if let found = firstList(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    /// Derive the Dock strip from the gap between `frame` and `visibleFrame`.
    /// Reliable in a real app bundle; returns nil when the gap reads as zero.
    private static func viaVisibleFrame() -> DockFrame? {
        // Check the active display first: with "Displays have separate Spaces"
        // the Dock moves to whichever screen you are working on, and taking
        // the first screen in the list would strand the car on the other one.
        var order = NSScreen.screens
        if let main = NSScreen.main, let index = order.firstIndex(of: main) {
            order.remove(at: index)
            order.insert(main, at: 0)
        }

        for screen in order {
            let f = screen.frame, v = screen.visibleFrame
            let bottomGap = v.minY - f.minY
            if bottomGap > 4 {
                let rect = CGRect(x: f.minX, y: f.minY, width: f.width, height: bottomGap)
                return DockFrame(rect: rect, screen: screen, edge: .bottom, measured: false)
            }
            let leftGap = v.minX - f.minX
            if leftGap > 4 {
                let rect = CGRect(x: f.minX, y: f.minY, width: leftGap, height: f.height)
                return DockFrame(rect: rect, screen: screen, edge: .left, measured: false)
            }
            let rightGap = f.maxX - v.maxX
            if rightGap > 4 {
                let rect = CGRect(x: v.maxX, y: f.minY, width: rightGap, height: f.height)
                return DockFrame(rect: rect, screen: screen, edge: .right, measured: false)
            }
        }
        return nil
    }

    /// Last resort, reached when Accessibility is not granted AND
    /// `visibleFrame` shows no Dock gap on any screen. No gap means the Dock
    /// is not occupying a screen edge right now — hidden, or covered by a
    /// full-screen app — so the honest answer is the bottom of the screen.
    ///
    /// (The old fallback here reconstructed a Dock strip from the Dock's
    /// preferences, which silently assumed the Dock was visible and left the
    /// car hovering at Dock height with nothing under it.)
    private static func hiddenFallback() -> DockFrame {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let f = screen.frame
        return DockFrame(rect: CGRect(x: f.minX, y: f.minY, width: f.width, height: 0),
                         screen: screen, edge: .bottom, measured: false)
    }

    // MARK: - helpers

    /// AX and CoreGraphics use a top-left origin anchored on the primary display.
    private static func flipToCocoa(_ r: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    private static func screenContaining(_ rect: CGRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main
    }

    private static func edge(of rect: CGRect, on screen: NSScreen) -> DockFrame.Edge {
        let f = screen.frame
        if rect.width >= rect.height { return .bottom }
        return rect.midX < f.midX ? .left : .right
    }
}
