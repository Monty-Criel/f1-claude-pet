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

        // Team mark on the engine cover flank: a rising accent flash with a
        // trim tick — reads as a logo without pretending to be lettering.
        ctx.fill(livery.accent) { p in
            p.polygon([pt(16.4, 9.0), pt(19.6, 9.7), pt(19.6, 10.5), pt(16.4, 9.8)])
        }
        ctx.fillRect(livery.trim, 20.2, 9.9, 0.8, 0.8)

        // Floor and tub.
        ctx.fillRect(livery.shade, 11, 2.8, 46, 1.5)
        ctx.fill(livery.primary) { p in
            p.polygon([pt(13, 4), pt(48, 4), pt(48, 8.2), pt(42, 9.6),
                       pt(32, 9.8), pt(22, 9.2), pt(13, 8.4)])
        }
        // Underfloor skirt dropping between the wheels to front-wing height:
        // skirt, skid line along its bottom, strakes hanging toward the track.
        ctx.fill(livery.shade) { p in
            p.polygon([pt(23, 2.8), pt(48, 2.8), pt(48, 1.6),
                       pt(44, 1.3), pt(26, 1.3), pt(23, 1.8)])
        }
        ctx.fillRect(livery.trim, 26, 1.3, 16, 0.35)
        ctx.fillRect(livery.accent, 36, 1.9, 5, 0.5)
        ctx.fillRect(livery.shade, 43.5, 0.9, 0.7, 1.0)
        ctx.fillRect(livery.shade, 45.5, 0.9, 0.7, 1.0)
        ctx.fillRect(livery.shade, 47.3, 0.9, 0.7, 1.0)

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

        // Broadcast kit: T-cam, race number, silver halo edge, mirror.
        let silver = NSColor(srgbRed: 0.72, green: 0.76, blue: 0.82, alpha: 1)
        ctx.fillRect(NSColor(white: 0.08, alpha: 1), 28.2, 13.8 + a, 3.2, 1.2)
        ctx.fillRect(NSColor(srgbRed: 0.85, green: 0.08, blue: 0.06, alpha: 1),
                     31.4, 13.9 + a, 0.9, 1.0)
        ctx.fillRect(livery.trim, 55.8, 4.7, 0.8, 2.3)
        ctx.fillRect(livery.trim, 57.2, 4.7, 0.8, 2.3)
        ctx.stroke(silver, width: 0.5) { p in
            p.move(to: pt(32.6, 10.4))
            p.addCurve(to: pt(43.8, 9.2), control1: pt(35, 13.1), control2: pt(42, 12.3))
        }
        ctx.fillRect(livery.shade, 43.6, 10.6, 1.6, 0.9)
        ctx.fillRect(silver, 43.8, 10.8, 1.0, 0.5)
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

    /// Aston Martin AMR26 — racing green with a lime flash.
    static let astonMartin = F1Car(
        id: "amr26",
        displayName: "Aston Martin AMR26 (2026)",
        livery: Livery(
            primary: NSColor(srgbRed: 0.00, green: 0.35, blue: 0.28, alpha: 1),
            shade:   NSColor(srgbRed: 0.00, green: 0.17, blue: 0.14, alpha: 1),
            accent:  NSColor(srgbRed: 0.62, green: 0.90, blue: 0.10, alpha: 1),
            trim:    NSColor(srgbRed: 0.93, green: 0.95, blue: 0.96, alpha: 1)
        ),
        noseLength: 0.8,
        airbox: 0.2
    )

    /// Williams FW48 — Atlassian navy with electric blue.
    static let williams = F1Car(
        id: "fw48",
        displayName: "Williams FW48 (2026)",
        livery: Livery(
            primary: NSColor(srgbRed: 0.04, green: 0.13, blue: 0.38, alpha: 1),
            shade:   NSColor(srgbRed: 0.02, green: 0.06, blue: 0.19, alpha: 1),
            accent:  NSColor(srgbRed: 0.15, green: 0.60, blue: 0.98, alpha: 1),
            trim:    NSColor(srgbRed: 0.93, green: 0.95, blue: 0.96, alpha: 1)
        ),
        noseLength: 0,
        airbox: 0
    )

    /// Alpine A526 — French blue with the pink flash.
    static let alpine = F1Car(
        id: "a526",
        displayName: "Alpine A526 (2026)",
        livery: Livery(
            primary: NSColor(srgbRed: 0.02, green: 0.22, blue: 0.60, alpha: 1),
            shade:   NSColor(srgbRed: 0.01, green: 0.10, blue: 0.30, alpha: 1),
            accent:  NSColor(srgbRed: 0.96, green: 0.32, blue: 0.58, alpha: 1),
            trim:    NSColor(srgbRed: 0.93, green: 0.95, blue: 0.96, alpha: 1)
        ),
        noseLength: -0.8,
        airbox: 0.3
    )

    /// Audi R26 — titanium silver over carbon, Audi Sport red.
    static let audi = F1Car(
        id: "r26",
        displayName: "Audi R26 (2026)",
        livery: Livery(
            primary: NSColor(srgbRed: 0.70, green: 0.73, blue: 0.77, alpha: 1),
            shade:   NSColor(srgbRed: 0.14, green: 0.15, blue: 0.17, alpha: 1),
            accent:  NSColor(srgbRed: 0.88, green: 0.06, blue: 0.10, alpha: 1),
            trim:    NSColor(srgbRed: 0.07, green: 0.08, blue: 0.09, alpha: 1)
        ),
        noseLength: 0.5,
        airbox: 0.5
    )

    /// Racing Bulls RB03 — white with the blue-and-red bull flashes.
    static let racingBulls = F1Car(
        id: "vcarb03",
        displayName: "Racing Bulls RB03 (2026)",
        livery: Livery(
            primary: NSColor(srgbRed: 0.92, green: 0.93, blue: 0.95, alpha: 1),
            shade:   NSColor(srgbRed: 0.16, green: 0.24, blue: 0.48, alpha: 1),
            accent:  NSColor(srgbRed: 0.10, green: 0.30, blue: 0.75, alpha: 1),
            trim:    NSColor(srgbRed: 0.88, green: 0.10, blue: 0.14, alpha: 1)
        ),
        noseLength: -1,
        airbox: 0.2
    )

    /// Haas VF-26 — white over black with the red stripe.
    static let haas = F1Car(
        id: "vf26",
        displayName: "Haas VF-26 (2026)",
        livery: Livery(
            primary: NSColor(srgbRed: 0.90, green: 0.91, blue: 0.93, alpha: 1),
            shade:   NSColor(srgbRed: 0.10, green: 0.11, blue: 0.12, alpha: 1),
            accent:  NSColor(srgbRed: 0.16, green: 0.17, blue: 0.19, alpha: 1),
            trim:    NSColor(srgbRed: 0.85, green: 0.08, blue: 0.10, alpha: 1)
        ),
        noseLength: 0.3,
        airbox: 0
    )

    /// Cadillac — the 2026 new entry: black with gold and a red-white flash.
    static let cadillac = F1Car(
        id: "cadillac26",
        displayName: "Cadillac (2026)",
        livery: Livery(
            primary: NSColor(srgbRed: 0.08, green: 0.08, blue: 0.10, alpha: 1),
            shade:   NSColor(srgbRed: 0.03, green: 0.03, blue: 0.04, alpha: 1),
            accent:  NSColor(srgbRed: 0.83, green: 0.62, blue: 0.22, alpha: 1),
            trim:    NSColor(srgbRed: 0.85, green: 0.10, blue: 0.12, alpha: 1)
        ),
        noseLength: 1.2,
        airbox: 0.4
    )

    static let all: [any Car] = [
        mercedes, mclaren, astonMartin, williams, alpine,
        audi, racingBulls, haas, cadillac,
    ]
}
