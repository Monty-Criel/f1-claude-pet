import AppKit

/// Oracle Red Bull Racing RB22, drawn against the launch photo: matte navy
/// over everything, ORACLE in white across the sidepod, the Red Bull script
/// and bull on the flank, yellow nose tip, red accents on the wings.
///
/// Proportions are deliberately long and low — roughly 3.5:1 — which is what
/// makes it read as an F1 car rather than a go-kart. The front wheel sits well
/// back so the nose and front wing still have room ahead of it.
///
/// Drawn for the fine raster (detail ≥ 2): half-point features here become
/// whole pixels on screen, which is what makes the lettering readable.
struct RB22: Car {
    let id = "rb22"
    let displayName = "Red Bull RB22 (2026)"
    let category = CarCategory.formula1

    // 72 x 20 native grid: long and low, with headroom for the raked tail.
    let pixelSize = CGSize(width: 72, height: 20)

    /// Light stagger — fatter rears, as they look on track.
    let wheels = [
        Wheel(center: pt(16, 5.9), radius: 5.9, isDriven: true),
        Wheel(center: pt(54, 5.2), radius: 5.2, isDriven: false),
    ]

    /// Just enough tail-up rake to give it some attitude.
    let rakeDegrees: CGFloat = 3

    /// Tailpipe exit, just under the rear wing.
    let exhaustPoint = pt(6.5, 7.6)

    // MARK: - palette, matched to the matte launch car

    private let shadow = NSColor(srgbRed: 0.02, green: 0.03, blue: 0.09, alpha: 1)
    private let navy   = NSColor(srgbRed: 0.05, green: 0.07, blue: 0.17, alpha: 1)
    private let panel  = NSColor(srgbRed: 0.08, green: 0.12, blue: 0.28, alpha: 1)
    private let steel  = NSColor(srgbRed: 0.24, green: 0.32, blue: 0.50, alpha: 1)
    private let yellow = NSColor(srgbRed: 1.00, green: 0.82, blue: 0.00, alpha: 1)
    private let red    = NSColor(srgbRed: 0.85, green: 0.05, blue: 0.10, alpha: 1)
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
        drawBranding(ctx)
        drawBroadcastKit(ctx)
    }

    // MARK: - parts

    private func drawRearWing(_ ctx: CGContext) {
        ctx.fillRect(shadow, 10, 8.6, 1.8, 5.4)   // swan-neck pylon
        ctx.fillRect(navy,   3,  10.8, 8, 1.2)    // beam wing
        ctx.fillRect(shadow, 3,  10.8, 8, 0.4)    // beam wing shadow
        ctx.fillRect(navy,   1,  13.4, 13, 1.8)   // main plane
        ctx.fillRect(red,    1,  15.2, 13, 0.5)   // red top edge
        ctx.fillRect(shadow, 0.4, 11, 2, 5.4)     // endplate
        ctx.fillRect(red,    0.4, 14.6, 2, 0.9)   // endplate flash
        // Sponsor tick on the main plane.
        ctx.fillRect(white, 4.5, 13.9, 1.6, 0.8)
        ctx.fillRect(white, 6.7, 13.9, 1.6, 0.8)
        ctx.fillRect(white, 8.9, 13.9, 1.6, 0.8)
    }

    private func drawExhaust(_ ctx: CGContext) {
        ctx.fillRect(shadow, 6, 6.9, 6, 1.6)      // pipe
        ctx.fillRect(steel,  5.6, 7.2, 0.9, 1)    // hot exit
        ctx.fillRect(shadow, 7, 4.4, 6, 1.6)      // diffuser
        ctx.fillRect(panel,  7, 5.4, 6, 0.5)      // strake highlight
    }

    private func drawEngineCover(_ ctx: CGContext) {
        // Shark fin sweeping from the airbox back down to the wing pylon.
        ctx.fill(navy) { p in
            p.move(to: pt(10, 8.2))
            p.addLine(to: pt(10, 9.6))
            p.addCurve(to: pt(26, 13.4), control1: pt(17, 10.6), control2: pt(22, 12.8))
            p.addLine(to: pt(32, 13.4))
            p.addLine(to: pt(32, 8.2))
            p.closeSubpath()
        }
        // Cooling louvres along the spine.
        ctx.fillRect(shadow, 14, 9.6, 5, 0.5)
        ctx.fillRect(shadow, 20, 11, 4, 0.5)

        // Airbox intake above the driver's head.
        ctx.fill(shadow) { p in
            p.polygon([pt(26.5, 13.6), pt(32.5, 13.6), pt(32.5, 11), pt(26.5, 11.8)])
        }
        // The bull-and-sun mark where the launch car wears it.
        ctx.fillRect(red, 27.2, 12.6, 1.6, 1.0)
        ctx.fillRect(yellow, 29.0, 12.8, 0.8, 0.8)
    }

    private func drawFloorAndTub(_ ctx: CGContext) {
        ctx.fillRect(shadow, 11, 2.8, 46, 1.5)    // floor edge
        ctx.fill(navy) { p in
            p.polygon([pt(13, 4), pt(48, 4), pt(48, 8.2), pt(42, 9.6),
                       pt(32, 9.8), pt(22, 9.2), pt(13, 8.4)])
        }
        ctx.fillRect(shadow, 13, 4, 35, 0.8)      // underside shadow
        // Red floor tick at the front, off the launch car.
        ctx.fillRect(red, 44, 3.2, 3.5, 0.6)

        // Underfloor skirt dropping between the wheels to front-wing height,
        // so the floor actually reads at Dock size: skirt, titanium skid
        // line along its bottom, and strakes hanging toward the track.
        ctx.fill(shadow) { p in
            p.polygon([pt(23, 2.8), pt(48, 2.8), pt(48, 1.6),
                       pt(44, 1.3), pt(26, 1.3), pt(23, 1.8)])
        }
        ctx.fillRect(steel, 26, 1.3, 16, 0.35)    // titanium skid line
        ctx.fillRect(red,   36, 1.9, 5, 0.5)      // edge-wing flash
        ctx.fillRect(shadow, 43.5, 0.9, 0.7, 1.0) // strakes
        ctx.fillRect(shadow, 45.5, 0.9, 0.7, 1.0)
        ctx.fillRect(shadow, 47.3, 0.9, 0.7, 1.0)
    }

    private func drawSidepod(_ ctx: CGContext) {
        ctx.fill(panel) { p in
            p.polygon([pt(28, 4.4), pt(48, 4.4), pt(48, 8), pt(43, 9),
                       pt(31, 9), pt(28, 7.6)])
        }
        // Undercut highlight where the sidepod tucks in.
        ctx.fill(steel) { p in
            p.polygon([pt(30, 5.0), pt(46, 5.0), pt(46, 5.7), pt(30, 5.7)])
        }
        ctx.fillRect(shadow, 46, 5.2, 2.2, 2.8)   // inlet mouth
    }

    private func drawNose(_ ctx: CGContext) {
        ctx.fill(navy) { p in
            p.polygon([pt(46, 8), pt(58, 6.4), pt(67, 4.8),
                       pt(67, 2.8), pt(58, 4), pt(46, 4.2)])
        }
        // Yellow tip cap, tighter than before — the launch car only dips the
        // very end of the nose.
        ctx.fill(yellow) { p in
            p.polygon([pt(64, 5.3), pt(67, 4.8), pt(67, 2.8), pt(64, 3.2)])
        }
        ctx.fillRect(shadow, 50, 3.8, 10, 0.5)    // cape
    }

    private func drawCockpit(_ ctx: CGContext) {
        ctx.fillRect(shadow, 33, 9.2, 9, 1.2)     // cockpit opening
        // Helmet, kept low-contrast.
        ctx.fillRect(shadow, 35.5, 10.2, 3, 1.2)
        ctx.fillRect(white,  35.7, 10.6, 2.4, 0.5)
        // Halo hoop.
        ctx.stroke(shadow, width: 1.1) { p in
            p.move(to: pt(32.5, 10))
            p.addCurve(to: pt(44, 8.8), control1: pt(35, 12.8), control2: pt(42, 12))
        }
        ctx.stroke(shadow, width: 0.9) { p in     // front strut
            p.move(to: pt(43.2, 10.8))
            p.addLine(to: pt(44.4, 8.2))
        }
    }

    private func drawFrontWing(_ ctx: CGContext) {
        ctx.fillRect(shadow, 60, 0.8, 12, 1.3)    // main plane
        ctx.fillRect(white,  60, 0.8, 12, 0.45)   // leading-edge highlight
        ctx.fillRect(navy,   60.5, 2.2, 9, 0.9)   // upper flap
        ctx.fillRect(shadow, 70.3, 0.4, 1.7, 4.4) // endplate
        ctx.fillRect(red,    70.3, 2.6, 1.7, 1.0) // red endplate patch
    }

    /// Team-colour identity instead of sponsor lettering: one rising yellow
    /// flash on the sidepod — a single band can't read as a flag — and the
    /// Red Bull mark proper on the engine cover: yellow sun disc, red bull.
    private func drawBranding(_ ctx: CGContext) {
        ctx.fill(yellow) { p in
            p.polygon([pt(38, 5.6), pt(46, 6.4), pt(46, 5.8), pt(38, 5.1)])
        }
        // Small sun disc with a compact bull over it — quiet, like the
        // matte launch car, not a cartoon.
        ctx.setFillColor(yellow.cgColor)
        ctx.fillEllipse(in: CGRect(x: 17.2, y: 8.6, width: 2.6, height: 2.6))
        ctx.fillRect(red, 17.7, 9.2, 1.6, 0.9)    // body
        ctx.fillRect(red, 19.3, 9.6, 0.6, 0.7)    // head and horn, raised
    }

    /// T-cam, race number, silver halo edge, door mirror.
    private func drawBroadcastKit(_ ctx: CGContext) {
        let silver = NSColor(srgbRed: 0.72, green: 0.76, blue: 0.82, alpha: 1)
        ctx.fillRect(NSColor(white: 0.08, alpha: 1), 28.2, 13.8, 3.2, 1.2)
        ctx.fillRect(red, 31.4, 13.9, 0.9, 1.0)
        // Verstappen's number 1 on the nose.
        ctx.fillRect(white, 56.6, 4.6, 0.9, 2.4)
        ctx.fillRect(white, 55.9, 6.3, 0.7, 0.7)
        // Silver edge on the halo hoop.
        ctx.stroke(silver, width: 0.5) { p in
            p.move(to: pt(32.6, 10.4))
            p.addCurve(to: pt(43.8, 9.2), control1: pt(35, 13.1), control2: pt(42, 12.3))
        }
        // Door mirror.
        ctx.fillRect(shadow, 43.6, 10.6, 1.6, 0.9)
        ctx.fillRect(white,  43.8, 10.8, 1.0, 0.5)
    }
}
