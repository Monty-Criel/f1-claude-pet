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
            guard let composed = compose(rep, width: Int(width), height: Int(height))
            else { return false }
            CGImageDestinationAddImage(destination, composed, frameProperties)
        }
        return CGImageDestinationFinalize(destination)
    }

    /// GIF has 1-bit alpha, which would fringe the smoke — so each frame is
    /// baked onto a dark stage with a Dock-like pill for the car to sit on.
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

        // The Dock pill the car drives along.
        let pill = CGPath(roundedRect: CGRect(x: 10, y: 4, width: width - 20, height: 30),
                          cornerWidth: 14, cornerHeight: 14, transform: nil)
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.10))
        ctx.addPath(pill)
        ctx.fillPath()

        ctx.interpolationQuality = .none    // keep the pixels hard
        ctx.draw(frame, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}
