import AppKit

/// Scuderia Ferrari SF-26 — the 2026 car.
///
/// Written as the second model deliberately, to check `Car` actually
/// generalises: this file defines a palette, some paths, wheel positions and a
/// rake value, and nothing in the renderer, the physics or the smoke system
/// needed to change to accommodate it.
///
/// Visually the opposite of the RB22 on purpose — rosso corsa, less rake, and a
/// higher, squarer airbox — so it is obvious at Dock size which one is running.
struct SF26: Car {
    let id = "sf26"
    let displayName = "Ferrari SF-26 (2026)"
    let category = CarCategory.formula1

    let pixelSize = CGSize(width: 72, height: 20)

    let wheels = [
        Wheel(center: pt(16, 5.9), radius: 5.9, isDriven: true),
        Wheel(center: pt(54, 5.2), radius: 5.2, isDriven: false),
    ]

    /// Ferrari traditionally runs a flatter platform than Red Bull.
    let rakeDegrees: CGFloat = 1.5

    let exhaustPoint = pt(6.5, 7.4)

    // MARK: - palette

    private let rosso  = NSColor(srgbRed: 0.83, green: 0.05, blue: 0.09, alpha: 1)
    private let deep   = NSColor(srgbRed: 0.55, green: 0.02, blue: 0.05, alpha: 1)
    private let bright = NSColor(srgbRed: 0.95, green: 0.20, blue: 0.16, alpha: 1)
    private let black  = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.12, alpha: 1)
    private let yellow = NSColor(srgbRed: 1.00, green: 0.85, blue: 0.10, alpha: 1)
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
        drawBroadcastKit(ctx)
    }

    /// Broadcast kit: T-cam, Leclerc's 16, silver halo edge, mirror.
    private func drawBroadcastKit(_ ctx: CGContext) {
        let silver = NSColor(srgbRed: 0.72, green: 0.76, blue: 0.82, alpha: 1)
        ctx.fillRect(NSColor(white: 0.08, alpha: 1), 28.2, 14.1, 3.2, 1.2)
        ctx.fillRect(bright, 31.4, 14.2, 0.9, 1.0)
        // 16 on the nose, abstracted to two white bars.
        ctx.fillRect(white, 55.6, 4.7, 0.8, 2.3)
        ctx.fillRect(white, 57.0, 4.7, 1.1, 2.3)
        ctx.fillRect(black, 57.3, 5.4, 0.5, 0.9)
        ctx.stroke(silver, width: 0.5) { p in
            p.move(to: pt(32.6, 10.4))
            p.addCurve(to: pt(43.8, 9.2), control1: pt(35, 13.1), control2: pt(42, 12.3))
        }
        ctx.fillRect(black, 43.6, 10.6, 1.6, 0.9)
        ctx.fillRect(white, 43.8, 10.8, 1.0, 0.5)
    }

    // MARK: - parts

    private func drawRearWing(_ ctx: CGContext) {
        ctx.fillRect(deep,   10, 8.6, 1.8, 5.4)   // pylon
        ctx.fillRect(rosso,  3,  10.8, 8, 1.2)    // beam wing
        ctx.fillRect(rosso,  1,  13.4, 13, 1.8)   // main plane
        ctx.fillRect(white,  1,  15.2, 13, 0.9)   // top edge
        ctx.fillRect(deep,   0.4, 11, 2, 5.4)     // endplate
        ctx.fillRect(yellow, 0.4, 13.4, 2, 1.4)   // Scuderia yellow
    }

    private func drawExhaust(_ ctx: CGContext) {
        ctx.fillRect(black,  6, 6.7, 6, 1.6)
        ctx.fillRect(bright, 5.6, 7, 0.9, 1)
        ctx.fillRect(deep,   7, 4.4, 6, 1.6)      // diffuser
    }

    private func drawEngineCover(_ ctx: CGContext) {
        ctx.fill(rosso) { p in
            p.move(to: pt(10, 8.2))
            p.addLine(to: pt(10, 9.6))
            p.addCurve(to: pt(26, 13.6), control1: pt(17, 10.4), control2: pt(22, 13))
            p.addLine(to: pt(32, 13.6))
            p.addLine(to: pt(32, 8.2))
            p.closeSubpath()
        }
        ctx.fillRect(deep, 15, 9.8, 5, 0.5)       // louvres
        ctx.fillRect(deep, 21, 11.2, 4, 0.5)

        // Prancing-horse shield on the engine cover flank.
        ctx.fillRect(yellow, 17.4, 8.9, 1.9, 2.0)
        ctx.fillRect(black, 18.0, 9.3, 0.8, 1.2)

        // Squarer, taller airbox than the Red Bull.
        ctx.fill(black) { p in
            p.polygon([pt(26, 13.9), pt(32.5, 13.9), pt(32.5, 11), pt(26, 11.6)])
        }
        ctx.fillRect(yellow, 26, 13.1, 6.5, 0.8)
    }

    private func drawFloorAndTub(_ ctx: CGContext) {
        ctx.fillRect(black, 11, 2.8, 46, 1.4)
        ctx.fill(rosso) { p in
            p.polygon([pt(13, 4), pt(48, 4), pt(48, 8.2), pt(42, 9.6),
                       pt(32, 9.8), pt(22, 9.2), pt(13, 8.4)])
        }
        ctx.fillRect(deep, 13, 4, 35, 0.8)        // underside shadow

        // Underfloor skirt dropping between the wheels to front-wing height:
        // skirt, skid line along its bottom, strakes hanging toward the track.
        ctx.fill(black) { p in
            p.polygon([pt(23, 2.8), pt(48, 2.8), pt(48, 1.6),
                       pt(44, 1.3), pt(26, 1.3), pt(23, 1.8)])
        }
        ctx.fillRect(bright, 26, 1.3, 16, 0.35)
        ctx.fillRect(yellow, 36, 1.9, 5, 0.5)
        ctx.fillRect(black,  43.5, 0.9, 0.7, 1.0)
        ctx.fillRect(black,  45.5, 0.9, 0.7, 1.0)
        ctx.fillRect(black,  47.3, 0.9, 0.7, 1.0)
    }

    private func drawSidepod(_ ctx: CGContext) {
        ctx.fill(rosso) { p in
            p.polygon([pt(28, 4.4), pt(48, 4.4), pt(48, 8), pt(43, 9),
                       pt(31, 9), pt(28, 7.6)])
        }
        ctx.fill(bright) { p in                   // undercut highlight
            p.polygon([pt(30, 5.2), pt(46, 5.2), pt(46, 6.2), pt(30, 6.2)])
        }
        ctx.fillRect(black, 46, 5.2, 2.2, 2.8)    // inlet
        // Prancing-horse patch: yellow shield with a dark mark.
        ctx.fillRect(yellow, 34, 5.9, 3.6, 2.1)
        ctx.fillRect(black,  35.2, 6.3, 1.2, 1.4)
        ctx.fillRect(white, 28, 4.4, 20, 0.5)
    }

    private func drawNose(_ ctx: CGContext) {
        ctx.fill(rosso) { p in
            p.polygon([pt(46, 8), pt(58, 6.4), pt(67, 4.8),
                       pt(67, 2.8), pt(58, 4), pt(46, 4.2)])
        }
        ctx.fill(white) { p in                    // white nose tip
            p.polygon([pt(63, 5.2), pt(67, 4.8), pt(67, 2.8), pt(63, 3.3)])
        }
        ctx.fillRect(deep, 50, 3.8, 10, 0.5)      // cape
    }

    private func drawCockpit(_ ctx: CGContext) {
        ctx.fillRect(black, 33, 9.2, 9, 1.2)
        ctx.fillRect(black, 35.5, 10.2, 3, 1.2)   // helmet
        ctx.fillRect(white, 35.7, 10.6, 2.4, 0.5) // visor
        ctx.stroke(black, width: 1.1) { p in      // halo
            p.move(to: pt(32.5, 10))
            p.addCurve(to: pt(44, 8.8), control1: pt(35, 12.8), control2: pt(42, 12))
        }
        ctx.stroke(black, width: 0.9) { p in
            p.move(to: pt(43.2, 10.8))
            p.addLine(to: pt(44.4, 8.2))
        }
    }

    private func drawFrontWing(_ ctx: CGContext) {
        ctx.fillRect(black,  60, 0.8, 12, 1.3)
        ctx.fillRect(white,  60, 0.8, 12, 0.45)
        ctx.fillRect(rosso,  60.5, 2.2, 9, 0.9)
        ctx.fillRect(deep,   70.3, 0.4, 1.7, 4.4)
        ctx.fillRect(yellow, 70.3, 2, 1.7, 1.4)
    }
}
