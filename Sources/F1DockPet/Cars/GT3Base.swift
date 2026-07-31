import AppKit

/// Colours for a GT3 entry.
struct Livery {
    let primary: NSColor        // main bodywork
    let shade: NSColor          // darker tone for the lower body and shadow
    let accent: NSColor         // stripe / secondary panel
    let trim: NSColor           // small details, wing edge, lights
    let glass: NSColor

    init(primary: NSColor, shade: NSColor, accent: NSColor, trim: NSColor,
         glass: NSColor = NSColor(srgbRed: 0.16, green: 0.20, blue: 0.26, alpha: 1)) {
        self.primary = primary
        self.shade = shade
        self.accent = accent
        self.trim = trim
        self.glass = glass
    }
}

/// A GT3 car.
///
/// These are production-based, so unlike Formula 1 — where the regulations
/// force near-identical silhouettes and the identity really is the livery —
/// each GT3 car genuinely is a different shape. A mid-engined McLaren, a
/// rear-engined 911 and a long-bonnet AMG share almost nothing in profile.
///
/// So every model draws its own body and glasshouse. What lives here is only
/// the genuinely common furniture: arches, wing, splitter, skirts.
protocol GT3Model: Car {
    var livery: Livery { get }
}

extension GT3Model {
    var category: CarCategory { .gt3 }
    var pixelSize: CGSize { CGSize(width: 74, height: 26) }
    var rakeDegrees: CGFloat { 0 }          // GT cars sit flat
    var exhaustPoint: CGPoint { pt(8, 5.4) }
    var engineBayPoint: CGPoint { pt(30, 13) }

    var tyreColor: NSColor { NSColor(srgbRed: 0.09, green: 0.10, blue: 0.12, alpha: 1) }
    /// Neutral magnesium — a bright team colour on the rims reads as glowing
    /// wheels rather than as a wheel.
    var rimColor: NSColor { NSColor(srgbRed: 0.72, green: 0.74, blue: 0.78, alpha: 1) }

    // MARK: - shared furniture

    /// Wheel openings punched into the bodywork.
    ///
    /// On a real car the tyre sits inside a dark arch cut-out with the fender
    /// wrapped over the top of it — checked against reference photos. The
    /// previous approach (body-coloured half-discs anchored beside the wheel)
    /// left lumps of bodywork fore and aft of the tyre.
    ///
    /// Draw order matters: the body panels are already down, this punches the
    /// dark well through them, and the renderer draws the tyre on top — what
    /// survives is a thin dark arch gap around the tyre's upper half.
    func drawArches(_ ctx: CGContext, lift: CGFloat = 1.6) {
        let well = NSColor(srgbRed: 0.04, green: 0.05, blue: 0.06, alpha: 1)
        for wheel in wheels {
            let wellR = wheel.radius + lift
            let fenderR = wellR + 1.0

            // Fender blister wrapped over the opening.
            ctx.setFillColor(livery.primary.cgColor)
            ctx.fillEllipse(in: CGRect(x: wheel.center.x - fenderR,
                                       y: wheel.center.y - fenderR,
                                       width: fenderR * 2, height: fenderR * 2))
            // The dark well the tyre lives in.
            ctx.setFillColor(well.cgColor)
            ctx.fillEllipse(in: CGRect(x: wheel.center.x - wellR,
                                       y: wheel.center.y - wellR,
                                       width: wellR * 2, height: wellR * 2))
            // Arch lip.
            ctx.setStrokeColor(livery.shade.cgColor)
            ctx.setLineWidth(0.8)
            ctx.strokeEllipse(in: CGRect(x: wheel.center.x - wellR,
                                         y: wheel.center.y - wellR,
                                         width: wellR * 2, height: wellR * 2))

            // A fender only wraps the *top* of the tyre — wipe the ring's
            // spill below the rocker line so the lower tyre hangs free, as on
            // the reference photos. Skirts and splitter repaint after this.
            ctx.clear(CGRect(x: wheel.center.x - fenderR, y: 0,
                             width: fenderR * 2, height: 3.8))
        }
    }

    /// Swan-neck rear wing. `deck` is where the mounts meet the bodywork, so
    /// the wing never floats behind the car.
    func drawWing(_ ctx: CGContext, height: CGFloat, deck: CGFloat, span: ClosedRange<CGFloat>) {
        let w = span.upperBound - span.lowerBound
        ctx.fillRect(livery.shade, span.lowerBound + 3, deck, 1.8, height - deck)
        ctx.fillRect(livery.shade, span.upperBound - 5, deck, 1.8, height - deck)
        ctx.fillRect(livery.primary, span.lowerBound, height, w, 2.2)
        ctx.fillRect(livery.trim, span.lowerBound, height + 2.2, w, 0.8)
        ctx.fillRect(livery.shade, span.lowerBound, height - 1.6, 2, 5.4)
    }

    func drawSplitterAndSkirt(_ ctx: CGContext, splitterFrom: CGFloat = 62) {
        ctx.fillRect(livery.shade, splitterFrom, 3.2, 74 - splitterFrom - 1, 1.3)
        ctx.fillRect(livery.trim, splitterFrom + 1, 3.2, 74 - splitterFrom - 3, 0.4)
        ctx.fillRect(livery.shade, 20, 3.9, 34, 0.9)        // side skirt
        ctx.fillRect(livery.shade, 5, 3.6, 9, 1.4)          // diffuser
    }

    func drawTailLight(_ ctx: CGContext, at y: CGFloat = 8) {
        ctx.fillRect(NSColor(srgbRed: 0.85, green: 0.08, blue: 0.06, alpha: 1), 4.2, y, 2.6, 1.8)
    }

    /// Number roundel on the door.
    func drawRoundel(_ ctx: CGContext, at x: CGFloat, y: CGFloat = 7.4) {
        ctx.fillRect(livery.trim, x, y, 5, 3.6)
        ctx.fillRect(livery.shade, x + 2, y + 0.8, 1.2, 2)
    }
}
