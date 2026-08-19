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

    static func record(to path: String, car: (any Car)? = nil,
                       seconds: Double = 9, fps: Int = 20,
                       width: CGFloat = 900, height: CGFloat = 150) -> Bool {
        let view = TrackView(frame: CGRect(x: 0, y: 0, width: width, height: height))
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
    /// baked onto a dark stage carrying a fake macOS Dock: translucent pill,
    /// a row of generic app tiles (deliberately nobody's real icon), and the
    /// car riding along its top edge, exactly as it does on the real thing.
    private static func compose(_ rep: NSBitmapImageRep,
                                width: Int, height: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let frame = rep.cgImage
        else { return nil }

        ctx.setFillColor(CGColor(red: 0.075, green: 0.07, blue: 0.08, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // The Dock pill.
        let pillTop = dockBand - 6
        let pill = CGPath(roundedRect: CGRect(x: 10, y: 4, width: CGFloat(width) - 20,
                                              height: pillTop - 4),
                          cornerWidth: 15, cornerHeight: 15, transform: nil)
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.12))
        ctx.addPath(pill)
        ctx.fillPath()

        // App tiles: two-tone rounded squares in a fixed palette — abstract
        // on purpose, so the Dock reads as a Dock without copying any icon.
        let palette: [(CGFloat, CGFloat, CGFloat)] = [
            (0.36, 0.62, 0.98), (0.94, 0.42, 0.36), (0.30, 0.80, 0.70),
            (0.98, 0.70, 0.25), (0.66, 0.48, 0.95), (0.42, 0.82, 0.38),
            (0.92, 0.48, 0.72), (0.55, 0.58, 0.64),
        ]
        let tile: CGFloat = 26
        let gap: CGFloat = 9
        let count = Int((CGFloat(width) - 48) / (tile + gap))
        let rowWidth = CGFloat(count) * tile + CGFloat(count - 1) * gap
        var x = (CGFloat(width) - rowWidth) / 2
        for index in 0..<count {
            let (r, g, b) = palette[index % palette.count]
            let rect = CGRect(x: x, y: 8, width: tile, height: tile)
            let path = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6,
                              transform: nil)
            ctx.addPath(path)
            ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
            ctx.fillPath()
            // A lighter cap on the upper half sells the icon gradient.
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.setFillColor(CGColor(red: min(1, r + 0.14), green: min(1, g + 0.14),
                                     blue: min(1, b + 0.14), alpha: 1))
            ctx.fill(CGRect(x: rect.minX, y: rect.midY, width: tile, height: tile / 2))
            ctx.restoreGState()
            // Running-indicator dots under a few of them.
            if index % 4 == 1 {
                ctx.setFillColor(CGColor(gray: 1, alpha: 0.55))
                ctx.fillEllipse(in: CGRect(x: rect.midX - 1.5, y: 3, width: 3, height: 3))
            }
            x += tile + gap
        }

        // The car rides the Dock's top edge, like the real overlay does.
        ctx.interpolationQuality = .none    // keep the pixels hard
        ctx.draw(frame, in: CGRect(x: 0, y: pillTop,
                                   width: CGFloat(width),
                                   height: CGFloat(height) - pillTop))
        return ctx.makeImage()
    }
}
