import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Renders the car's show into an animated GIF — the README hero demo.
///
/// Nothing is screen-recorded: the same TrackView that drives the Dock is
/// stepped manually at a fixed rate and drawn offscreen, frame by frame, so
/// the clip always matches the current art exactly and needs no permissions.
@MainActor
enum GifRecorder {

    /// The show, as data so it can be sanity-checked in the self-test.
    /// Captions are fixed strings — the real victory caption reads the user's
    /// transcript, which has no business appearing in a README GIF.
    struct Cue {
        let time: Double
        let state: PetState
        let message: String?
    }

    static let choreography: [Cue] = [
        Cue(time: 0.0, state: .launch, message: "LIGHTS OUT"),
        Cue(time: 2.6, state: .racing, message: nil),
        Cue(time: 5.6, state: .victory, message: "P1 \u{1F3C1}"),
    ]

    /// Height of the fake Dock band the car rides on.
    private static let dockBand: CGFloat = 44

    /// The icon lineup drawn on the fake Dock.
    private static let lineup: [FakeIcon] = [.finder, .compass, .mail, .messages,
                                             .maps, .photos, .calendar, .notes,
                                             .music, .terminal, .code, .folder,
                                             .gear, .store]
    private static let tileSize: CGFloat = 30
    private static let tileGap: CGFloat = 10
    private static let dividerWidth: CGFloat = 14

    /// Where the glass pill sits for a given stage width — shared between
    /// record() (which sizes the track to it, so the car cannot overrun the
    /// Dock) and compose() (which draws it there).
    static func pillRect(stageWidth: CGFloat) -> CGRect {
        let rowWidth = CGFloat(lineup.count + 1) * tileSize
            + CGFloat(lineup.count) * tileGap + dividerWidth
        let x = (stageWidth - rowWidth) / 2
        return CGRect(x: x - 12, y: 2, width: rowWidth + 24, height: dockBand - 6)
    }

    static func record(to path: String, car: (any Car)? = nil,
                       seconds: Double = 9, fps: Int = 20,
                       width: CGFloat = 900, height: CGFloat = 150) -> Bool {
        // The track is exactly the pill: the car turns where the Dock ends,
        // the same constraint the real overlay lives under.
        let pill = pillRect(stageWidth: width)
        let view = TrackView(frame: CGRect(x: 0, y: 0, width: pill.width, height: height))
        if let car { view.car = car }
        view.livelyMode = true              // the whole point is the show

        let dt = 1.0 / Double(fps)
        let frameCount = Int(seconds * Double(fps))
        var cues = choreography

        guard let destination = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: path) as CFURL,
            UTType.gif.identifier as CFString, frameCount, nil)
        else { return false }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)

        let frameProperties = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: dt],
        ] as CFDictionary

        for frame in 0..<frameCount {
            let t = Double(frame) * dt
            while let cue = cues.first, t >= cue.time {
                view.apply(cue.state, message: cue.message)
                cues.removeFirst()
            }
            view.advance(dt: dt)

            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { return false }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let composed = compose(rep, width: Int(width),
                                         height: Int(height + Self.dockBand))
            else { return false }
            CGImageDestinationAddImage(destination, composed, frameProperties)
        }
        return CGImageDestinationFinalize(destination)
    }

    /// GIF has 1-bit alpha, which would fringe the smoke — so each frame is
    /// baked onto a stage carrying a fake macOS Dock, drawn to read like the
    /// real thing: wallpaper blobs behind frosted glass, and a lineup that
    /// evokes a default Dock — face, compass, envelope, bubble, calendar,
    /// pinwheel, gear, trash — every icon drawn here, nobody's actual artwork.
    private static func compose(_ rep: NSBitmapImageRep,
                                width: Int, height: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let frame = rep.cgImage
        else { return nil }

        let w = CGFloat(width)
        let space = CGColorSpaceCreateDeviceRGB()
        ctx.setShouldAntialias(true)

        // Clean night backdrop: a quiet vertical gradient with one soft glow
        // above the Dock — no busy wallpaper.
        let sky = [CGColor(red: 0.115, green: 0.125, blue: 0.16, alpha: 1),
                   CGColor(red: 0.05, green: 0.055, blue: 0.075, alpha: 1)] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: sky, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0, y: CGFloat(height)),
                                   end: CGPoint(x: 0, y: 0), options: [])
        }
        let glow = [CGColor(red: 0.30, green: 0.45, blue: 0.75, alpha: 0.10),
                    CGColor(red: 0.30, green: 0.45, blue: 0.75, alpha: 0)] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: glow, locations: [0, 1]) {
            ctx.drawRadialGradient(gradient,
                                   startCenter: CGPoint(x: w / 2, y: 30), startRadius: 0,
                                   endCenter: CGPoint(x: w / 2, y: 30), endRadius: w * 0.55,
                                   options: [])
        }

        let icons = lineup
        let tile = tileSize
        let gap = tileGap
        let divider = dividerWidth
        let iconY: CGFloat = 6

        // The glass pill, where record() promised it would be.
        let pillTop = dockBand - 4
        let pillRect = Self.pillRect(stageWidth: w)
        var x = pillRect.minX + 12
        let pill = CGPath(roundedRect: pillRect, cornerWidth: 16, cornerHeight: 16,
                          transform: nil)
        ctx.saveGState()
        ctx.addPath(pill)
        ctx.clip()
        let glass = [CGColor(gray: 1, alpha: 0.24), CGColor(gray: 1, alpha: 0.10)] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: glass, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0, y: pillRect.maxY),
                                   end: CGPoint(x: 0, y: pillRect.minY), options: [])
        }
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.30))
        ctx.fill(CGRect(x: pillRect.minX + 10, y: pillRect.maxY - 1.2,
                        width: pillRect.width - 20, height: 1.2))
        ctx.restoreGState()
        ctx.addPath(pill)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.22))
        ctx.setLineWidth(1)
        ctx.strokePath()

        for icon in icons {
            icon.draw(in: CGRect(x: x, y: iconY, width: tile, height: tile), ctx: ctx)
            x += tile + gap
        }
        // Divider, then the bin.
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.25))
        ctx.fill(CGRect(x: x + divider / 2 - gap / 2 - 0.5, y: iconY + 3,
                        width: 1, height: tile - 6))
        x += divider
        FakeIcon.trash.draw(in: CGRect(x: x, y: iconY, width: tile, height: tile), ctx: ctx)

        // The car rides the Dock's top edge — over the pill and only the
        // pill, since the track was sized to it.
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        ctx.draw(frame, in: CGRect(x: pillRect.minX, y: pillTop,
                                   width: pillRect.width,
                                   height: CGFloat(height) - pillTop))
        return ctx.makeImage()
    }

    /// Hand-drawn stand-ins for a default Dock. Motifs are generic — an
    /// envelope, a compass, a gear — rendered in macOS's visual grammar
    /// (gradient squircles) without reproducing anyone's icon.
    private enum FakeIcon {
        case finder, compass, mail, messages, maps, photos, calendar
        case notes, music, terminal, code, folder, gear, store, trash

        func draw(in rect: CGRect, ctx: CGContext) {
            let path = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.24,
                              cornerHeight: rect.width * 0.24, transform: nil)
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            fillBackground(rect, ctx)
            glyph(rect, ctx)
            // Gloss: a faint lighter wash over the upper half.
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.09))
            ctx.fill(CGRect(x: rect.minX, y: rect.midY, width: rect.width,
                            height: rect.height / 2))
            ctx.restoreGState()
        }

        private func gradient(_ rect: CGRect, _ ctx: CGContext,
                              top: (CGFloat, CGFloat, CGFloat),
                              bottom: (CGFloat, CGFloat, CGFloat)) {
            let colors = [CGColor(red: top.0, green: top.1, blue: top.2, alpha: 1),
                          CGColor(red: bottom.0, green: bottom.1, blue: bottom.2, alpha: 1)] as CFArray
            guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors, locations: [0, 1]) else { return }
            ctx.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.maxY),
                                   end: CGPoint(x: rect.midX, y: rect.minY), options: [])
        }

        private func fillBackground(_ r: CGRect, _ ctx: CGContext) {
            switch self {
            case .finder:   gradient(r, ctx, top: (0.45, 0.75, 0.98), bottom: (0.15, 0.45, 0.90))
            case .compass:  gradient(r, ctx, top: (0.35, 0.65, 0.95), bottom: (0.10, 0.35, 0.75))
            case .mail:     gradient(r, ctx, top: (0.40, 0.70, 0.98), bottom: (0.15, 0.45, 0.88))
            case .messages: gradient(r, ctx, top: (0.45, 0.90, 0.45), bottom: (0.15, 0.70, 0.25))
            case .maps:     gradient(r, ctx, top: (0.90, 0.95, 0.90), bottom: (0.75, 0.85, 0.78))
            case .photos, .calendar, .notes:
                gradient(r, ctx, top: (0.97, 0.97, 0.97), bottom: (0.85, 0.85, 0.87))
            case .music:    gradient(r, ctx, top: (0.98, 0.45, 0.55), bottom: (0.90, 0.20, 0.30))
            case .terminal: gradient(r, ctx, top: (0.22, 0.22, 0.25), bottom: (0.08, 0.08, 0.10))
            case .code:     gradient(r, ctx, top: (0.25, 0.55, 0.95), bottom: (0.10, 0.30, 0.70))
            case .folder:   gradient(r, ctx, top: (0.50, 0.80, 0.98), bottom: (0.25, 0.60, 0.95))
            case .gear:     gradient(r, ctx, top: (0.80, 0.82, 0.85), bottom: (0.55, 0.58, 0.62))
            case .store:    gradient(r, ctx, top: (0.35, 0.65, 0.98), bottom: (0.12, 0.40, 0.85))
            case .trash:    gradient(r, ctx, top: (0.85, 0.86, 0.88), bottom: (0.62, 0.64, 0.68))
            }
        }

        private func glyph(_ r: CGRect, _ ctx: CGContext) {
            let cx = r.midX, cy = r.midY, s = r.width
            switch self {
            case .finder:
                // Two-tone face: lighter left half, smile, two eyes.
                ctx.setFillColor(CGColor(red: 0.70, green: 0.88, blue: 1, alpha: 0.9))
                ctx.fill(CGRect(x: r.minX, y: r.minY, width: s * 0.48, height: s))
                ctx.setStrokeColor(CGColor(red: 0.05, green: 0.15, blue: 0.35, alpha: 1))
                ctx.setLineWidth(s * 0.06)
                ctx.move(to: CGPoint(x: cx - s * 0.22, y: cy - s * 0.12))
                ctx.addQuadCurve(to: CGPoint(x: cx + s * 0.22, y: cy - s * 0.12),
                                 control: CGPoint(x: cx, y: cy - s * 0.30))
                ctx.strokePath()
                for dx in [-s * 0.16, s * 0.16] {
                    ctx.setFillColor(CGColor(red: 0.05, green: 0.15, blue: 0.35, alpha: 1))
                    ctx.fill(CGRect(x: cx + dx - s * 0.03, y: cy + s * 0.08,
                                    width: s * 0.06, height: s * 0.18))
                }
            case .compass:
                ctx.setFillColor(CGColor(gray: 1, alpha: 0.95))
                ctx.fillEllipse(in: r.insetBy(dx: s * 0.14, dy: s * 0.14))
                ctx.setFillColor(CGColor(red: 0.10, green: 0.35, blue: 0.75, alpha: 1))
                ctx.fillEllipse(in: r.insetBy(dx: s * 0.18, dy: s * 0.18))
                // Needle: red north, white south, tilted.
                ctx.saveGState()
                ctx.translateBy(x: cx, y: cy)
                ctx.rotate(by: .pi / 5)
                ctx.setFillColor(CGColor(red: 0.95, green: 0.30, blue: 0.25, alpha: 1))
                ctx.fill(CGRect(x: -s * 0.035, y: 0, width: s * 0.07, height: s * 0.24))
                ctx.setFillColor(CGColor(gray: 1, alpha: 1))
                ctx.fill(CGRect(x: -s * 0.035, y: -s * 0.24, width: s * 0.07, height: s * 0.24))
                ctx.restoreGState()
            case .mail:
                let env = CGRect(x: cx - s * 0.28, y: cy - s * 0.20,
                                 width: s * 0.56, height: s * 0.40)
                ctx.setFillColor(CGColor(gray: 1, alpha: 0.95))
                ctx.fill(env)
                ctx.setStrokeColor(CGColor(red: 0.25, green: 0.50, blue: 0.85, alpha: 1))
                ctx.setLineWidth(s * 0.045)
                ctx.move(to: CGPoint(x: env.minX, y: env.maxY))
                ctx.addLine(to: CGPoint(x: cx, y: cy))
                ctx.addLine(to: CGPoint(x: env.maxX, y: env.maxY))
                ctx.strokePath()
            case .messages:
                let bubble = CGPath(roundedRect: CGRect(x: cx - s * 0.26, y: cy - s * 0.18,
                                                        width: s * 0.52, height: s * 0.40),
                                    cornerWidth: s * 0.14, cornerHeight: s * 0.14,
                                    transform: nil)
                ctx.setFillColor(CGColor(gray: 1, alpha: 0.95))
                ctx.addPath(bubble)
                ctx.fillPath()
                ctx.move(to: CGPoint(x: cx - s * 0.14, y: cy - s * 0.16))
                ctx.addLine(to: CGPoint(x: cx - s * 0.22, y: cy - s * 0.30))
                ctx.addLine(to: CGPoint(x: cx - 0.02 * s, y: cy - s * 0.16))
                ctx.fillPath()
            case .maps:
                // Diagonal road with a pin.
                ctx.setStrokeColor(CGColor(red: 0.95, green: 0.75, blue: 0.20, alpha: 1))
                ctx.setLineWidth(s * 0.10)
                ctx.move(to: CGPoint(x: r.minX + s * 0.1, y: r.minY + s * 0.15))
                ctx.addQuadCurve(to: CGPoint(x: r.maxX - s * 0.1, y: r.maxY - s * 0.2),
                                 control: CGPoint(x: cx + s * 0.2, y: cy - s * 0.25))
                ctx.strokePath()
                ctx.setFillColor(CGColor(red: 0.90, green: 0.25, blue: 0.25, alpha: 1))
                ctx.fillEllipse(in: CGRect(x: cx - s * 0.09, y: cy + s * 0.02,
                                           width: s * 0.18, height: s * 0.18))
            case .photos:
                // Eight-petal pinwheel.
                let hues: [(CGFloat, CGFloat, CGFloat)] = [
                    (0.95, 0.35, 0.30), (0.98, 0.60, 0.20), (0.95, 0.85, 0.25),
                    (0.45, 0.80, 0.30), (0.25, 0.75, 0.65), (0.25, 0.55, 0.95),
                    (0.55, 0.40, 0.90), (0.90, 0.40, 0.75),
                ]
                for (i, hue) in hues.enumerated() {
                    ctx.saveGState()
                    ctx.translateBy(x: cx, y: cy)
                    ctx.rotate(by: CGFloat(i) * .pi / 4)
                    ctx.setFillColor(CGColor(red: hue.0, green: hue.1, blue: hue.2, alpha: 0.85))
                    ctx.fillEllipse(in: CGRect(x: -s * 0.06, y: 0,
                                               width: s * 0.12, height: s * 0.30))
                    ctx.restoreGState()
                }
            case .calendar:
                ctx.setFillColor(CGColor(red: 0.92, green: 0.28, blue: 0.25, alpha: 1))
                ctx.fill(CGRect(x: r.minX, y: r.maxY - s * 0.30, width: s, height: s * 0.30))
                Self.text("17", size: s * 0.42, weight: .semibold,
                          color: CGColor(red: 0.2, green: 0.2, blue: 0.22, alpha: 1),
                          at: CGPoint(x: cx, y: r.minY + s * 0.10), ctx: ctx)
            case .notes:
                ctx.setFillColor(CGColor(red: 0.98, green: 0.83, blue: 0.25, alpha: 1))
                ctx.fill(CGRect(x: r.minX, y: r.maxY - s * 0.24, width: s, height: s * 0.24))
                ctx.setStrokeColor(CGColor(gray: 0.65, alpha: 1))
                ctx.setLineWidth(s * 0.035)
                for i in 1...3 {
                    let y = r.minY + s * 0.16 * CGFloat(i)
                    ctx.move(to: CGPoint(x: r.minX + s * 0.16, y: y))
                    ctx.addLine(to: CGPoint(x: r.maxX - s * 0.16, y: y))
                }
                ctx.strokePath()
            case .music:
                ctx.setFillColor(CGColor(gray: 1, alpha: 0.96))
                ctx.fillEllipse(in: CGRect(x: cx - s * 0.24, y: cy - s * 0.22,
                                           width: s * 0.17, height: s * 0.13))
                ctx.fillEllipse(in: CGRect(x: cx + s * 0.07, y: cy - s * 0.16,
                                           width: s * 0.17, height: s * 0.13))
                ctx.setLineWidth(s * 0.055)
                ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.96))
                ctx.move(to: CGPoint(x: cx - s * 0.08, y: cy - s * 0.16))
                ctx.addLine(to: CGPoint(x: cx - s * 0.08, y: cy + s * 0.24))
                ctx.addLine(to: CGPoint(x: cx + s * 0.23, y: cy + s * 0.30))
                ctx.addLine(to: CGPoint(x: cx + s * 0.23, y: cy - s * 0.10))
                ctx.strokePath()
            case .terminal:
                Self.text(">_", size: s * 0.38, weight: .bold,
                          color: CGColor(gray: 0.95, alpha: 1),
                          at: CGPoint(x: cx - s * 0.02, y: cy - s * 0.16), ctx: ctx)
            case .code:
                Self.text("</>", size: s * 0.34, weight: .bold,
                          color: CGColor(gray: 1, alpha: 0.95),
                          at: CGPoint(x: cx, y: cy - s * 0.14), ctx: ctx)
            case .folder:
                ctx.setFillColor(CGColor(red: 0.85, green: 0.93, blue: 1, alpha: 0.95))
                ctx.fill(CGRect(x: cx - s * 0.28, y: cy - s * 0.18,
                                width: s * 0.56, height: s * 0.34))
                ctx.fill(CGRect(x: cx - s * 0.28, y: cy + s * 0.12,
                                width: s * 0.24, height: s * 0.10))
            case .gear:
                ctx.setFillColor(CGColor(gray: 0.35, alpha: 1))
                for i in 0..<8 {
                    ctx.saveGState()
                    ctx.translateBy(x: cx, y: cy)
                    ctx.rotate(by: CGFloat(i) * .pi / 4)
                    ctx.fill(CGRect(x: -s * 0.05, y: s * 0.12, width: s * 0.10, height: s * 0.14))
                    ctx.restoreGState()
                }
                ctx.fillEllipse(in: r.insetBy(dx: s * 0.26, dy: s * 0.26))
                ctx.setFillColor(CGColor(gray: 0.8, alpha: 1))
                ctx.fillEllipse(in: r.insetBy(dx: s * 0.38, dy: s * 0.38))
            case .store:
                ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.95))
                ctx.setLineWidth(s * 0.07)
                ctx.strokeEllipse(in: r.insetBy(dx: s * 0.2, dy: s * 0.2))
                ctx.setLineWidth(s * 0.06)
                ctx.move(to: CGPoint(x: cx - s * 0.12, y: cy - s * 0.12))
                ctx.addLine(to: CGPoint(x: cx, y: cy + s * 0.16))
                ctx.addLine(to: CGPoint(x: cx + s * 0.12, y: cy - s * 0.12))
                ctx.strokePath()
            case .trash:
                ctx.setFillColor(CGColor(gray: 0.92, alpha: 0.9))
                let body = CGRect(x: cx - s * 0.20, y: r.minY + s * 0.10,
                                  width: s * 0.40, height: s * 0.52)
                ctx.fill(body)
                ctx.setStrokeColor(CGColor(gray: 0.55, alpha: 1))
                ctx.setLineWidth(s * 0.03)
                for i in 0...4 {
                    let lx = body.minX + body.width * CGFloat(i) / 4
                    ctx.move(to: CGPoint(x: lx, y: body.minY))
                    ctx.addLine(to: CGPoint(x: lx, y: body.maxY))
                }
                ctx.strokePath()
                ctx.setFillColor(CGColor(gray: 0.75, alpha: 1))
                ctx.fill(CGRect(x: cx - s * 0.24, y: body.maxY, width: s * 0.48, height: s * 0.07))
            }
        }

        private static func text(_ string: String, size: CGFloat, weight: NSFont.Weight,
                                 color: CGColor, at point: CGPoint, ctx: CGContext) {
            let attributed = NSAttributedString(string: string, attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: weight),
                .foregroundColor: NSColor(cgColor: color) ?? .white,
            ])
            let line = CTLineCreateWithAttributedString(attributed)
            let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
            ctx.saveGState()
            ctx.textPosition = CGPoint(x: point.x - bounds.width / 2, y: point.y)
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }
    }
}
