import AppKit

/// Oracle Red Bull Racing RB22 — the 2026 Red Bull Ford Powertrains car.
///
/// Livery cues taken from the Detroit launch: gloss racing blue as a throwback
/// to the 2005 debut car, a lot more Ford blue than previous seasons, white
/// accenting, and yellow flashes on the nose and airbox with the bull in red.
///
/// Proportions are deliberately long and low — roughly 3.5:1 — which is what
/// makes it read as an F1 car rather than a go-kart. The front wheel sits well
/// back so the nose and front wing still have room ahead of it.
struct RB22: Car {
    let id = "rb22"
    let displayName = "Red Bull RB22 (2026)"
    let category = CarCategory.formula1

    // 72 x 20 native grid: long and low, with headroom for the raked tail.
    let pixelSize = CGSize(width: 72, height: 20)

    /// Light stagger — fatter rears, as they look on track. Enough to notice,
    /// not enough to turn it into a hot rod.
    let wheels = [
        Wheel(center: pt(16, 5.9), radius: 5.9, isDriven: true),
        Wheel(center: pt(54, 5.2), radius: 5.2, isDriven: false),
    ]

    /// Just enough tail-up rake to give it some attitude.
    let rakeDegrees: CGFloat = 3

    /// Tailpipe exit, just under the rear wing.
    let exhaustPoint = pt(6.5, 7.6)

    // MARK: - palette

    private let navy   = NSColor(srgbRed: 0.04, green: 0.09, blue: 0.28, alpha: 1)
    private let blue   = NSColor(srgbRed: 0.07, green: 0.20, blue: 0.55, alpha: 1)
    private let ford   = NSColor(srgbRed: 0.11, green: 0.34, blue: 0.72, alpha: 1)
    private let sky    = NSColor(srgbRed: 0.20, green: 0.52, blue: 0.90, alpha: 1)
    private let yellow = NSColor(srgbRed: 1.00, green: 0.82, blue: 0.00, alpha: 1)
    private let red    = NSColor(srgbRed: 0.84, green: 0.00, blue: 0.11, alpha: 1)
    private let white  = NSColor(srgbRed: 0.95, green: 0.96, blue: 0.98, alpha: 1)

    func drawChassis(in ctx: CGContext) {
        drawRearWing(ctx)
        drawExhaust(ctx)
        drawEngineCover(ctx)
        drawFloorAndTub(ctx)
        drawSidepod(ctx)
        drawNose(ctx)
        drawCockpit(ctx)
        drawFrontWing(ctx)
    }

    // MARK: - parts

    private func drawRearWing(_ ctx: CGContext) {
        ctx.fillRect(navy,   10, 8.6, 1.8, 5.4)   // swan-neck pylon
        ctx.fillRect(blue,   3,  10.8, 8, 1.2)    // beam wing
        ctx.fillRect(navy,   3,  10.8, 8, 0.4)    // beam wing shadow
        ctx.fillRect(blue,   1,  13.4, 13, 1.8)   // main plane
        ctx.fillRect(yellow, 1,  15.2, 13, 0.9)   // top edge flash
        ctx.fillRect(navy,   0.4, 11, 2, 5.4)     // endplate
        ctx.fillRect(ford,   0.4, 13.4, 2, 1.8)   // endplate accent
    }

    private func drawExhaust(_ ctx: CGContext) {
        // Tailpipe poking out under the rear wing, plus the diffuser below it.
        ctx.fillRect(navy,  6, 6.9, 6, 1.6)       // pipe
        ctx.fillRect(sky,   5.6, 7.2, 0.9, 1)     // hot exit
        ctx.fillRect(navy,  7, 4.4, 6, 1.6)       // diffuser
        ctx.fillRect(ford,  7, 5.4, 6, 0.5)       // diffuser strake highlight
    }

    private func drawEngineCover(_ ctx: CGContext) {
        // Shark fin sweeping from the airbox back down to the wing pylon.
        ctx.fill(blue) { p in
            p.move(to: pt(10, 8.2))
            p.addLine(to: pt(10, 9.6))
            p.addCurve(to: pt(26, 13.4), control1: pt(17, 10.6), control2: pt(22, 12.8))
            p.addLine(to: pt(32, 13.4))
            p.addLine(to: pt(32, 8.2))
            p.closeSubpath()
        }
        // Cooling louvres along the spine.
        ctx.fillRect(navy, 14, 9.6, 5, 0.5)
        ctx.fillRect(navy, 20, 11, 4, 0.5)

        // Airbox intake above the driver's head.
        ctx.fill(navy) { p in
            p.polygon([pt(26.5, 13.6), pt(32.5, 13.6), pt(32.5, 11), pt(26.5, 11.8)])
        }
        ctx.fillRect(yellow, 26.5, 12.8, 6, 0.9)  // yellow flash on the airbox
    }

    private func drawFloorAndTub(_ ctx: CGContext) {
        // Floor edge running the length of the car.
        ctx.fillRect(navy, 11, 2.8, 46, 1.5)
        // Main tub, tapering down towards the nose.
        ctx.fill(blue) { p in
            p.polygon([pt(13, 4), pt(48, 4), pt(48, 8.2), pt(42, 9.6),
                       pt(32, 9.8), pt(22, 9.2), pt(13, 8.4)])
        }
        // Shadow along the underside for a bit of depth.
        ctx.fillRect(navy, 13, 4, 35, 0.8)
    }

    private func drawSidepod(_ ctx: CGContext) {
        ctx.fill(ford) { p in
            p.polygon([pt(28, 4.4), pt(48, 4.4), pt(48, 8), pt(43, 9),
                       pt(31, 9), pt(28, 7.6)])
        }
        // Undercut highlight where the sidepod tucks in.
        ctx.fill(sky) { p in
            p.polygon([pt(30, 5.2), pt(46, 5.2), pt(46, 6.4), pt(30, 6.4)])
        }
        ctx.fillRect(navy, 46, 5.2, 2.2, 2.8)     // inlet mouth
        ctx.fillRect(red, 34, 5.9, 3.6, 2.1)      // bull mark
        ctx.fillRect(yellow, 37.6, 5.9, 1.6, 2.1)
        ctx.fillRect(white, 28, 4.4, 20, 0.6)     // accent stripe along the floor
    }

    private func drawNose(_ ctx: CGContext) {
        // Long, low nose reaching well past the front wheel to the wing.
        ctx.fill(blue) { p in
            p.polygon([pt(46, 8), pt(58, 6.4), pt(67, 4.8),
                       pt(67, 2.8), pt(58, 4), pt(46, 4.2)])
        }
        ctx.fill(yellow) { p in
            p.polygon([pt(62, 5.5), pt(67, 4.8), pt(67, 2.8), pt(62, 3.4)])
        }
        // Cape under the nose.
        ctx.fillRect(navy, 50, 3.8, 10, 0.5)
    }

    private func drawCockpit(_ ctx: CGContext) {
        ctx.fillRect(navy, 33, 9.2, 9, 1.2)       // cockpit opening
        // Suggestion of a helmet, kept low-contrast so it doesn't fight the
        // bull mark on the sidepod.
        ctx.fillRect(navy,  35.5, 10.2, 3, 1.2)
        ctx.fillRect(white, 35.7, 10.6, 2.4, 0.5)
        // Halo hoop.
        ctx.stroke(navy, width: 1.1) { p in
            p.move(to: pt(32.5, 10))
            p.addCurve(to: pt(44, 8.8), control1: pt(35, 12.8), control2: pt(42, 12))
        }
        ctx.stroke(navy, width: 0.9) { p in       // front strut
            p.move(to: pt(43.2, 10.8))
            p.addLine(to: pt(44.4, 8.2))
        }
    }

    private func drawFrontWing(_ ctx: CGContext) {
        ctx.fillRect(navy,  60, 0.8, 12, 1.3)     // main plane
        ctx.fillRect(white, 60, 0.8, 12, 0.45)    // leading-edge highlight
        ctx.fillRect(blue,  60.5, 2.2, 9, 0.9)    // upper flap
        ctx.fillRect(navy,  70.3, 0.4, 1.7, 4.4)  // endplate
        ctx.fillRect(ford,  70.3, 2, 1.7, 1.6)    // endplate accent
    }
}
