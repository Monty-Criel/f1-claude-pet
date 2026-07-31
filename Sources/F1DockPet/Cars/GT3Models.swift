import AppKit

// MARK: - Porsche 911 GT3 R

/// The most distinctive profile on the grid: rear-engined, so the roof flows
/// in one unbroken fastback line from the windscreen all the way to the tail,
/// with a short nose, round headlights set high on the front wings, and a
/// visibly heavy rear.
struct Porsche911GT3R: GT3Model {
    let id = "porsche-gt3"
    let displayName = "Porsche 911 GT3 RS"
    /// The classic works scheme: white body, black aero and wheels, with red
    /// as the only other colour. Deliberately monochrome — the 911's shape is
    /// the thing you recognise, so the paint gets out of its way.
    let livery = Livery(
        primary: NSColor(srgbRed: 0.95, green: 0.95, blue: 0.96, alpha: 1),
        shade:   NSColor(srgbRed: 0.09, green: 0.09, blue: 0.10, alpha: 1),
        accent:  NSColor(srgbRed: 0.11, green: 0.11, blue: 0.13, alpha: 1),
        trim:    NSColor(srgbRed: 0.82, green: 0.06, blue: 0.10, alpha: 1)
    )
    // Short overhangs, wide rear track.
    let wheels = [
        Wheel(center: pt(17, 7.0), radius: 7.0, isDriven: true),
        Wheel(center: pt(56, 6.3), radius: 6.3, isDriven: false),
    ]

    func drawChassis(in ctx: CGContext) {
        drawWing(ctx, height: 19, deck: 12.6, span: 3...19)

        // One continuous fastback line — the 911 signature.
        ctx.fill(livery.primary) { p in
            p.move(to: pt(5, 5))
            p.addLine(to: pt(69, 4.6))
            p.addLine(to: pt(71.5, 6.4))        // short, low nose
            p.addCurve(to: pt(58, 11.6), control1: pt(70, 9.6), control2: pt(64, 11.4))
            p.addLine(to: pt(50, 12.2))         // cowl
            p.addCurve(to: pt(38, 18.2), control1: pt(45, 12.6), control2: pt(41, 17))
            p.addLine(to: pt(30, 18.4))         // roof
            p.addCurve(to: pt(12, 12.6), control1: pt(22, 18.2), control2: pt(16, 14.6))
            p.addLine(to: pt(5, 11.8))          // full, heavy tail
            p.closeSubpath()
        }
        ctx.fill(livery.shade) { p in           // rocker
            p.polygon([pt(6, 4.6), pt(68, 4.4), pt(68, 6), pt(6, 6.4)])
        }
        // Glass follows the same sweep.
        ctx.fill(livery.glass) { p in
            p.move(to: pt(30, 17.6))
            p.addLine(to: pt(38.5, 17.4))
            p.addCurve(to: pt(48, 12.6), control1: pt(43, 16.4), control2: pt(46, 13.4))
            p.addLine(to: pt(28, 12.9))
            p.addCurve(to: pt(30, 17.6), control1: pt(28.4, 14.6), control2: pt(29, 16.4))
            p.closeSubpath()
        }
        // Black roof and rear deck sweeping down into the tail.
        ctx.fill(livery.shade) { p in
            p.move(to: pt(12, 12.6))
            p.addCurve(to: pt(30, 18.4), control1: pt(16, 14.6), control2: pt(22, 18.2))
            p.addLine(to: pt(38, 18.2))
            p.addCurve(to: pt(46, 13.6), control1: pt(41, 17), control2: pt(44, 14.6))
            p.addLine(to: pt(44, 12.9))
            p.addCurve(to: pt(30, 16.9), control1: pt(41, 15.6), control2: pt(35, 16.9))
            p.addLine(to: pt(16, 12.2))
            p.closeSubpath()
        }
        // Slim red stripe along the sill — the only colour on the car.
        ctx.fillRect(livery.trim, 22, 6.6, 36, 0.9)
        drawArches(ctx)
        // Round headlight high on the wing — pure 911.
        ctx.setFillColor(livery.trim.cgColor)
        ctx.fillEllipse(in: CGRect(x: 64.5, y: 8.4, width: 3.6, height: 3.6))
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        ctx.fillEllipse(in: CGRect(x: 65.4, y: 9.3, width: 1.6, height: 1.6))
        drawRoundel(ctx, at: 34)
        drawTailLight(ctx, at: 8.6)
        drawSplitterAndSkirt(ctx, splitterFrom: 63)
    }
}

// MARK: - McLaren 720S GT3

/// Mid-engined: cab well forward, an extremely low nose, a teardrop cabin that
/// tapers into a long rear deck, and McLaren's deep side intake ahead of the
/// rear arch.
struct McLaren720SGT3: GT3Model {
    let id = "mclaren-gt3"
    let displayName = "McLaren 720S GT3"
    let livery = Livery(
        primary: NSColor(srgbRed: 1.00, green: 0.47, blue: 0.00, alpha: 1),
        shade:   NSColor(srgbRed: 0.62, green: 0.25, blue: 0.00, alpha: 1),
        accent:  NSColor(srgbRed: 0.05, green: 0.09, blue: 0.13, alpha: 1),
        trim:    NSColor(srgbRed: 0.13, green: 0.72, blue: 0.90, alpha: 1)
    )
    let wheels = [
        Wheel(center: pt(16, 6.8), radius: 6.8, isDriven: true),
        Wheel(center: pt(55, 6.3), radius: 6.3, isDriven: false),
    ]

    func drawChassis(in ctx: CGContext) {
        drawWing(ctx, height: 18.6, deck: 11.8, span: 2...18)

        ctx.fill(livery.primary) { p in
            p.move(to: pt(4, 5))
            p.addLine(to: pt(70, 4.4))
            p.addLine(to: pt(72.5, 5.6))        // very low nose
            p.addCurve(to: pt(60, 9.8), control1: pt(70.5, 7.6), control2: pt(65, 9.4))
            p.addLine(to: pt(52, 11.4))         // long low bonnet
            p.addCurve(to: pt(44, 17.4), control1: pt(49, 12), control2: pt(46, 16))
            p.addLine(to: pt(35, 17.8))         // cab forward
            p.addCurve(to: pt(22, 12.4), control1: pt(29, 17.6), control2: pt(25, 14.4))
            p.addLine(to: pt(10, 11.6))         // long rear deck
            p.addLine(to: pt(4, 10.4))
            p.closeSubpath()
        }
        ctx.fill(livery.shade) { p in
            p.polygon([pt(6, 4.6), pt(68, 4.2), pt(68, 6), pt(6, 6.4)])
        }
        // Teardrop glasshouse.
        ctx.fill(livery.glass) { p in
            p.move(to: pt(35, 17))
            p.addLine(to: pt(43, 16.6))
            p.addCurve(to: pt(49.5, 11.8), control1: pt(46, 15.4), control2: pt(48, 12.6))
            p.addLine(to: pt(27, 12.4))
            p.addCurve(to: pt(35, 17), control1: pt(29, 14.4), control2: pt(32, 16.4))
            p.closeSubpath()
        }
        // Deep side intake feeding the mid-mounted engine.
        ctx.fill(livery.accent) { p in
            p.polygon([pt(23, 7), pt(31, 6.8), pt(29, 11), pt(23, 10.6)])
        }
        ctx.fill(livery.trim) { p in            // intake lip
            p.polygon([pt(23, 10.2), pt(29.4, 10.6), pt(29, 11.4), pt(23, 11)])
        }
        drawArches(ctx)
        ctx.fillRect(livery.trim, 66, 7.2, 4, 1.6)      // slim headlight
        drawRoundel(ctx, at: 36)
        drawTailLight(ctx, at: 8)
        drawSplitterAndSkirt(ctx, splitterFrom: 62)
    }
}

// MARK: - BMW M4 GT3

/// Front-engined and deliberately upright: a notchback with a squared-off
/// tail, flat roof with real pillar angles, and the enormous vertical kidney
/// grille that no other car on the grid has.
struct BMWM4GT3: GT3Model {
    let id = "bmw-gt3"
    let displayName = "BMW M4 GT3"
    let livery = Livery(
        primary: NSColor(srgbRed: 0.93, green: 0.94, blue: 0.96, alpha: 1),
        shade:   NSColor(srgbRed: 0.50, green: 0.53, blue: 0.58, alpha: 1),
        accent:  NSColor(srgbRed: 0.85, green: 0.10, blue: 0.14, alpha: 1),
        trim:    NSColor(srgbRed: 0.02, green: 0.35, blue: 0.70, alpha: 1)
    )
    let wheels = [
        Wheel(center: pt(16, 6.6), radius: 6.6, isDriven: true),
        Wheel(center: pt(55, 6.4), radius: 6.4, isDriven: false),
    ]

    func drawChassis(in ctx: CGContext) {
        drawWing(ctx, height: 18.6, deck: 12, span: 2...18)

        // Squarer than the others: flat bonnet, upright screen, notched boot.
        ctx.fill(livery.primary) { p in
            p.polygon([
                pt(4, 5), pt(70, 4.6),
                pt(72, 7.2),            // tall blunt nose
                pt(71, 11.4),           // upright grille face
                pt(56, 11.8),           // flat bonnet
                pt(49, 12.2),
                pt(43, 18.2),           // steep A-pillar
                pt(29, 18.6),           // flat roof
                pt(23, 12.6),           // steep C-pillar
                pt(10, 12.2),           // notched boot deck
                pt(4, 11),
            ])
        }
        ctx.fill(livery.shade) { p in
            p.polygon([pt(6, 4.6), pt(68, 4.4), pt(68, 6), pt(6, 6.4)])
        }
        ctx.fill(livery.glass) { p in           // upright glasshouse
            p.polygon([pt(29, 18), pt(42, 17.6), pt(47, 12.7), pt(25.5, 13)])
        }
        // M stripes along the flank: blue, dark blue, red.
        ctx.fillRect(livery.trim, 24, 7.2, 30, 0.9)
        ctx.fillRect(NSColor(srgbRed: 0.05, green: 0.15, blue: 0.45, alpha: 1), 24, 8.1, 30, 0.9)
        ctx.fillRect(livery.accent, 24, 9.0, 30, 0.9)
        drawArches(ctx)
        // The kidney grille — tall, vertical, unmistakable.
        ctx.fillRect(livery.shade, 68.4, 6.6, 3.2, 5)
        ctx.fillRect(livery.primary, 69.8, 6.8, 0.5, 4.6)
        ctx.fillRect(livery.trim, 64.5, 9.4, 3.4, 1.6)   // headlight
        drawRoundel(ctx, at: 34)
        drawTailLight(ctx, at: 9)
        drawSplitterAndSkirt(ctx, splitterFrom: 62)
    }
}

// MARK: - Mercedes-AMG GT3

/// The longest bonnet on the grid by a distance, with the cabin pushed right
/// back over the rear axle and a fastback tail. Front face carries the
/// Panamericana vertical-bar grille.
///
/// Livery is a tribute to Verstappen.com Racing's navy and orange, not a
/// reproduction of any specific car.
struct MercedesAMGGT3: GT3Model {
    // One body, several liveries — same car, different paint. Defaults are the
    // Verstappen tribute; other entries are declared in `GT3Grid`.
    var id = "amg-gt3-mv"
    var displayName = "Mercedes-AMG GT3 — Verstappen livery"
    var livery = Livery(
        primary: NSColor(srgbRed: 0.05, green: 0.09, blue: 0.24, alpha: 1),
        shade:   NSColor(srgbRed: 0.02, green: 0.04, blue: 0.13, alpha: 1),
        accent:  NSColor(srgbRed: 1.00, green: 0.40, blue: 0.00, alpha: 1),
        trim:    NSColor(srgbRed: 0.95, green: 0.96, blue: 0.98, alpha: 1)
    )
    // Long wheelbase, cab-rearward.
    let wheels = [
        Wheel(center: pt(15, 6.8), radius: 6.8, isDriven: true),
        Wheel(center: pt(57, 6.4), radius: 6.4, isDriven: false),
    ]

    func drawChassis(in ctx: CGContext) {
        drawWing(ctx, height: 18.2, deck: 11.6, span: 2...17)

        ctx.fill(livery.primary) { p in
            p.move(to: pt(4, 5))
            p.addLine(to: pt(70, 4.6))
            p.addLine(to: pt(72, 6.6))
            p.addCurve(to: pt(62, 11), control1: pt(71, 9), control2: pt(66, 10.8))
            p.addLine(to: pt(44, 12.4))         // very long bonnet
            p.addCurve(to: pt(36, 17.6), control1: pt(41, 12.8), control2: pt(38, 16.2))
            p.addLine(to: pt(26, 18))
            p.addCurve(to: pt(13, 12), control1: pt(20, 17.8), control2: pt(16, 14))
            p.addLine(to: pt(4, 10.6))          // fastback tail
            p.closeSubpath()
        }
        ctx.fill(livery.shade) { p in
            p.polygon([pt(6, 4.6), pt(68, 4.4), pt(68, 6), pt(6, 6.4)])
        }
        ctx.fill(livery.glass) { p in
            p.polygon([pt(26, 17.4), pt(35.5, 17), pt(41.5, 12.6), pt(23.5, 12.4)])
        }
        // Orange flash sweeping the full flank.
        ctx.fill(livery.accent) { p in
            p.polygon([pt(18, 6.9), pt(60, 6.6), pt(60, 9.2), pt(18, 9.8)])
        }
        drawArches(ctx)
        // Panamericana grille: vertical bars.
        ctx.fillRect(livery.shade, 68.6, 6.4, 3, 4.4)
        for i in 0..<3 {
            ctx.fillRect(livery.trim, 69 + CGFloat(i) * 0.9, 6.6, 0.4, 4)
        }
        ctx.fillRect(livery.trim, 64, 9, 3.4, 1.5)      // headlight
        drawRoundel(ctx, at: 30)
        drawTailLight(ctx, at: 8.4)
        drawSplitterAndSkirt(ctx, splitterFrom: 62)
    }
}

// MARK: - Aston Martin Vantage GT3

/// Front-engined with a long bonnet and a short, high, ducktailed rear —
/// muscular haunches and Aston's big oval grille aperture up front.
struct AstonVantageGT3: GT3Model {
    let id = "aston-gt3"
    let displayName = "Aston Martin Vantage GT3"
    let livery = Livery(
        primary: NSColor(srgbRed: 0.02, green: 0.25, blue: 0.20, alpha: 1),
        shade:   NSColor(srgbRed: 0.01, green: 0.13, blue: 0.11, alpha: 1),
        accent:  NSColor(srgbRed: 0.60, green: 0.85, blue: 0.10, alpha: 1),
        trim:    NSColor(srgbRed: 0.88, green: 0.92, blue: 0.90, alpha: 1)
    )
    let wheels = [
        Wheel(center: pt(16, 6.8), radius: 6.8, isDriven: true),
        Wheel(center: pt(56, 6.4), radius: 6.4, isDriven: false),
    ]

    func drawChassis(in ctx: CGContext) {
        drawWing(ctx, height: 18.4, deck: 12.4, span: 2...18)

        ctx.fill(livery.primary) { p in
            p.move(to: pt(4, 5))
            p.addLine(to: pt(70, 4.6))
            p.addLine(to: pt(72, 7))
            p.addCurve(to: pt(60, 10.8), control1: pt(71.5, 9.4), control2: pt(65, 10.6))
            p.addLine(to: pt(47, 12.2))         // long bonnet
            p.addCurve(to: pt(39, 17.8), control1: pt(44, 12.6), control2: pt(41, 16.4))
            p.addLine(to: pt(28, 18.2))
            p.addCurve(to: pt(19, 13.6), control1: pt(23, 18), control2: pt(20.5, 15.6))
            p.addLine(to: pt(11, 13))
            p.addLine(to: pt(4, 11))            // short high ducktail
            p.closeSubpath()
        }
        ctx.fill(livery.shade) { p in
            p.polygon([pt(6, 4.6), pt(68, 4.4), pt(68, 6), pt(6, 6.4)])
        }
        ctx.fill(livery.glass) { p in
            p.polygon([pt(28, 17.6), pt(38, 17.2), pt(44.5, 12.4), pt(25.5, 13.6)])
        }
        ctx.fill(livery.accent) { p in          // lime flank flash
            p.polygon([pt(22, 7.1), pt(58, 6.7), pt(58, 9.4), pt(22, 10)])
        }
        drawArches(ctx)
        // Aston's big oval grille aperture.
        ctx.fill(livery.shade) { p in
            p.polygon([pt(68, 6.6), pt(72, 7.2), pt(71.6, 10), pt(68, 9.6)])
        }
        ctx.fillRect(livery.trim, 64, 9.2, 3.4, 1.5)    // headlight
        drawRoundel(ctx, at: 32)
        drawTailLight(ctx, at: 9)
        drawSplitterAndSkirt(ctx, splitterFrom: 62)
    }
}

// MARK: - grid

enum GT3Grid {

    /// AMG ONE-style colours on the GT3 body: silver over graphite with
    /// Petronas teal accents, teal wing edge, black lower half.
    static let amgOne = MercedesAMGGT3(
        id: "amg-gt3-one",
        displayName: "Mercedes-AMG GT3 — AMG ONE livery",
        livery: Livery(
            primary: NSColor(srgbRed: 0.76, green: 0.78, blue: 0.81, alpha: 1),
            shade:   NSColor(srgbRed: 0.14, green: 0.15, blue: 0.17, alpha: 1),
            accent:  NSColor(srgbRed: 0.00, green: 0.82, blue: 0.75, alpha: 1),
            trim:    NSColor(srgbRed: 0.00, green: 0.65, blue: 0.60, alpha: 1)
        )
    )

    static let all: [any Car] = [
        AstonVantageGT3(),
        MercedesAMGGT3(),
        amgOne,
        McLaren720SGT3(),
        BMWM4GT3(),
        Porsche911GT3R(),
    ]
}
