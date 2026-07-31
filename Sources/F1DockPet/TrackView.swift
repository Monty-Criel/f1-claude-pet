import AppKit

/// The strip of screen the car drives along, sat on top of the Dock.
///
/// The car normally keeps to the right-hand third so it stays out of the way,
/// with its home end acting as the pit box. A new prompt or a tool firing
/// sends it out on one full lap of the whole Dock before it settles back.
@MainActor
final class TrackView: NSView {

    // Touched from deinit, which is not main-actor isolated.
    private nonisolated(unsafe) var displayLink: CADisplayLink?

    /// Swappable at runtime from the menu bar.
    var car: any Car = CarRegistry.selected {
        didSet { needsDisplay = true }
    }

    /// Screen points per art unit. 2.25 with matching raster detail gives a
    /// slightly bigger car drawn from 1pt pixels — round wheels, legible
    /// lettering — instead of chunky 2pt blocks.
    private let scale: CGFloat = 2.25

    /// Fraction of the Dock width the car normally uses, from the right end.
    private let laneFraction: CGFloat = 1.0 / 3.0

    // MARK: - motion

    private var x: CGFloat = 0
    private var direction: CGFloat = -1
    private var velocity: CGFloat = 0
    private var wheelAngle: CGFloat = 0
    /// 0…1 — how much the driven tyres are lighting up.
    private var tyreSpin: CGFloat = 0

    private var state: PetState = .idle
    private var stateAge: CFTimeInterval = 0

    /// Seconds left on a tool-fired speed burst.
    private var boostRemaining: CGFloat = 0
    /// Seconds left sitting still at the end of a lane before turning around.
    private var dwellRemaining: CGFloat = 0
    /// True while hard on the brakes — drives the lock-up puff and brake glow.
    private var isBraking = false

    private enum LapMode { case shortLane, full }
    private var lapMode: LapMode = .shortLane
    private var fullLapReachedFarEnd = false

    /// Off by default, on purpose.
    ///
    /// The pet lives in your peripheral vision while you are trying to read
    /// code. Large, fast, full-width movement every time a tool fires reads as
    /// an interruption rather than a status light, so routine activity stays
    /// small and local. Turning this on restores the full-Dock laps for when
    /// you actually want the show.
    var livelyMode = UserDefaults.standard.bool(forKey: "livelyMode") {
        didSet { UserDefaults.standard.set(livelyMode, forKey: "livelyMode") }
    }

    /// Seconds left of the big cloud that only a tool run produces.
    private var bigSmokeRemaining: CGFloat = 0
    /// How much bigger that cloud is. Set per event, since a boost should
    /// smoke harder than a victory donut.
    private var bigSmokeBillow: CGFloat = 1
    /// Sideways shimmy while sitting still doing a burnout.
    private var wiggle: CGFloat = 0
    /// Vertical shake of a stationary engine idling.
    private var idleShake: CGFloat = 0
    /// 0…1 engine load, driving how hard the exhaust puffs.
    private var revs: CGFloat = 0
    /// 0…1 how flat the rear tyre is after a failure.
    private var puncture: CGFloat = 0
    /// 0…1 size of the engine fire after a failure.
    private var engineFire: CGFloat = 0
    /// 0…1 spark intensity while sat on the line at lights out.
    private var launchSparks: CGFloat = 0
    /// Seconds left of the hard launch off the line — faster and harder
    /// accelerating than an ordinary tool-fired boost.
    private var launchBurst: CGFloat = 0

    /// While Claude works the car alternates between a hot lap and a cool-down
    /// lap, rather than droning round at one speed. A push lap is quick and
    /// throws sparks over the kerbs; a cool-down is a slow roll.
    private enum Stint { case hotLap, coolDown }
    private var stint: Stint = .coolDown
    /// Stints are counted in laps, not seconds — a lap being the length of the
    /// Dock and back. A cool-down is exactly one.
    private var stintLapsRemaining: Int = 1
    /// Bottoming-out sparks, struck at random while pushing.
    private var kerbSparks: CGFloat = 0
    /// Cheap deterministic-ish jitter for picking stint lengths.
    private var rng: UInt64 = 0x2545F4914F6CDD1D

    private func random() -> CGFloat {
        rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
        return CGFloat(rng % 10_000) / 10_000
    }
    /// Rotation about the car's *vertical* axis, for the celebratory donut.
    /// In side view this foreshortens the car to edge-on and back, rather than
    /// cartwheeling it end over end.
    private var yawAngle: CGFloat = 0

    private var smoke = SmokeSystem()
    private var bubbleText: String?
    private var bubbleAlpha: CGFloat = 0

    private var lastFrameTime: CFTimeInterval = CACurrentMediaTime()

    /// Draws the track bounds — handy when checking Dock alignment.
    var showsTrackOutline = false

    /// Frozen from the menu bar. The car stays drawn, it just stops moving.
    var isPaused = false {
        didSet { needsDisplay = true }
    }

    /// True while the chat panel is open. The car parks and stays put — a
    /// panel pinned to a moving car is unreadable, and you came to read it.
    var isChatOpen = false

    override var isFlipped: Bool { false }

    // MARK: - geometry

    private var carSize: CGSize {
        CGSize(width: car.pixelSize.width * scale, height: car.pixelSize.height * scale)
    }

    /// Where the car's lane sits within the window.
    ///
    /// With Accessibility granted the window *is* the Dock strip, so hugging
    /// its right end keeps the car on the Dock. Without it we only know the
    /// Dock's height, not its width, and the window spans the whole screen —
    /// so anchoring right would put the car past the end of the Dock. The Dock
    /// is always centred, so centring is the safe choice there.
    enum LaneAnchor { case right, centre }
    var laneAnchor: LaneAnchor = .right

    /// The stretch of Dock the car may use — its corner normally, the whole
    /// window while it is out on a full lap.
    private var lane: (minX: CGFloat, maxX: CGFloat) {
        switch laneAnchor {
        case .right:
            // The window *is* the Dock strip, so the whole of it is fair game.
            if lapMode == .full { return (bounds.minX, bounds.maxX) }
            // Short laps stay at the car's home end, so it never wanders far
            // from its pit box.
            let width = bounds.width * laneFraction
            return pitHome == .left
                ? (bounds.minX, bounds.minX + width)
                : (bounds.maxX - width, bounds.maxX)

        case .centre:
            // The window is the whole screen and we cannot see where the Dock
            // begins or ends, so stay well inside it — a "full lap" here has to
            // be a centred band, or the car drives off the end of the Dock.
            let width = bounds.width * (lapMode == .full ? 0.5 : laneFraction)
            let mid = bounds.midX
            return (mid - width / 2, mid + width / 2)

        }
    }

    /// Where the car parks when it is called in: the home end of
    /// whichever lane it is using.
    private var pitBoxX: CGFloat {
        let width = bounds.width * laneFraction
        switch (pitHome, laneAnchor) {
        case (.right, .right):  return bounds.maxX - carSize.width - 6
        case (.right, .centre): return bounds.midX + width / 2 - carSize.width - 8
        case (.left, .right):   return bounds.minX + 6
        case (.left, .centre):  return bounds.midX - width / 2 + 8
        }
    }

    /// Which end of the Dock this car calls home. The primary lives on the
    /// left; the second car pits at the right end, so the two never fight over
    /// the same box even though both may use the full Dock when moving.
    enum PitHome: String { case right, left }

    /// Persisted for the primary car, so the choice survives a restart. The
    /// second car sets this directly and is always the opposite end.
    var pitHome: PitHome = .left {
        didSet { needsDisplay = true }
    }

    /// How hard the car drives while Claude works, set by the speed slider in
    /// the menu bar. Scales top speed, acceleration and braking together, so
    /// the car actually reaches the pace it is given before the Dock runs out.
    static let speedRange: ClosedRange<CGFloat> = 0.25...5.0

    static var speedFactor: CGFloat {
        get {
            let stored = UserDefaults.standard.object(forKey: "speedFactor") as? Double
            return min(speedRange.upperBound,
                       max(speedRange.lowerBound, CGFloat(stored ?? 1.0)))
        }
        set {
            let clamped = min(speedRange.upperBound, max(speedRange.lowerBound, newValue))
            UserDefaults.standard.set(Double(clamped), forKey: "speedFactor")
        }
    }

    /// The primary car's home end, as picked in the menu bar.
    static var preferredPitHome: PitHome {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "pitHome") else { return .left }
            return PitHome(rawValue: raw) ?? .left
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "pitHome") }
    }



    /// Where the car is actually painted, including the burnout shimmy.
    private var drawX: CGFloat { x + wiggle }

    // MARK: - interaction

    /// Called when the user clicks the car. Wired by the app delegate.
    var onCarClicked: (() -> Void)?

    /// What the car is doing right now — the chat panel gates on this.
    var currentState: PetState { state }

    /// Persistent caption for a car that represents a session rather than the
    /// live one — the second car wears its session's name as its bubble.
    func showInfo(_ text: String?) {
        infoCaption = text.map { Self.truncate($0) }
        bubbleText = infoCaption
        needsDisplay = true
    }

    /// A caption this car always falls back to — the session it represents.
    /// Set for the second car, and used by the primary once it goes idle so
    /// the Dock always tells you which conversation you are looking at.
    private var infoCaption: String?

    /// The car's rect in screen coordinates, so the chat panel can ride above
    /// it as it moves.
    var carScreenRect: CGRect? {
        guard let window else { return nil }
        return window.convertToScreen(CGRect(x: drawX, y: idleShake,
                                             width: carSize.width, height: carSize.height))
    }

    /// Where the last radio bubble was drawn, in view coordinates. `nil` when
    /// no bubble is showing.
    private var lastBubbleRect: CGRect?

    /// Top of everything the car currently occupies on screen — the car, plus
    /// the bubble when one is up. The chat panel clips above this so it never
    /// lands on top of the radio call.
    var contentTopScreenY: CGFloat? {
        guard let window, let car = carScreenRect else { return nil }
        guard let bubble = lastBubbleRect else { return car.maxY }
        return max(car.maxY, window.convertToScreen(bubble).maxY)
    }

    /// The only part of the window that accepts clicks, padded a little so a
    /// moving target stays catchable.
    private var carHitBox: CGRect {
        CGRect(x: drawX, y: 0, width: carSize.width, height: carSize.height)
            .insetBy(dx: -6, dy: -6)
    }

    /// Let clicks through everywhere except over the car itself. Polled from
    /// the frame loop we already run — no extra permissions, no event taps.
    private func updateClickThrough() {
        guard let window else { return }
        let local = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let overCar = carHitBox.contains(local)
        if window.ignoresMouseEvents == overCar {
            window.ignoresMouseEvents = !overCar
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard carHitBox.contains(point) else { return }
        onCarClicked?()
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard carHitBox.contains(point) else { return }
        // Right-click is the pit board: call the car in — BOX BOX — and a
        // second right-click releases it back to work.
        apply(state == .waiting ? .idle : .waiting)
    }

    /// Contact patch of a tyre, in view coordinates, accounting for facing.
    private func contactPoint(driven: Bool) -> CGPoint {
        let wheel = car.wheels.first { $0.isDriven == driven } ?? car.wheels[0]
        let localX = direction > 0
            ? wheel.center.x * scale
            : carSize.width - wheel.center.x * scale
        return CGPoint(x: drawX + localX, y: 2)
    }

    private var rearContactPoint: CGPoint { contactPoint(driven: true) }
    private var frontContactPoint: CGPoint { contactPoint(driven: false) }

    /// Engine bay in view coordinates — where a fire breaks out.
    private var engineBayPointView: CGPoint {
        let p = car.engineBayPoint
        let localX = direction > 0 ? p.x * scale : carSize.width - p.x * scale
        return CGPoint(x: drawX + localX, y: p.y * scale + idleShake)
    }

    /// Tailpipe position in view coordinates, following the car's facing.
    private var exhaustPointView: CGPoint {
        let p = car.exhaustPoint
        let localX = direction > 0 ? p.x * scale : carSize.width - p.x * scale
        return CGPoint(x: drawX + localX, y: p.y * scale + idleShake)
    }

    /// Send the car out on one lap of the entire Dock.
    private func startFullLap() {
        lapMode = .full
        fullLapReachedFarEnd = false
        direction = -1          // head away down the Dock first
    }

    // MARK: - lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if x == 0 { x = pitBoxX }
    }

    func start() {
        // NSView's display link is main-actor bound and follows whichever
        // screen the view is actually on — which matters when the Dock, and
        // therefore this window, moves between monitors.
        let link = displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    deinit {
        displayLink?.invalidate()
    }

    @objc private func tick() { step() }

    // MARK: - state

    /// Longest caption the bubble can show. The bubble wraps to three lines,
    /// so this is generous — it only guards against a whole paragraph.
    private static let maxBubbleLength = 120

    /// `Stop` fires at the end of every response, so celebrate sparingly.
    private static let victoryCooldown: CFTimeInterval = 60
    /// Rapid tool calls shouldn't each restart a full lap.
    private static let boostCooldown: CFTimeInterval = 4

    private var lastVictory: CFTimeInterval = -.greatestFiniteMagnitude
    private var lastBoost: CFTimeInterval = -.greatestFiniteMagnitude

    /// - Parameter message: optional caption — normally what Claude just did.
    ///   When absent the state's own radio call is used.
    /// How long the car keeps celebrating before it will react to something
    /// new. Without this, a prompt sent straight after a job finishes cuts the
    /// donut off mid-spin and the car snaps into a launch — which looks like a
    /// glitch rather than a celebration.
    private static let victoryHold: CFTimeInterval = 3.4

    /// An event that arrived while the car was still celebrating.
    private var pendingState: (PetState, String?)?

    func apply(_ new: PetState, message: String? = nil) {
        let now = CACurrentMediaTime()
        let caption = message.map { Self.truncate($0) }

        // Let the celebration play out, then pick up whatever arrived. Only
        // a breakdown is allowed to interrupt — that is genuinely urgent.
        if state == .victory, stateAge < Self.victoryHold, new != .idle, new != .spin {
            pendingState = (new, message)
            if let caption { bubbleText = caption }
            needsDisplay = true
            return
        }

        // A boost is an event, not a state: big cloud, then a lap of the Dock.
        if new == .boost {
            // Ignore the lap restart during a burst of tool calls, but still
            // refresh the caption so the bubble tracks what is happening.
            let onCooldown = now - lastBoost < Self.boostCooldown
            if let caption { bubbleText = caption }
            guard !onCooldown else { needsDisplay = true; return }

            lastBoost = now
            // Calm: the car stays put — the wheels just spin up hard with a
            // puff. Lively: big cloud and a lap of the whole Dock.
            boostRemaining = livelyMode ? 1.0 : 0.45
            bigSmokeRemaining = livelyMode ? 1.8 : 0.7
            bigSmokeBillow = livelyMode ? 3.4 : 1.9
            if livelyMode { velocity = max(velocity, 300) }
            tyreSpin = livelyMode ? 1 : 0.8
            if livelyMode { startFullLap() }
            if state != .racing { state = .racing; stateAge = 0 }
            needsDisplay = true
            return
        }

        // Don't donut after every one-line answer.
        if new == .victory && now - lastVictory < Self.victoryCooldown {
            apply(.idle)
            return
        }
        if new == .victory { lastVictory = now }

        state = new
        stateAge = 0
        yawAngle = 0
        wiggle = 0
        // Any new event repairs the car.
        if new != .spin { puncture = 0; engineFire = 0 }
        if new != .launch { launchSparks = 0 }
        if new != .racing { launchBurst = 0; kerbSparks = 0 }
        // Every stretch of work opens with a push lap, and work is run in
        // whole laps of the Dock rather than to a stopwatch.
        if new == .racing {
            stint = .hotLap
            stintLapsRemaining = 1
            lapMode = .full
            fullLapReachedFarEnd = false
        }

        switch new {
        case .idle:
            // Nothing left to do: fall back to naming the session, so the
            // Dock always says which conversation this car belongs to.
            bubbleText = caption ?? infoCaption ?? Self.liveSessionName()
            lapMode = .shortLane
        case .launch:
            bubbleText = caption ?? "LIGHTS OUT"
        case .racing:
            bubbleText = caption
        case .waiting:
            bubbleText = caption ?? "BOX BOX"
            lapMode = .shortLane
        case .victory:
            // Prefer what Claude actually said over a canned "P1".
            bubbleText = caption ?? Self.finishedMessage() ?? "P1 \u{1F3C1}"
            bigSmokeRemaining = livelyMode ? 2.6 : 1.0
            bigSmokeBillow = livelyMode ? 2.4 : 1.6
        case .spin:
            bubbleText = caption ?? "YELLOW FLAG"
        case .boost:
            break   // handled above; never becomes a resting state
        }
        needsDisplay = true
    }

    /// The session the hooks are watching, by name — the resting caption.
    private static func liveSessionName() -> String? {
        guard let (id, cwd) = StateChannel.readSession() else { return nil }
        if let title = StateChannel.readSessionTitle(id: id, cwd: cwd), !title.isEmpty {
            return truncate(title)
        }
        return truncate((cwd as NSString).lastPathComponent)
    }

    /// What to show when a job finishes: the first line of Claude's closing
    /// message, with a count of the steps it took to get there.
    private static func finishedMessage() -> String? {
        guard let (id, cwd) = StateChannel.readSession() else { return nil }

        let steps = Transcript.recentTools(id: id, cwd: cwd, limit: 20).count
        guard let said = Transcript.lastAssistantText(id: id, cwd: cwd) else {
            return steps > 0 ? "\u{1F3C1} done · \(steps) steps" : nil
        }

        // First sentence or line, whichever comes first.
        let firstLine = said.components(separatedBy: "\n").first ?? said
        let sentence = firstLine.components(separatedBy: ". ").first ?? firstLine
        let stepTag = steps > 0 ? "  ·  \(steps) steps" : ""
        return "\u{1F3C1} " + truncate(sentence, to: 100) + stepTag
    }

    /// Clip a caption to something that fits above the car.
    private static func truncate(_ text: String, to limit: Int = maxBubbleLength) -> String {
        let clean = text.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard clean.count > limit else { return clean }
        return clean.prefix(limit - 1) + "\u{2026}"
    }

    // MARK: - loop

    private func step() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastFrameTime, 1.0 / 30.0)   // clamp after a stall
        lastFrameTime = now
        guard !isPaused else { return }
        stateAge += dt
        let dtf = CGFloat(dt)

        boostRemaining = max(0, boostRemaining - dtf)
        bigSmokeRemaining = max(0, bigSmokeRemaining - dtf)
        launchBurst = max(0, launchBurst - dtf)
        kerbSparks = max(0, kerbSparks - dtf * 3)

        drive(dt: dtf)

        // Roll the wheels at the rate the ground passes under them, plus any
        // extra rotation from the tyres spinning up.
        let wheelRadius = (car.wheels.first?.radius ?? 5) * scale
        let travelled = velocity * dtf * direction
        x += travelled
        wheelAngle -= (travelled + tyreSpin * 700 * dtf * direction) / wheelRadius

        // Big cloud only when a tool has just run, or on the victory donut.
        // In calm mode the constantly-spinning wheels are silent — smoke only
        // accompanies an actual event, otherwise the pet would smoke all day.
        let billow: CGFloat = bigSmokeRemaining > 0 ? bigSmokeBillow : 1
        if tyreSpin > 0.02 && (livelyMode || bigSmokeRemaining > 0 || state == .launch || state == .spin) {
            var smokeOrigin = rearContactPoint
            var throwDir = -direction

            // Mid-donut the rear tyre isn't at the back of the sprite — it's
            // orbiting the car. Sweep the emission point with the yaw and
            // throw the smoke tangentially, so the cloud forms a ring around
            // the car instead of pouring out of one fixed spot.
            if state == .victory && yawAngle != 0 {
                let centreX = drawX + carSize.width / 2
                let sweep = cos(yawAngle) * carSize.width * 0.38
                smokeOrigin = CGPoint(x: centreX + sweep, y: 2)
                throwDir = sin(yawAngle) > 0 ? -1 : 1
            }

            smoke.emit(at: smokeOrigin,
                       intensity: tyreSpin,
                       backwards: throwDir,
                       dt: dtf,
                       billow: billow)
        }
        // A wisp off the fronts when they lock under braking.
        if isBraking && velocity > 90 {
            smoke.emit(at: frontContactPoint,
                       intensity: min(0.28, velocity / 800),
                       backwards: -direction,
                       dt: dtf)
        }
        // Sparks showering off the plank on the startline, and struck off
        // the floor when the car bottoms out on a push lap.
        let sparkIntensity = max(launchSparks, kerbSparks)
        if sparkIntensity > 0.01 {
            smoke.emitSparks(at: rearContactPoint,
                             intensity: sparkIntensity,
                             backwards: -direction,
                             dt: dtf)
        }
        // Thick black smoke pouring off a dying power unit, plus embers
        // carried up out of the flames.
        if engineFire > 0.01 {
            smoke.emitEngineSmoke(at: engineBayPointView, intensity: engineFire * 1.6, dt: dtf)
            smoke.emitEngineSmoke(at: CGPoint(x: exhaustPointView.x, y: exhaustPointView.y + 4),
                                  intensity: engineFire * 0.7, dt: dtf)
            smoke.emitEmbers(at: engineBayPointView, intensity: engineFire, dt: dtf)
        }
        // Exhaust, always ticking over unless the engine is off.
        if revs > 0.01 {
            smoke.emitExhaust(at: exhaustPointView,
                              backwards: -direction,
                              rate: 5 + revs * 22,
                              dt: dtf)
        }
        smoke.update(dt: dtf)

        let wantsBubble = bubbleText != nil
        bubbleAlpha += ((wantsBubble ? 1 : 0) - bubbleAlpha) * min(1, 8 * dtf)

        updateClickThrough()
        needsDisplay = true
    }

    /// Per-state driving behaviour.
    private func drive(dt: CGFloat) {
        // Calm enough to sit in your peripheral vision. This is a status light
        // that happens to be a car, not a screensaver.
        let topSpeed: CGFloat = (livelyMode ? 250 : 140) * TrackView.speedFactor
        let lane = self.lane

        // Reading the chat beats watching the car: stop dead, exactly where it
        // is, so the pinned panel stops moving the instant you open it. State
        // still advances underneath, so the lights and bubble stay live.
        if isChatOpen {
            velocity = 0
            tyreSpin = 0
            isBraking = false
            wiggle = 0
            yawAngle = 0
            idleShake = 0
            revs = 0.2
            return
        }

        switch state {
        case .idle:
            velocity += (0 - velocity) * min(1, 4 * dt)
            tyreSpin = 0
            isBraking = false
            coastTo(pitBoxX, dt: dt)
            // Ticking over gently — no shake at all, just the exhaust.
            idleShake = 0
            revs = velocity < 2 ? 0.18 : 0.3

        case .launch:
            // Lights out: sat on the line lighting up the rears and shimmying
            // against the brakes, then the clutch drops and it goes.
            let hold: CGFloat = livelyMode ? 1.4 : 0.9
            velocity = 0
            tyreSpin = livelyMode ? 0.7 : 0.45
            revs = 1
            idleShake = sin(CGFloat(stateAge) * 40) * 0.8
            wiggle = sin(CGFloat(stateAge) * 22) * (livelyMode ? 2.5 : 1.2)
            // Sparks are part of the show — lively only.
            launchSparks = livelyMode ? 0.35 + CGFloat(stateAge) / hold * 0.65 : 0

            if stateAge > hold {
                launchSparks = 0
                if livelyMode { startFullLap() }
                apply(.racing)
                if livelyMode {
                    // Zoom off: fire off the line genuinely quickly, with a
                    // long burst of extra top speed on tap. This is the one
                    // moment the car is *meant* to look fast.
                    direction = lapMode == .full ? -1 : direction
                    velocity = 520
                    boostRemaining = 1.8
                    launchBurst = 1.4
                }
            }

        case .racing:
            wiggle = 0
            idleShake = 0

            // Calm mode: the car holds its spot and the wheels spin in place,
            // like a car on a rolling road. All actual driving is lively-only.
            if !livelyMode {
                coastTo(pitBoxX, dt: dt)
                if velocity < 2 {
                    tyreSpin = boostRemaining > 0 ? 1 : 0.5
                }
                revs = 0.6 + (boostRemaining > 0 ? 0.4 : 0)
                isBraking = false
                return
            }

            revs = 0.45 + min(1, velocity / topSpeed) * 0.55
            // Sat at the end of the lane between laps.
            if dwellRemaining > 0 {
                dwellRemaining -= dt
                velocity = 0
                tyreSpin = 0
                isBraking = false
                if dwellRemaining <= 0 { turnAround() }
                return
            }

            // Hot lap / cool-down cycle, so the pace varies while Claude
            // works instead of holding one speed forever. Counted in laps —
            // see `completeLap()`.

            // A launch burst raises the ceiling well beyond a normal boost
            // and lets the car accelerate hard out of the box.
            let stintFactor: CGFloat = stint == .hotLap ? 1.45 : 0.6
            let boostFactor: CGFloat = launchBurst > 0 ? 2.6 : (boostRemaining > 0 ? 1.6 : 1)
            let ceiling = topSpeed * boostFactor * (launchBurst > 0 ? 1 : stintFactor)

            // Sparks off the plank when pushing hard — struck at random, the
            // way a real car only bottoms out over bumps and kerbs.
            if stint == .hotLap, velocity > topSpeed, random() < 3.5 * dt {
                kerbSparks = 0.5 + random() * 0.5
            }
            // Gentler than a real car would manage: sharp acceleration and
            // late braking are exactly what catches the eye.
            //
            // Acceleration scales with the speed setting, and faster than
            // linearly: at high multipliers a car that accelerated at the
            // stock rate would spend the whole Dock still winding up and never
            // reach the ceiling it was given.
            let pace = TrackView.speedFactor
            let accel: CGFloat = launchBurst > 0
                ? 1400 * pace
                : (livelyMode ? 380 : 210) * pace * pace
            let brake: CGFloat = (livelyMode ? 620 : 300) * pace * pace

            let distanceToEnd = direction > 0
                ? lane.maxX - (x + carSize.width)
                : x - lane.minX

            // Start braking exactly late enough to stop on the line.
            isBraking = distanceToEnd <= (velocity * velocity) / (2 * brake)

            if isBraking {
                velocity = max(0, velocity - brake * dt)
                tyreSpin = 0
            } else {
                velocity = min(ceiling, velocity + accel * dt)
                // Only a wisp under acceleration — the big smoke is reserved.
                tyreSpin = max(0, (ceiling - velocity) / ceiling) * 0.18
                // ...unless a tool just fired. Hold the rears lit for the
                // whole burst, otherwise wheelspin decays before the cloud
                // has had a chance to build.
                if bigSmokeRemaining > 0 { tyreSpin = max(tyreSpin, 0.9) }
            }

            if distanceToEnd <= 1.5 {
                velocity = 0
                // A long pause makes the whole thing read as occasional
                // movement rather than continuous pacing.
                dwellRemaining = stint == .hotLap ? 0.15 : (livelyMode ? 0.45 : 1.6)
            }

        case .waiting:
            tyreSpin = 0
            isBraking = false
            wiggle = 0
            coastTo(pitBoxX, dt: dt)

            // Sat in the box with the engine running: shaking on its springs,
            // and blipped every couple of seconds so it never looks frozen.
            if velocity < 2 {
                let t = CGFloat(stateAge)
                // A blip: quick swell in revs roughly every 2.4s.
                let phase = t.truncatingRemainder(dividingBy: 2.4)
                revs = phase < 0.35 ? 0.35 + sin(phase / 0.35 * .pi) * 0.65 : 0.3
                // Only shake while it is actually being revved. A constant
                // shake reads as buzzing, because pixel snapping turns any
                // amplitude into a full 1pt jump.
                idleShake = revs > 0.75 ? sin(t * 30) * 0.8 : 0
                // The blip rocks the car back on its rear suspension.
                wiggle = revs > 0.7 ? -(revs - 0.7) * 2.5 : 0
            } else {
                idleShake = 0
                revs = 0.35
            }

        case .victory:
            // Calm mode: no donut — a celebratory wheelspin in place, then
            // settle. The donut is lively-only.
            if !livelyMode {
                velocity = 0
                yawAngle = 0
                wiggle = 0
                tyreSpin = stateAge < 1.2 ? 0.8 : 0
                if stateAge > Self.victoryHold {
                    if let (next, message) = pendingState {
                        pendingState = nil
                        apply(next, message: message)
                    } else {
                        apply(.idle)
                    }
                }
                return
            }

            // Donut: held on the spot, spinning, smoke everywhere.
            velocity = 0
            tyreSpin = 1
            wiggle = sin(CGFloat(stateAge) * 14) * 1.5
            if stateAge < 2.6 {
                // Eased, not constant: the car has to break traction and wind
                // the spin up, and it runs out of momentum at the end.
                let t = CGFloat(stateAge)
                let windUp = min(1, t / 0.45)
                let windDown = min(1, max(0, (2.6 - t) / 0.5))
                let rate = 8.5 * windUp * windUp * (0.3 + 0.7 * windDown)
                yawAngle += rate * dt
                // Weight rocking over the outside tyres, twice per revolution.
                idleShake = sin(yawAngle * 2) * 0.7
            } else {
                // Donut done: roll back to the pit box at its home end and
                // stop there, so the car is parked where the chat panel opens
                // rather than stranded mid-Dock.
                yawAngle = 0
                tyreSpin = 0
                coastTo(pitBoxX, dt: dt)
                if stateAge > Self.victoryHold {
                    if let (next, message) = pendingState {
                        pendingState = nil
                        apply(next, message: message)
                    } else {
                        apply(.idle)
                    }
                }
            }

        case .spin:
            // A failure is a breakdown, not a spin-and-recover: the car stops
            // dead where it was, blows a rear tyre, and sits there smoking.
            // It stays broken until something else happens, so a failure you
            // walked away from is still visible when you come back.
            velocity = max(0, velocity - 900 * dt)
            let t = CGFloat(stateAge)
            tyreSpin = max(0, 0.5 - t)                  // brief lock-up, then nothing
            puncture = min(1, t / 0.7)                  // tyre lets go quickly
            // Flares up fast, then settles into a long steady burn rather than
            // guttering out — a retired car sits there smoking for a while.
            engineFire = t < 0.5 ? t / 0.5 : max(0.8, 1 - (t - 0.5) / 30)
            revs = max(0, 0.35 - t * 0.2)               // engine dies
            idleShake = t < 1.2 ? sin(t * 45) * 0.9 : 0 // death throes
            wiggle = 0
            isBraking = false

        case .boost:
            break   // never a resting state
        }
    }

    /// Turn the car round at the end of a lane.
    ///
    /// A lap is the length of the Dock and back: it is retired when the car
    /// returns to its home end having already been to the far one.
    private func turnAround() {
        let atHomeEnd = (pitHome == .left) == (direction < 0)
        if atHomeEnd {
            if fullLapReachedFarEnd {
                fullLapReachedFarEnd = false
                completeLap()
            }
        } else {
            fullLapReachedFarEnd = true
        }
        direction *= -1
    }

    /// One lap of the Dock done. While Claude is working this drives the
    /// hot-lap / cool-down cycle; otherwise it sends the car back to its
    /// corner.
    private func completeLap() {
        guard state == .racing else {
            lapMode = .shortLane            // one lap out was the whole point
            return
        }

        stintLapsRemaining -= 1
        guard stintLapsRemaining <= 0 else { return }

        if stint == .hotLap {
            stint = .coolDown
            stintLapsRemaining = 1          // a cool-down is always one lap
        } else {
            stint = .hotLap
            stintLapsRemaining = 1 + Int(random() * 2)   // one or two push laps
            boostRemaining = max(boostRemaining, 0.7)    // start it with a shove
        }
    }

    /// Ease towards a parking spot and stop cleanly on it.
    private func coastTo(_ target: CGFloat, dt: CGFloat) {
        let gap = target - x
        if abs(gap) < 1.5 {
            x = target
            velocity = 0
            // Park facing back down the Dock, not nose-first into the edge.
            direction = pitHome == .right ? -1 : 1
            return
        }
        direction = gap > 0 ? 1 : -1
        velocity = min(300, abs(gap) * 3.2)
    }

    // MARK: - drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)

        if showsTrackOutline {
            ctx.setStrokeColor(NSColor.systemYellow.withAlphaComponent(0.7).cgColor)
            ctx.setLineWidth(2)
            ctx.stroke(CGRect(x: lane.minX, y: 0,
                              width: lane.maxX - lane.minX, height: bounds.height))
        }

        // Smoke sits behind the car so the bodywork stays readable.
        smoke.draw(in: ctx)

        guard let sprite = CarRenderer.image(for: car,
                                             wheelAngle: wheelAngle,
                                             facingRight: direction > 0,
                                             wheelSpin: tyreSpin,
                                             deflation: puncture,
                                             detail: scale)
        else { return }

        let rect = CGRect(x: drawX.rounded(), y: idleShake.rounded(),
                          width: carSize.width, height: carSize.height)

        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)

        if yawAngle != 0 {
            // Donut. Spinning about the vertical axis means the side view just
            // squashes horizontally: cos goes to 0 edge-on, then negative,
            // which flips the sprite so the car comes round facing the other
            // way. Far more convincing than rotating the sprite in-plane.
            //
            // Clamped away from zero — at exactly edge-on the car would vanish
            // for a frame, which reads as flicker rather than rotation.
            var squash = cos(yawAngle)
            let minSquash: CGFloat = 0.14
            if abs(squash) < minSquash {
                squash = squash < 0 ? -minSquash : minSquash
            }
            ctx.saveGState()
            ctx.translateBy(x: rect.midX, y: rect.midY)
            ctx.scaleBy(x: squash, y: 1)
            ctx.translateBy(x: -rect.midX, y: -rect.midY)
            ctx.draw(sprite, in: rect)
            ctx.restoreGState()
        } else {
            ctx.draw(sprite, in: rect)
        }

        if engineFire > 0.01 { drawFire(in: ctx) }

        // Only flash the brake light when there is real speed to shed —
        // otherwise it blinks at every turnaround and draws the eye.
        if isBraking && velocity > 90 { drawBrakeLight(in: ctx) }

        // Stationary cars run their rain light, like a car sat on the grid
        // before the start. Waiting flashes hard and fast because that is the
        // one moment the pet is *supposed* to grab your attention; idle just
        // pulses slowly so you can tell it is alive.
        if velocity < 3 && (state == .idle || state == .waiting) && !isBraking {
            let urgent = (state == .waiting)
            let blink = sin(CGFloat(stateAge) * (urgent ? 11 : 3.4))
            let lit = urgent ? blink > -0.2 : blink > 0.35
            if lit {
                drawBrakeLight(in: ctx, intensity: urgent ? 0.65 + blink * 0.35 : 0.5)
            }
        }

        if bubbleAlpha > 0.01, let text = bubbleText {
            drawBubble(text, alpha: bubbleAlpha)
        } else {
            lastBubbleRect = nil
        }
    }

    /// The rain light on the back of the car, lit under braking and flashed
    /// while waiting in the box.
    private func drawBrakeLight(in ctx: CGContext, intensity: CGFloat = 1) {
        let cx = direction > 0 ? drawX + 6 : drawX + carSize.width - 6
        let cy = carSize.height * 0.42

        ctx.setShouldAntialias(true)
        for (radius, alpha) in [(11.0, 0.18), (6.5, 0.34), (3.0, 0.95)] {
            ctx.setFillColor(NSColor(srgbRed: 1, green: 0.12, blue: 0.10,
                                     alpha: alpha * intensity).cgColor)
            let r = radius * (0.8 + intensity * 0.2)
            ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        }
        ctx.setShouldAntialias(false)
    }

    /// Engine fire: a few flickering blobs stacked warm-to-cool, with the
    /// flicker driven off different frequencies so it never looks like a
    /// pulsing circle.
    private func drawFire(in ctx: CGContext) {
        let t = CGFloat(stateAge)
        ctx.setShouldAntialias(true)

        // Two seats of fire — the engine bay and the exhaust behind it — so it
        // reads as a car properly ablaze rather than one pulsing blob.
        let seats: [(CGPoint, CGFloat)] = [
            (engineBayPointView, 1.0),
            (CGPoint(x: exhaustPointView.x, y: exhaustPointView.y + 4), 0.62),
        ]

        let layers: [(CGFloat, NSColor, CGFloat)] = [
            (16.0, NSColor(srgbRed: 0.85, green: 0.15, blue: 0.02, alpha: 0.30),  9),
            (11.0, NSColor(srgbRed: 0.95, green: 0.30, blue: 0.04, alpha: 0.50), 13),
            ( 7.0, NSColor(srgbRed: 1.00, green: 0.55, blue: 0.08, alpha: 0.78), 19),
            ( 3.6, NSColor(srgbRed: 1.00, green: 0.90, blue: 0.55, alpha: 0.98), 27),
        ]

        for (origin, scale) in seats {
            for (i, layer) in layers.enumerated() {
                let (base, color, freq) = layer
                let flicker = 0.72 + 0.28 * sin(t * freq + CGFloat(i) * 1.7 + origin.x * 0.1)
                let r = base * flicker * engineFire * scale
                let lift = CGFloat(i) * 2.4 + sin(t * (freq * 0.6)) * 1.2
                ctx.setFillColor(color.cgColor)
                ctx.fillEllipse(in: CGRect(x: origin.x - r * 0.62,
                                           y: origin.y - r * 0.6 + lift,
                                           width: r * 1.24, height: r * 2.1))
            }
        }
        ctx.setShouldAntialias(false)
    }

    /// Pit-wall radio call, floating above the car. Wraps to at most three
    /// lines so a real sentence from Claude fits without becoming a banner.
    private func drawBubble(_ text: String, alpha: CGFloat) {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.lineSpacing = 1

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(alpha),
            .paragraphStyle: paragraph,
        ]
        let string = NSAttributedString(string: text, attributes: attrs)

        // Measure with a wrap width, then cap the height at three lines.
        let maxWidth = min(bounds.width - 24, 320)
        let lineHeight = font.boundingRectForFont.height + paragraph.lineSpacing
        let measured = string.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                                           options: [.usesLineFragmentOrigin, .usesFontLeading])
        let textW = min(ceil(measured.width), maxWidth)
        let textH = min(ceil(measured.height), ceil(lineHeight * 3))

        let padding: CGFloat = 8
        let boxW = textW + padding * 2
        let boxH = textH + padding * 1.4
        var boxX = drawX + carSize.width / 2 - boxW / 2
        boxX = max(bounds.minX + 2, min(boxX, bounds.maxX - boxW - 2))
        let boxY = carSize.height + 8

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setShouldAntialias(true)

        let box = CGRect(x: boxX, y: boxY, width: boxW, height: boxH)
        lastBubbleRect = box
        let boxPath = CGPath(roundedRect: box, cornerWidth: 6, cornerHeight: 6, transform: nil)
        ctx.setFillColor(Theme.bubbleBackground.withAlphaComponent(0.88 * alpha).cgColor)
        ctx.addPath(boxPath)
        ctx.fillPath()
        ctx.setStrokeColor(Theme.accent.withAlphaComponent(0.55 * alpha).cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(boxPath)
        ctx.strokePath()

        // Tail pointing down at the car.
        let tail = CGMutablePath()
        let tipX = min(max(drawX + carSize.width / 2, box.minX + 10), box.maxX - 10)
        tail.polygon([pt(tipX - 5, boxY + 1), pt(tipX + 5, boxY + 1), pt(tipX, boxY - 6)])
        ctx.setFillColor(Theme.bubbleBackground.withAlphaComponent(0.88 * alpha).cgColor)
        ctx.addPath(tail)
        ctx.fillPath()

        string.draw(with: CGRect(x: box.minX + padding, y: box.minY + padding * 0.7,
                                 width: textW, height: textH),
                    options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}
