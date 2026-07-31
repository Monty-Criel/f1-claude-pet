import AppKit

/// Tyre smoke, drawn in screen space rather than baked into the sprite so it
/// can billow well beyond the car's own bounds.
struct SmokeSystem {

    /// Sparks need different physics from smoke — they fall rather than rise,
    /// keep their momentum instead of dissipating, and are drawn as bright
    /// streaks rather than soft blobs.
    enum Kind { case smoke, spark }

    struct Particle {
        var position: CGPoint
        var velocity: CGVector
        var radius: CGFloat
        var life: CGFloat          // 1 at birth, 0 when it should be removed
        var decay: CGFloat
        var shade: CGFloat         // 0 = dark rubber, 1 = white smoke
        var kind: Kind = .smoke
    }

    private(set) var particles: [Particle] = []

    /// Cap the population so a long burnout can't tank the frame rate.
    private let maxParticles = 260

    /// Deterministic-ish jitter without pulling in a RNG dependency.
    private var seed: UInt64 = 0x9E3779B97F4A7C15

    private mutating func random() -> CGFloat {
        seed ^= seed << 13
        seed ^= seed >> 7
        seed ^= seed << 17
        return CGFloat(seed % 10_000) / 10_000
    }

    /// Emit smoke from a spinning tyre.
    /// - Parameters:
    ///   - origin: contact patch, in view coordinates.
    ///   - intensity: 0…1, scales both the spawn rate and how far it throws.
    ///   - backwards: direction the smoke is thrown, opposite to travel.
    ///   - billow: multiplier on volume and throw. 1 is a normal burnout;
    ///     push it up for the big cloud when a tool fires.
    mutating func emit(at origin: CGPoint,
                       intensity: CGFloat,
                       backwards: CGFloat,
                       dt: CGFloat,
                       billow: CGFloat = 1) {
        guard intensity > 0.01 else { return }

        let rate = 42 * intensity * billow
        var toSpawn = Int(rate * dt)
        if random() < (rate * dt) - CGFloat(Int(rate * dt)) { toSpawn += 1 }

        for _ in 0..<toSpawn {
            guard particles.count < maxParticles else { break }
            // Tight to the contact patch rather than a wide cloud.
            let spread = (random() - 0.5) * 7 * billow
            particles.append(Particle(
                position: CGPoint(x: origin.x + spread, y: origin.y + random() * 2),
                velocity: CGVector(dx: backwards * (8 + random() * 24) * intensity * billow,
                                   dy: (6 + random() * 16) * billow),
                radius: (1.6 + random() * 2.4) * billow,
                life: 1,
                decay: 0.85 + random() * 0.55,
                shade: 0.62 + random() * 0.3
            ))
        }
    }

    /// A small puff out of the tailpipe. Much finer and shorter-lived than
    /// tyre smoke, and it drifts up rather than being thrown backwards.
    mutating func emitExhaust(at origin: CGPoint, backwards: CGFloat, rate: CGFloat, dt: CGFloat) {
        var toSpawn = Int(rate * dt)
        if random() < (rate * dt) - CGFloat(Int(rate * dt)) { toSpawn += 1 }

        for _ in 0..<toSpawn {
            guard particles.count < maxParticles else { break }
            particles.append(Particle(
                position: CGPoint(x: origin.x, y: origin.y + (random() - 0.5) * 2),
                velocity: CGVector(dx: backwards * (10 + random() * 14),
                                   dy: 9 + random() * 12),
                radius: 1 + random() * 1.4,
                life: 1,
                decay: 1.7 + random() * 0.9,
                shade: 0.35 + random() * 0.3
            ))
        }
    }

    /// Thick, dark, slow smoke pouring out of a dying engine. Rises rather than
    /// being thrown, and is much darker than tyre smoke so a failure reads as
    /// something going wrong rather than as a burnout.
    mutating func emitEngineSmoke(at origin: CGPoint, intensity: CGFloat, dt: CGFloat) {
        guard intensity > 0.01 else { return }
        let rate = 34 * intensity
        var toSpawn = Int(rate * dt)
        if random() < (rate * dt) - CGFloat(Int(rate * dt)) { toSpawn += 1 }

        for _ in 0..<toSpawn {
            guard particles.count < maxParticles else { break }
            particles.append(Particle(
                position: CGPoint(x: origin.x + (random() - 0.5) * 5, y: origin.y),
                velocity: CGVector(dx: (random() - 0.5) * 14, dy: 20 + random() * 22),
                radius: 2 + random() * 3,
                life: 1,
                decay: 0.42 + random() * 0.3,
                shade: random() * 0.22          // near-black
            ))
        }
    }

    /// Sparks off the plank and the rear tyres as the clutch drops.
    mutating func emitSparks(at origin: CGPoint, intensity: CGFloat, backwards: CGFloat, dt: CGFloat) {
        guard intensity > 0.01 else { return }
        let rate = 70 * intensity
        var toSpawn = Int(rate * dt)
        if random() < (rate * dt) - CGFloat(Int(rate * dt)) { toSpawn += 1 }

        for _ in 0..<toSpawn {
            guard particles.count < maxParticles else { break }
            particles.append(Particle(
                position: CGPoint(x: origin.x + (random() - 0.5) * 10, y: origin.y + random() * 2),
                velocity: CGVector(dx: backwards * (40 + random() * 130),
                                   dy: 25 + random() * 70),
                radius: 0.7 + random() * 0.9,
                life: 1,
                decay: 1.6 + random() * 1.2,
                shade: 0.6 + random() * 0.4,
                kind: .spark
            ))
        }
    }

    /// Embers rising out of a fire: sparks that drift upward on the heat
    /// before gravity wins, rather than being thrown backwards.
    mutating func emitEmbers(at origin: CGPoint, intensity: CGFloat, dt: CGFloat) {
        guard intensity > 0.01 else { return }
        let rate = 26 * intensity
        var toSpawn = Int(rate * dt)
        if random() < (rate * dt) - CGFloat(Int(rate * dt)) { toSpawn += 1 }

        for _ in 0..<toSpawn {
            guard particles.count < maxParticles else { break }
            particles.append(Particle(
                position: CGPoint(x: origin.x + (random() - 0.5) * 8, y: origin.y + random() * 4),
                velocity: CGVector(dx: (random() - 0.5) * 26, dy: 55 + random() * 60),
                radius: 0.6 + random() * 0.8,
                life: 1,
                decay: 0.85 + random() * 0.6,
                shade: 0.5 + random() * 0.5,
                kind: .spark
            ))
        }
    }

    mutating func update(dt: CGFloat) {
        for i in particles.indices {
            particles[i].position.x += particles[i].velocity.dx * dt
            particles[i].position.y += particles[i].velocity.dy * dt

            if particles[i].kind == .spark {
                // Ballistic: gravity, little drag, no swelling.
                particles[i].velocity.dy -= 320 * dt
                particles[i].velocity.dx *= (1 - 0.9 * dt)
            } else {
                // Smoke slows and swells as it dissipates.
                particles[i].velocity.dx *= (1 - 1.6 * dt)
                particles[i].velocity.dy *= (1 - 0.9 * dt)
                particles[i].radius += 16 * dt
            }
            particles[i].life -= particles[i].decay * dt
        }
        particles.removeAll { $0.life <= 0 }
    }

    func draw(in ctx: CGContext) {
        for p in particles {
            switch p.kind {
            case .smoke:
                // Ease the fade so puffs linger then vanish, rather than
                // blinking out.
                let alpha = max(0, p.life * p.life) * 0.5
                // Pixel-art puffs: squares snapped to the same 2pt grid as the
                // car sprite, so the smoke matches the artwork instead of
                // looking like soft photographic circles behind pixel art.
                let grid: CGFloat = 2
                func snap(_ v: CGFloat) -> CGFloat { (v / grid).rounded() * grid }
                let r = max(grid, snap(p.radius))
                let x = snap(p.position.x)
                let y = snap(p.position.y)

                // A darker rim one pixel proud of the puff. Light smoke over a
                // white window would otherwise vanish; the rim gives it an
                // edge on any background without darkening the smoke itself.
                // Skipped for near-black smoke, which needs no help.
                if p.shade > 0.3 {
                    ctx.setFillColor(NSColor(white: max(0, p.shade - 0.5),
                                             alpha: alpha * 0.5).cgColor)
                    ctx.fill(CGRect(x: x - r - grid, y: y - r - grid,
                                    width: (r + grid) * 2, height: (r + grid) * 2))
                }

                // The stored shade IS the grey level — re-mapping it here was
                // washing everything out, including the engine fire's
                // supposedly near-black smoke.
                ctx.setFillColor(NSColor(white: p.shade, alpha: alpha).cgColor)
                ctx.fill(CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))

                // Cauliflower lobes on the bigger puffs. Deterministic per
                // particle — from its shade, not a RNG — so lobes don't dance
                // frame to frame.
                if r >= 4 {
                    let lobe = max(grid, snap(r * 0.6))
                    let side: CGFloat = p.shade > 0.75 ? 1 : -1
                    ctx.fill(CGRect(x: x + side * r - lobe / 2, y: y + r - lobe / 2,
                                    width: lobe, height: lobe))
                    ctx.fill(CGRect(x: x - side * r - lobe / 2, y: y + r * 0.3,
                                    width: lobe, height: lobe))
                }

            case .spark:
                // Bright, hot, and drawn as a short streak along its own
                // direction of travel so it reads as a flying ember.
                let alpha = max(0, p.life)
                let heat = p.shade
                ctx.setFillColor(NSColor(srgbRed: 1,
                                         green: 0.55 + heat * 0.35,
                                         blue: 0.10 + heat * 0.25,
                                         alpha: alpha).cgColor)
                let len = max(1.5, min(6, abs(p.velocity.dx) * 0.02))
                let dir: CGFloat = p.velocity.dx < 0 ? -1 : 1
                ctx.fill(CGRect(x: p.position.x - (dir > 0 ? 0 : len),
                                y: p.position.y - p.radius,
                                width: len,
                                height: p.radius * 2))
            }
        }
    }

    mutating func clear() { particles.removeAll() }

    var isEmpty: Bool { particles.isEmpty }
}
