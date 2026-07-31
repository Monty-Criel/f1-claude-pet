import AppKit

/// Pirelli compound, worn as the coloured sidewall ring and lettering.
enum TyreCompound: String, CaseIterable {
    case soft, medium, hard, intermediate, wet

    var color: NSColor {
        switch self {
        case .soft:         return NSColor(srgbRed: 0.90, green: 0.12, blue: 0.10, alpha: 1)
        case .medium:       return NSColor(srgbRed: 0.98, green: 0.80, blue: 0.05, alpha: 1)
        case .hard:         return NSColor(srgbRed: 0.92, green: 0.93, blue: 0.95, alpha: 1)
        case .intermediate: return NSColor(srgbRed: 0.15, green: 0.72, blue: 0.25, alpha: 1)
        case .wet:          return NSColor(srgbRed: 0.15, green: 0.45, blue: 0.90, alpha: 1)
        }
    }

    var displayName: String {
        switch self {
        case .soft:         return "Soft — red"
        case .medium:       return "Medium — yellow"
        case .hard:         return "Hard — white"
        case .intermediate: return "Intermediate — green"
        case .wet:          return "Wet — blue"
        }
    }

    /// The fitted set, shared by every car on track. Softs by default.
    static var selected: TyreCompound {
        get {
            UserDefaults.standard.string(forKey: "tyreCompound")
                .flatMap(TyreCompound.init(rawValue:)) ?? .soft
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "tyreCompound") }
    }
}
