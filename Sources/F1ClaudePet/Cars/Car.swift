import AppKit

/// A wheel, in the car's own pixel grid (y-up, origin at the ground line).
struct Wheel {
    let center: CGPoint
    let radius: CGFloat
    /// Rear wheels are the driven ones — these are the ones that light up.
    let isDriven: Bool
}

/// What kind of racing car this is. Drives the grouping in the menu bar.
enum CarCategory: String, CaseIterable {
    case formula1 = "F1"
    case gt3 = "GT3"

    var displayName: String {
        switch self {
        case .formula1: return "Formula 1"
        case .gt3:      return "GT3"
        }
    }
}

/// A liveried car the pet can drive.
///
/// Cars are authored as vector paths in a small pixel grid and rasterised with
/// anti-aliasing off, which keeps the crisp sprite look while staying far
/// easier to tweak than a hand-painted spritesheet. Adding a model means
/// adding one file conforming to this protocol, then listing it in `CarRegistry`.
///
/// All coordinates are in *pixel units*, y-up, with y = 0 as the ground the
/// tyres sit on and the car facing **right**.
protocol Car: Sendable {
    /// Stable identifier used in settings and on the command line.
    var id: String { get }
    var displayName: String { get }
    var category: CarCategory { get }

    /// Native sprite grid. Keep it small — this is what gives the pixel look.
    var pixelSize: CGSize { get }

    var wheels: [Wheel] { get }

    /// Tyre and rim colours, so different eras can run different rubber.
    var tyreColor: NSColor { get }
    var rimColor: NSColor { get }

    /// Aero rake: how many degrees the rear of the car is jacked up relative to
    /// the front. Applied to the chassis only — the tyres stay on the ground.
    var rakeDegrees: CGFloat { get }

    /// Non-uniform stretch applied to the chassis artwork only. Lets the
    /// chunky/lanky balance be tuned by changing two numbers instead of
    /// re-authoring every coordinate in the car.
    var chassisStretch: CGSize { get }

    /// Where the exhaust exits, in pixel units. Puffs are emitted from here
    /// while the engine is idling.
    var exhaustPoint: CGPoint { get }

    /// Draw everything except the wheels. The context is already set up in
    /// pixel units with y-up and anti-aliasing disabled.
    func drawChassis(in ctx: CGContext)
}

extension Car {
    var tyreColor: NSColor { NSColor(srgbRed: 0.08, green: 0.09, blue: 0.11, alpha: 1) }
    var rimColor: NSColor { NSColor(srgbRed: 0.78, green: 0.80, blue: 0.84, alpha: 1) }
    var rakeDegrees: CGFloat { 0 }
    var chassisStretch: CGSize { CGSize(width: 1, height: 1) }

    /// Sensible default: just behind the rearmost wheel, at axle height.
    var exhaustPoint: CGPoint {
        let rear = wheels.min(by: { $0.center.x < $1.center.x })?.center ?? .zero
        return CGPoint(x: max(0, rear.x - 6), y: rear.y + 1)
    }

    /// Where an engine fire breaks out — over the power unit, between the rear
    /// axle and the cockpit.
    var engineBayPoint: CGPoint {
        let rear = wheels.min(by: { $0.center.x < $1.center.x })?.center ?? .zero
        return CGPoint(x: rear.x + 8, y: pixelSize.height * 0.55)
    }

    /// Rake pivots about the front axle, so raking the car lifts the tail
    /// rather than burying the nose below the road.
    var rakePivot: CGPoint {
        wheels.max(by: { $0.center.x < $1.center.x })?.center ?? .zero
    }
}

// MARK: - drawing helpers

extension CGContext {
    /// Fill a shape built by `build` in the given colour.
    func fill(_ color: NSColor, _ build: (CGMutablePath) -> Void) {
        let path = CGMutablePath()
        build(path)
        setFillColor(color.cgColor)
        addPath(path)
        fillPath()
    }

    /// Stroke a shape built by `build`.
    func stroke(_ color: NSColor, width: CGFloat, _ build: (CGMutablePath) -> Void) {
        let path = CGMutablePath()
        build(path)
        setStrokeColor(color.cgColor)
        setLineWidth(width)
        setLineCap(.round)
        addPath(path)
        strokePath()
    }

    func fillRect(_ color: NSColor, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        setFillColor(color.cgColor)
        fill(CGRect(x: x, y: y, width: w, height: h))
    }
}

extension CGMutablePath {
    /// Add a closed polygon through the given points.
    func polygon(_ points: [CGPoint]) {
        guard let first = points.first else { return }
        move(to: first)
        for p in points.dropFirst() { addLine(to: p) }
        closeSubpath()
    }
}

func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
