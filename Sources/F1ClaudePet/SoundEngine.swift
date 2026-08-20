import AVFoundation

/// Synthesised sound effects, tuned against the real F1 broadcast signature.
///
/// Everything is generated in-process — there are no audio assets and nothing
/// to license. The radio call reproduces the actual chain a team-radio message
/// passes through: a voice, band-limited to the walkie-talkie band, pushed
/// through Apple's radio-transmission distortion, sat on a bed of hiss, and
/// book-ended by squelch chirps. The launch is an additive engine model with
/// two audible upshifts and a turbo whistle, not a slide-whistle sweep.
///
/// The honest limit: the voice is a speech synthesiser, so it sounds like a
/// radio message from a robot engineer, convincingly — but it is not a
/// recorded human. Real recordings would need licensed assets.
@MainActor
final class SoundEngine {

    static let shared = SoundEngine()

    /// On by default — it was asked for — and one menu click to silence.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "soundEffects") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "soundEffects") }
    }

    /// Menu-slider volume, applied to the mixer. Defaults quiet on purpose:
    /// the pet lives in your peripheral vision, not your headphones.
    static var volume: Float {
        get {
            let stored = UserDefaults.standard.object(forKey: "soundVolume") as? Double
            return Float(min(1.0, max(0.0, stored ?? 0.3)))
        }
        set { UserDefaults.standard.set(Double(min(1, max(0, newValue))), forKey: "soundVolume") }
    }

    /// Live-applies the current volume; safe before the engine has started.
    func applyVolume() {
        if started { engine.mainMixerNode.outputVolume = Self.volume }
    }

    nonisolated static let sampleRate: Double = 44_100
    private static var format: AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var started = false

    private var launchBuffer: AVAudioPCMBuffer?
    private var radioBuffer: AVAudioPCMBuffer?
    private var victoryBuffer: AVAudioPCMBuffer?
    private var preparing = false
    /// The victory burnout fires on every Stop event; the clip only plays as
    /// often as the donut does.
    private var lastVictorySound: Date = .distantPast

    // MARK: - playback

    func play(for state: PetState) {
        guard Self.isEnabled else { return }
        switch state {
        case .launch:  play(bufferFor: .launch)
        case .waiting: play(bufferFor: .radio)
        case .victory:
            guard Date().timeIntervalSince(lastVictorySound) > 60 else { return }
            lastVictorySound = Date()
            play(bufferFor: .victory)
        default:       break
        }
    }

    enum Clip: String { case launch, radio, victory }

    private func play(bufferFor clip: Clip) {
        prepareIfNeeded()
        let buffer: AVAudioPCMBuffer? = switch clip {
        case .launch:  launchBuffer
        case .radio:   radioBuffer
        case .victory: victoryBuffer
        }
        guard let buffer else { return }      // still synthesising: skip quietly

        if !started {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: Self.format)
            engine.mainMixerNode.outputVolume = Self.volume
            guard (try? engine.start()) != nil else { return }
            started = true
        }
        engine.mainMixerNode.outputVolume = Self.volume
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    /// Build both clips off the main thread, once. The radio voice needs the
    /// speech synthesiser and an offline effects render, which takes ~a second
    /// — so it happens in the background at first use and is cached.
    private func prepareIfNeeded() {
        guard launchBuffer == nil || radioBuffer == nil, !preparing else { return }
        preparing = true
        Task.detached(priority: .utility) {
            // Real recordings first — a 1996 Williams V10 launch and a 2006
            // Red Bull V10 burnout (CC BY-SA, see Resources/Sounds/CREDITS.md)
            // — with the synthesised engine as the no-assets fallback.
            let launch = SoundSynth.bundledClip("launch") ?? SoundSynth.launchClip()
            let victory = SoundSynth.bundledClip("victory")
            let radio = SoundSynth.radioClip()
            await MainActor.run {
                self.launchBuffer = launch
                self.victoryBuffer = victory
                self.radioBuffer = radio
                self.preparing = false
            }
        }
    }

    /// Called at startup so the first real event doesn't play late.
    func warmUp() { prepareIfNeeded() }
}

/// The actual synthesis — pure functions over sample arrays, so the CLI can
/// export the same clips to WAV for auditioning (`pet sound radio|launch`).
enum SoundSynth {

    static let sampleRate: Double = 44_100

    /// A bundled recording, mono, in the engine's working format. The app
    /// bundle carries them under Resources/Sounds; the bare CLI binary has no
    /// bundle and falls back to synthesis.
    static func bundledClip(_ name: String) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "m4a",
                                        subdirectory: "Sounds")
            ?? Bundle.main.url(forResource: name, withExtension: "m4a")
        else { return nil }
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        guard let raw = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                         frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: raw)) != nil
        else { return nil }

        let target = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        if raw.format == target { return raw }
        guard let converter = AVAudioConverter(from: raw.format, to: target),
              let out = AVAudioPCMBuffer(pcmFormat: target,
                                         frameCapacity: AVAudioFrameCount(
                                            Double(raw.frameLength)
                                            * sampleRate / raw.format.sampleRate + 1024))
        else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return raw
        }
        return error == nil ? out : nil
    }

    // MARK: - launch: a V10 pull with two upshifts

    static func launchClip() -> AVAudioPCMBuffer? {
        let duration = 1.35
        let n = Int(duration * sampleRate)
        var samples = [Float](repeating: 0, count: n)

        // The rev curve: three pulls with two gear drops between them.
        // (startT, endT, startHz, endHz) — firing frequency, not RPM. A V10
        // fires five times per rev, so nearing the limiter the fundamental
        // sits over a kilohertz: that is the scream. No turbo — these were
        // naturally aspirated, which is exactly why they sing.
        let gears: [(Double, Double, Double, Double)] = [
            (0.00, 0.50, 330, 950),
            (0.50, 0.90, 640, 1180),
            (0.90, 1.35, 820, 1420),
        ]

        var phaseA = 0.0
        var phaseB = 0.0
        var rng: UInt64 = 0x9E3779B97F4A7C15

        for i in 0..<n {
            let t = Double(i) / sampleRate
            guard let gear = gears.first(where: { t >= $0.0 && t < $0.1 })
                ?? gears.last else { continue }
            let f = gear.2 + (gear.3 - gear.2) * (t - gear.0) / (gear.1 - gear.0)

            // Two voices, slightly detuned — the exhaust-bank beating that
            // makes a V10 shimmer instead of buzzing like a synth.
            phaseA += f / sampleRate
            phaseB += f * 1.013 / sampleRate

            var v = 0.0
            for k in 1...7 {
                // Bright weighting: the upper harmonics roll off slowly, which
                // is where the scream lives; keep them under Nyquist.
                guard f * Double(k) * 1.05 < sampleRate / 2 else { break }
                let w = 1.0 / pow(Double(k), 0.72)
                v += w * sin(2 * .pi * phaseA * Double(k))
                v += w * 0.55 * sin(2 * .pi * phaseB * Double(k))
            }
            v /= 5.6

            // Mechanical/intake noise bed — thinner than the turbo car's.
            rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
            let noise = Double(Int64(bitPattern: rng % 2000) - 1000) / 1000.0
            v += noise * 0.045

            // Envelope: sharp in, a lift at each shift, tail out.
            var env = min(1.0, t / 0.03) * min(1.0, (duration - t) / 0.25)
            for shift in [0.50, 0.90] where abs(t - shift) < 0.03 {
                env *= 0.30 + 0.70 * abs(t - shift) / 0.03   // the lift-off blip
            }
            samples[i] = Float(v * env)
        }
        return buffer(from: samples)
    }

    // MARK: - radio: the transmission squelch, voice-free

    /// Just the click-click of a radio keying open and closed. The earlier
    /// synthesised "box box" voice is gone by request — a speech synthesiser
    /// through a radio filter is still a speech synthesiser.
    static func radioClip() -> AVAudioPCMBuffer? {
        var assembled: [Float] = []
        assembled.append(contentsOf: squelch())
        assembled.append(contentsOf: [Float](repeating: 0, count: Int(0.16 * sampleRate)))
        assembled.append(contentsOf: squelch())
        return buffer(from: assembled)
    }

    /// The broadcast squelch: a short shaped chirp with a noise splash.
    private static func squelch() -> [Float] {
        let n = Int(0.07 * sampleRate)
        var out = [Float](repeating: 0, count: n)
        var rng: UInt64 = 0xDEADBEEFCAFE
        for i in 0..<n {
            let t = Double(i) / sampleRate
            let env = exp(-t * 55)
            rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
            let noise = Double(Int64(bitPattern: rng % 2000) - 1000) / 1000.0
            out[i] = Float((sin(2 * .pi * 1750 * t) * 0.8 + noise * 0.5) * env * 0.5)
        }
        return out
    }

    // MARK: - plumbing

    private static func buffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count))
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer {
            buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count)
        }
        return buffer
    }

    private static func append(_ chunk: AVAudioPCMBuffer, to target: AVAudioPCMBuffer) {
        guard let src = chunk.floatChannelData, let dst = target.floatChannelData else { return }
        let offset = Int(target.frameLength)
        let count = Int(chunk.frameLength)
        guard offset + count <= Int(target.frameCapacity) else { return }
        dst[0].advanced(by: offset).update(from: src[0], count: count)
        target.frameLength += AVAudioFrameCount(count)
    }

    /// WAV export for the audition loop.
    static func export(_ clip: SoundEngine.Clip, to path: String) -> Bool {
        let buffer: AVAudioPCMBuffer?
        switch clip {
        case .launch:  buffer = bundledClip("launch") ?? launchClip()
        case .radio:   buffer = radioClip()
        case .victory: buffer = bundledClip("victory")
        }
        guard let buffer,
              let file = try? AVAudioFile(
                forWriting: URL(fileURLWithPath: path),
                settings: buffer.format.settings,
                commonFormat: .pcmFormatFloat32, interleaved: false)
        else { return false }
        return (try? file.write(from: buffer)) != nil
    }
}
