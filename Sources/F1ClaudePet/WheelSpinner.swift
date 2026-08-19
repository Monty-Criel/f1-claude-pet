import AppKit

/// A spinning Pirelli-shod wheel, shown in the pit wall while Claude is
/// working.
///
/// Same visual language as the car — a compound-colour ring on the sidewall and
/// a five-spoke centre-lock rim — but themed rather than liveried: the rim
/// takes the accent colour so the panel reads as one piece.
@MainActor
final class WheelSpinner: NSView {

    private var angle: CGFloat = 0
    private var timer: Timer?

    var isSpinning = false {
        didSet {
            guard isSpinning != oldValue else { return }
            isHidden = !isSpinning
            isSpinning ? start() : stop()
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func step() {
        angle += 0.42
        needsDisplay = true
    }

    override func draw(_ dirty: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, isSpinning else { return }
        let accent = Theme.accent

        let radius = min(bounds.height, bounds.width) / 2 - 2
        let centre = CGPoint(x: bounds.midX, y: bounds.midY + 2)
        ctx.setShouldAntialias(true)

        ctx.setFillColor(NSColor(white: 0.07, alpha: 1).cgColor)     // tyre
        ctx.fillEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                                   width: radius * 2, height: radius * 2))

        // Pirelli compound ring hugging the rim.
        let ringR = radius * 0.66
        ctx.setStrokeColor(TyreCompound.selected.color.withAlphaComponent(0.95).cgColor)
        ctx.setLineWidth(1.4)
        ctx.strokeEllipse(in: CGRect(x: centre.x - ringR, y: centre.y - ringR,
                                     width: ringR * 2, height: ringR * 2))

        // Rim barrel and five spokes, in the theme colour.
        let rimR = radius * 0.60
        ctx.setFillColor(NSColor(white: 0.16, alpha: 1).cgColor)
        ctx.fillEllipse(in: CGRect(x: centre.x - rimR, y: centre.y - rimR,
                                   width: rimR * 2, height: rimR * 2))

        ctx.setStrokeColor(accent.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(1.6)
        for spoke in 0..<5 {
            let a = angle + CGFloat(spoke) * .pi * 2 / 5
            ctx.move(to: CGPoint(x: centre.x + cos(a) * rimR * 0.30,
                                 y: centre.y + sin(a) * rimR * 0.30))
            ctx.addLine(to: CGPoint(x: centre.x + cos(a) * rimR * 0.82,
                                    y: centre.y + sin(a) * rimR * 0.82))
        }
        ctx.strokePath()

        // Centre-lock nut.
        ctx.setFillColor(accent.cgColor)
        let nut = rimR * 0.22
        ctx.fillEllipse(in: CGRect(x: centre.x - nut, y: centre.y - nut,
                                   width: nut * 2, height: nut * 2))
    }
}
