import AppKit

/// Claude's palette — the chat panel, radio bubble and app icon all share it,
/// so the pet reads as part of the Claude family rather than a random overlay.
enum Theme {
    /// Anthropic's brand orange (crail).
    static let accent = NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1)
    static let accentBright = NSColor(srgbRed: 0.93, green: 0.56, blue: 0.40, alpha: 1)

    /// Warm near-blacks, like the Claude apps in dark mode.
    static let panelBackground = NSColor(srgbRed: 0.09, green: 0.07, blue: 0.06, alpha: 0.96)
    static let bubbleBackground = NSColor(srgbRed: 0.12, green: 0.09, blue: 0.08, alpha: 1)
}
