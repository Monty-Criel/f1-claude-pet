import AppKit

/// A Formula 1 car built from a shared body.
///
/// This is a deliberate contrast with the GT3 cars, which each get their own
/// silhouette. F1 regulations are prescriptive enough that the 2026 cars really
/// are near-identical in profile — the identity is the livery, plus small
/// differences in nose length, airbox height and sidepod shape. Drawing five
/// bespoke bodies here would be inventing differences that do not exist.
///
/// The RB22 and SF-26 remain hand-drawn because they were built first and carry
/// extra detail; this covers the rest of the grid.
struct F1Car: Car {
    let id: String
    let displayName: String
    let livery: Livery
    var category: CarCategory { .formula1 }

    /// How far the nose reaches ahead of the front axle.
    var noseLength: CGFloat = 0
    /// Height of the airbox above the cockpit.
    var airbox: CGFloat = 0

    let pixelSize = CGSize(width: 72, height: 20)
    let wheels = [
        Wheel(center: pt(16, 5.9), radius: 5.9, isDriven: true),
        Wheel(center: pt(54, 5.2), radius: 5.2, isDriven: false),
    ]
    let rakeDegrees: CGFloat = 3
    let exhaustPoint = pt(6.5, 7.6)

    func drawChassis(in ctx: CGContext) {
        let n = noseLength
        let a = airbox

        // Rear wing.
        ctx.fillRect(livery.shade, 10, 8.6, 1.8, 5.4)
        ctx.fillRect(livery.primary, 3, 10.8, 8, 1.2)
        ctx.fillRect(livery.primary, 1, 13.4, 13, 1.8)
        ctx.fillRect(livery.accent, 1, 15.2, 13, 0.9)
        ctx.fillRect(livery.shade, 0.4, 11, 2, 5.4)

        // Exhaust and diffuser.
        ctx.fillRect(livery.shade, 6, 6.9, 6, 1.6)
        ctx.fillRect(livery.trim, 5.6, 7.2, 0.9, 1)
        ctx.fillRect(livery.shade, 7, 4.4, 6, 1.6)

        // Engine cover sweeping up to the airbox.
        ctx.fill(livery.primary) { p in
            p.move(to: pt(10, 8.2))
            p.addLine(to: pt(10, 9.6))
            p.addCurve(to: pt(26, 13.4 + a), control1: pt(17, 10.6), control2: pt(22, 12.8 + a))
            p.addLine(to: pt(32, 13.4 + a))
            p.addLine(to: pt(32, 8.2))
            p.closeSubpath()
        }
        ctx.fill(livery.shade) { p in
            p.polygon([pt(26.5, 13.6 + a), pt(32.5, 13.6 + a), pt(32.5, 11), pt(26.5, 11.8)])
        }
        ctx.fillRect(livery.accent, 26.5, 12.8 + a, 6, 0.9)

        // Floor and tub.
        ctx.fillRect(livery.shade, 11, 2.8, 46, 1.5)
        ctx.fill(livery.primary) { p in
            p.polygon([pt(13, 4), pt(48, 4), pt(48, 8.2), pt(42, 9.6),
                       pt(32, 9.8), pt(22, 9.2), pt(13, 8.4)])
        }

        // Sidepod.
        ctx.fill(livery.accent) { p in
            p.polygon([pt(28, 4.4), pt(48, 4.4), pt(48, 8), pt(43, 9), pt(31, 9), pt(28, 7.6)])
        }
        ctx.fillRect(livery.shade, 46, 5.2, 2.2, 2.8)
        ctx.fillRect(livery.trim, 28, 4.4, 20, 0.6)

        // Cockpit and halo.
        ctx.fillRect(livery.shade, 33, 9.2, 9, 1.2)
        ctx.fillRect(livery.shade, 35.5, 10.2, 3, 1.2)
        ctx.fillRect(livery.trim, 35.7, 10.6, 2.4, 0.5)
        ctx.stroke(livery.shade, width: 1.1) { p in
            p.move(to: pt(32.5, 10))
            p.addCurve(to: pt(44, 8.8), control1: pt(35, 12.8), control2: pt(42, 12))
        }

        // Nose and front wing.
        ctx.fill(livery.primary) { p in
            p.polygon([pt(46, 8), pt(58, 6.4), pt(67 + n, 4.8),
                       pt(67 + n, 2.8), pt(58, 4), pt(46, 4.2)])
        }
        ctx.fill(livery.accent) { p in
            p.polygon([pt(62 + n, 5.5), pt(67 + n, 4.8), pt(67 + n, 2.8), pt(62 + n, 3.4)])
        }
        ctx.fillRect(livery.shade, 60, 0.8, 12, 1.3)
        ctx.fillRect(livery.trim, 60, 0.8, 12, 0.45)
        ctx.fillRect(livery.primary, 60.5, 2.2, 9, 0.9)
        ctx.fillRect(livery.shade, 70.3, 0.4, 1.7, 4.4)
    }
}

enum F1Grid {
    /// Mercedes-AMG W17 — black with Petronas teal.
    static let mercedes = F1Car(
        id: "w17",
        displayName: "Mercedes-AMG W17 (2026)",
        livery: Livery(
            primary: NSColor(srgbRed: 0.09, green: 0.10, blue: 0.12, alpha: 1),
            shade:   NSColor(srgbRed: 0.04, green: 0.05, blue: 0.06, alpha: 1),
            accent:  NSColor(srgbRed: 0.00, green: 0.82, blue: 0.75, alpha: 1),
            trim:    NSColor(srgbRed: 0.78, green: 0.82, blue: 0.85, alpha: 1)
        ),
        noseLength: 0,
        airbox: 0.4
    )

    /// McLaren MCL40 — papaya and anthracite.
    static let mclaren = F1Car(
        id: "mcl40",
        displayName: "McLaren MCL40 (2026)",
        livery: Livery(
            primary: NSColor(srgbRed: 1.00, green: 0.47, blue: 0.00, alpha: 1),
            shade:   NSColor(srgbRed: 0.13, green: 0.14, blue: 0.16, alpha: 1),
            accent:  NSColor(srgbRed: 0.05, green: 0.07, blue: 0.09, alpha: 1),
            trim:    NSColor(srgbRed: 0.13, green: 0.72, blue: 0.90, alpha: 1)
        ),
        noseLength: -1.5,
        airbox: 0
    )

    static let all: [any Car] = [mercedes, mclaren]
}
