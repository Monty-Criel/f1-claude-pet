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
        let base = viaAccessibility() ?? viaVisibleFrame() ?? hiddenFallback()

        // A full-screen app hides the Dock whatever the auto-hide setting says,
        // but the Dock keeps reporting its normal on-screen rect through the
        // Accessibility API. Taking that at face value leaves the car hovering
        // where the Dock *would* be, well above the bottom of the screen.
        if hasFullScreenWindow(on: base.screen) {
            let f = base.screen.frame
            return DockFrame(rect: CGRect(x: f.minX, y: f.minY, width: f.width, height: 0),
                             screen: base.screen,
                             edge: .bottom,
                             measured: base.measured)
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
            if rect.height >= fullHeight,
               rect.minY <= f.minY + 2,
               f.contains(CGPoint(x: rect.midX, y: rect.midY)) {
                return true
            }
        }
        return false
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

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
        for screen in NSScreen.screens {
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
