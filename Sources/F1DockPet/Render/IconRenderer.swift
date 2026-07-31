import AppKit
import ImageIO

/// Draws the app icon: the car on a dark squircle with a checkered strip.
///
/// Generated from the same sprite the pet drives, so the icon can never drift
/// out of sync with the artwork — change the car and the icon follows.
enum IconRenderer {

    static func exportPNG(car: any Car, to path: String, size: Int = 1024) -> Bool {
        let s = CGFloat(size)
        guard let ctx = CGContext(data: nil, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }

        ctx.setShouldAntialias(true)

        // macOS icons sit inside a squircle with a margin around it.
        let margin = s * 0.055
        let rect = CGRect(x: margin, y: margin, width: s - margin * 2, height: s - margin * 2)
        let radius = rect.width * 0.225
        let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        ctx.saveGState()
        ctx.addPath(squircle)
        ctx.clip()

        // Racing blue, darker towards the bottom.
        let colors = [
            NSColor(srgbRed: 0.09, green: 0.20, blue: 0.52, alpha: 1).cgColor,
            NSColor(srgbRed: 0.03, green: 0.06, blue: 0.20, alpha: 1).cgColor,
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0, y: rect.maxY),
                                   end: CGPoint(x: 0, y: rect.minY),
                                   options: [])
        }

        // Work out where the car goes first, so the streaks can sit behind it
        // rather than floating somewhere above.
        let squares = 20
        let squareSize = rect.width / CGFloat(squares)
        let flagTop = rect.minY + squareSize * 2

        let targetW = rect.width * 0.94
        let carScale = targetW / car.pixelSize.width
        let targetH = car.pixelSize.height * carScale
        let carRect = CGRect(x: rect.midX - targetW / 2,
                             y: flagTop + (rect.maxY - flagTop - targetH) * 0.42,
                             width: targetW, height: targetH)

        // Speed streaks, trailing off the back of the car.
        for i in 0..<5 {
            let fraction = CGFloat(i) / 4
            let y = carRect.minY + targetH * (0.28 + fraction * 0.52)
            let w = rect.width * (0.40 - fraction * 0.075)
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.10 - fraction * 0.012).cgColor)
            ctx.fill(CGRect(x: rect.minX + rect.width * 0.03, y: y, width: w, height: s * 0.011))
        }
        for column in 0..<squares {
            for row in 0..<2 {
                let dark = (column + row) % 2 == 0
                ctx.setFillColor(dark ? NSColor.white.withAlphaComponent(0.92).cgColor
                                      : NSColor.black.withAlphaComponent(0.85).cgColor)
                ctx.fill(CGRect(x: rect.minX + CGFloat(column) * squareSize,
                                y: rect.minY + CGFloat(row) * squareSize,
                                width: squareSize, height: squareSize))
            }
        }

        // The car itself, nearest-neighbour so the pixels stay hard.
        if let sprite = CarRenderer.image(for: car, wheelAngle: 0.4) {
            // Soft shadow so the car lifts off the background.
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012),
                          blur: s * 0.03,
                          color: NSColor.black.withAlphaComponent(0.55).cgColor)
            ctx.interpolationQuality = .none
            ctx.setShouldAntialias(false)
            ctx.draw(sprite, in: carRect)
            ctx.restoreGState()
        }

        ctx.restoreGState()

        // Rim light around the squircle.
        ctx.setShouldAntialias(true)
        ctx.addPath(squircle)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.16).cgColor)
        ctx.setLineWidth(s * 0.006)
        ctx.strokePath()

        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(
                URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }
}
