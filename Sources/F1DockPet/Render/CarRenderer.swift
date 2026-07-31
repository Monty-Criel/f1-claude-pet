import AppKit
import ImageIO

/// Rasterises a `Car` into a crisp pixel sprite.
///
/// The car is drawn at its small native grid with anti-aliasing off, then the
/// caller blits it up with nearest-neighbour sampling. That combination is what
/// produces hard pixel edges instead of a blurry upscale.
enum CarRenderer {

    /// Render one frame of a car.
    /// - Parameters:
    ///   - wheelAngle: rotation of the wheels, in radians.
    ///   - facingRight: mirrored when the car is heading the other way.
    ///   - wheelSpin: 0…1, how much motion blur to put through the rims.
    ///   - deflation: 0…1 puncture on the driven tyre. Squashes it and drops
    ///     that corner of the car, so a failure is legible even in silhouette.
    ///   - detail: rasterisation multiplier. The art is vector paths, so a
    ///     higher detail draws the same car into a finer bitmap — rounder
    ///     wheels, crisper curves — without touching the artwork. Pair with a
    ///     smaller on-screen scale to trade pixel chunkiness for fidelity.
    static func image(for car: any Car,
                      wheelAngle: CGFloat = 0,
                      facingRight: Bool = true,
                      wheelSpin: CGFloat = 0,
                      deflation: CGFloat = 0,
                      detail: CGFloat = 1) -> CGImage? {

        let w = Int(car.pixelSize.width * detail)
        let h = Int(car.pixelSize.height * detail)

        guard let ctx = CGContext(data: nil,
                                  width: w, height: h,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        ctx.setAllowsAntialiasing(false)
        ctx.setShouldAntialias(false)
        ctx.interpolationQuality = .none

        if !facingRight {
            ctx.translateBy(x: CGFloat(w), y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }
        ctx.scaleBy(x: detail, y: detail)

        // Chassis is raked; the wheels are not, so the tyres stay flat on the road.
        ctx.saveGState()
        // A flat rear tyre drops the tail, i.e. it eats into the rake.
        let effectiveRake = car.rakeDegrees - deflation * (car.rakeDegrees + 4)
        if effectiveRake != 0 {
            let pivot = car.rakePivot
            ctx.translateBy(x: pivot.x, y: pivot.y)
            // Negative angle pitches the nose down, which lifts the tail.
            ctx.rotate(by: -effectiveRake * .pi / 180)
            ctx.translateBy(x: -pivot.x, y: -pivot.y)
        }
        // Applied inside the rake so the car still sits level on its tyres.
        ctx.scaleBy(x: car.chassisStretch.width, y: car.chassisStretch.height)
        car.drawChassis(in: ctx)
        ctx.restoreGState()

        for wheel in car.wheels {
            draw(wheel, of: car, in: ctx, angle: wheelAngle, spin: wheelSpin,
                 deflation: wheel.isDriven ? deflation : 0)
        }

        return ctx.makeImage()
    }

    private static func draw(_ wheel: Wheel,
                             of car: any Car,
                             in ctx: CGContext,
                             angle: CGFloat,
                             spin: CGFloat,
                             deflation: CGFloat = 0) {
        // A punctured tyre squashes vertically, bulges sideways and sits down
        // on a flat contact patch. The rim keeps its shape and stays visible
        // throughout — a deflated tyre, not a wheel that has fallen off.
        let squash = 1 - deflation * 0.34
        let bulge = 1 + deflation * 0.26
        let centreY = wheel.center.y - wheel.radius * deflation * 0.30

        ctx.setFillColor(car.tyreColor.cgColor)
        ctx.fillEllipse(in: CGRect(x: wheel.center.x - wheel.radius * bulge,
                                   y: centreY - wheel.radius * squash,
                                   width: wheel.radius * 2 * bulge,
                                   height: wheel.radius * 2 * squash))

        if deflation > 0.15 {
            // Flat-spotted contact patch where the sidewall has collapsed onto
            // the road, plus the sidewall bulging out either side of it.
            let patchW = wheel.radius * (1.1 + deflation * 0.7)
            ctx.fill(CGRect(x: wheel.center.x - patchW / 2,
                            y: centreY - wheel.radius * squash,
                            width: patchW,
                            height: wheel.radius * 0.45 * deflation))
        }

        if car.category == .formula1 {
            // Pirelli sidewall as on the real tyre: black rubber with one
            // thin compound-colour ring hugging the rim. Two zones, no text.
            let compound = TyreCompound.selected
            let ringR = wheel.radius * 0.66
            ctx.setStrokeColor(compound.color.withAlphaComponent(0.95).cgColor)
            ctx.setLineWidth(0.7)
            ctx.strokeEllipse(in: CGRect(x: wheel.center.x - ringR,
                                         y: centreY - ringR * squash,
                                         width: ringR * 2,
                                         height: ringR * 2 * squash))

            // Modern centre-lock rim. The barrel is tiny at this scale, so
            // restraint is everything: five thin spokes that stop short of
            // the lip, or the silver paves the whole disc and it reads pale.
            let rimR = wheel.radius * 0.60
            ctx.setFillColor(NSColor(srgbRed: 0.15, green: 0.16, blue: 0.18, alpha: 1).cgColor)
            ctx.fillEllipse(in: CGRect(x: wheel.center.x - rimR, y: centreY - rimR,
                                       width: rimR * 2, height: rimR * 2))

            ctx.saveGState()
            ctx.translateBy(x: wheel.center.x, y: centreY)
            ctx.rotate(by: angle)
            ctx.setStrokeColor(car.rimColor.withAlphaComponent(0.9 - spin * 0.75).cgColor)
            ctx.setLineWidth(0.28)
            let spokes = 5
            for i in 0..<spokes {
                let a = CGFloat(i) * (.pi * 2 / CGFloat(spokes))
                ctx.move(to: CGPoint(x: cos(a) * rimR * 0.30, y: sin(a) * rimR * 0.30))
                ctx.addLine(to: CGPoint(x: cos(a) * rimR * 0.82, y: sin(a) * rimR * 0.82))
            }
            ctx.strokePath()
            ctx.restoreGState()

            // Centre-lock nut.
            let nutR = rimR * 0.20
            ctx.setFillColor(car.rimColor.withAlphaComponent(0.9).cgColor)
            ctx.fillEllipse(in: CGRect(x: wheel.center.x - nutR, y: centreY - nutR,
                                       width: nutR * 2, height: nutR * 2))
        } else {
            // GT3 keeps its simple magnesium wheel — no Pirelli F1 branding
            // on a production-based car.
            let rimR = wheel.radius * 0.55
            ctx.setFillColor(car.rimColor.withAlphaComponent(1 - spin * 0.45).cgColor)
            ctx.fillEllipse(in: CGRect(x: wheel.center.x - rimR,
                                       y: centreY - rimR,
                                       width: rimR * 2,
                                       height: rimR * 2))
            ctx.saveGState()
            ctx.translateBy(x: wheel.center.x, y: centreY)
            ctx.rotate(by: angle)
            ctx.setStrokeColor(car.tyreColor.withAlphaComponent(1 - spin * 0.7).cgColor)
            ctx.setLineWidth(0.9)
            for i in 0..<4 {
                let a = CGFloat(i) * (.pi / 2)
                ctx.move(to: .zero)
                ctx.addLine(to: CGPoint(x: cos(a) * rimR, y: sin(a) * rimR))
            }
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    /// Write a magnified PNG of a car — used by `--export-sprite` to eyeball
    /// the artwork without squinting at the Dock.
    static func exportPNG(car: any Car, to path: String, scale: CGFloat = 8,
                          deflation: CGFloat = 0, detail: CGFloat = 1) -> Bool {
        guard let sprite = image(for: car, wheelAngle: 0.3, deflation: deflation,
                                 detail: detail) else { return false }

        let w = Int(car.pixelSize.width * detail * scale)
        let h = Int(car.pixelSize.height * detail * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }

        // Mid-grey backdrop so transparent areas and dark navy stay legible.
        ctx.setFillColor(NSColor(white: 0.45, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .none
        ctx.draw(sprite, in: CGRect(x: 0, y: 0, width: w, height: h))

        guard let out = ctx.makeImage() else { return false }
        let url = URL(fileURLWithPath: path)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(dest, out, nil)
        return CGImageDestinationFinalize(dest)
    }
}
