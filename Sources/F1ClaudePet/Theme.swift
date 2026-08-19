import AppKit

/// The app's accent colour, picked in the menu bar.
///
/// Defaults to Anthropic's orange so the pet reads as part of the Claude
/// family, but every panel, bubble and spinner reads from here — so changing
/// it re-themes the whole app.
enum ThemeColor: String, CaseIterable {
    case claude, papaya, ferrari, teal, azure, lime, magenta, silver

    var displayName: String {
        switch self {
        case .claude:  return "Claude Orange"
        case .papaya:  return "Papaya"
        case .ferrari: return "Rosso Corsa"
        case .teal:    return "Petronas Teal"
        case .azure:   return "Azure"
        case .lime:    return "Lime"
        case .magenta: return "Magenta"
        case .silver:  return "Silver"
        }
    }

    var color: NSColor {
        switch self {
        case .claude:  return NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1)
        case .papaya:  return NSColor(srgbRed: 1.00, green: 0.52, blue: 0.08, alpha: 1)
        case .ferrari: return NSColor(srgbRed: 0.90, green: 0.16, blue: 0.16, alpha: 1)
        case .teal:    return NSColor(srgbRed: 0.00, green: 0.79, blue: 0.72, alpha: 1)
        case .azure:   return NSColor(srgbRed: 0.25, green: 0.60, blue: 1.00, alpha: 1)
        case .lime:    return NSColor(srgbRed: 0.63, green: 0.89, blue: 0.16, alpha: 1)
        case .magenta: return NSColor(srgbRed: 0.95, green: 0.31, blue: 0.64, alpha: 1)
        case .silver:  return NSColor(srgbRed: 0.76, green: 0.79, blue: 0.83, alpha: 1)
        }
    }

    /// The panel background: a very dark wash of the accent, so the whole
    /// surface shifts with the theme instead of only the highlights.
    var background: NSColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        (color.usingColorSpace(.sRGB) ?? color).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: s * 0.35, brightness: 0.09, alpha: 0.96)
    }

    static var selected: ThemeColor {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "themeColor") else { return .claude }
            return ThemeColor(rawValue: raw) ?? .claude
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "themeColor")
            NotificationCenter.default.post(name: Theme.changed, object: nil)
        }
    }
}

/// Convenience accessors, so nothing else has to know about `ThemeColor`.
enum Theme {
    /// Posted when the accent changes; views repaint on it.
    static let changed = Notification.Name("F1ClaudePetThemeChanged")

    static var accent: NSColor { ThemeColor.selected.color }

    static var accentBright: NSColor {
        accent.blended(withFraction: 0.25, of: .white) ?? accent
    }

    static var panelBackground: NSColor { ThemeColor.selected.background }

    /// Warm near-black for the radio bubble, tinted by the accent.
    static var bubbleBackground: NSColor {
        ThemeColor.selected.background.withAlphaComponent(1)
    }
}
