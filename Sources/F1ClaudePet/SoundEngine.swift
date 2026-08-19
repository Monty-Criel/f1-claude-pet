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

    nonisolated static let sampleRate: Double = 44_100
    private static var format: AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var started = false

    private var launchBuffer: AVAudioPCMBuffer?
    private var radioBuffer: AVAudioPCMBuffer?
    private var preparing = false

    // MARK: - playback

    func play(for state: PetState) {
        guard Self.isEnabled else { return }
        switch state {
        case .launch:  play(bufferFor: .launch)
        case .waiting: play(bufferFor: .radio)
        default:       break
        }
    }

    enum Clip: String { case launch, radio }

    private func play(bufferFor clip: Clip) {
        prepareIfNeeded()
        let buffer = clip == .launch ? launchBuffer : radioBuffer
        guard let buffer else { return }      // still synthesising: skip quietly

        if !started {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: Self.format)
            engine.mainMixerNode.outputVolume = 0.3
            guard (try? engine.start()) != nil else { return }
            started = true
        }
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
            let launch = SoundSynth.launchClip()
            let radio = SoundSynth.radioClip()
            await MainActor.run {
                self.launchBuffer = launch
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

    // MARK: - launch: a V6 pull with two upshifts

    static func launchClip() -> AVAudioPCMBuffer? {
        let duration = 1.35
        let n = Int(duration * sampleRate)
        var samples = [Float](repeating: 0, count: n)

        // The rev curve: three pulls with two gear drops between them.
        // (startT, endT, startHz, endHz) — firing frequency, not RPM.
        let gears: [(Double, Double, Double, Double)] = [
            (0.00, 0.50, 95, 290),
            (0.50, 0.90, 200, 330),
            (0.90, 1.35, 240, 370),
        ]

        var phase = 0.0
        var whistlePhase = 0.0
        var rng: UInt64 = 0x9E3779B97F4A7C15

        for i in 0..<n {
            let t = Double(i) / sampleRate
            guard let gear = gears.first(where: { t >= $0.0 && t < $0.1 })
                ?? gears.last else { continue }
            let f = gear.2 + (gear.3 - gear.2) * (t - gear.0) / (gear.1 - gear.0)

            phase += f / sampleRate
            // Additive engine note: sawtooth-weighted harmonics, odd ones
            // boosted — the raspy V6 character rather than a smooth buzz.
            var v = 0.0
            for k in 1...9 {
                let w = 1.0 / Double(k) * (k % 2 == 1 ? 1.35 : 0.75)
                v += w * sin(2 * .pi * phase * Double(k))
            }
            v /= 4.2

            // Turbo whistle: thin, high, sweeping with the pull.
            whistlePhase += (1800 + f * 14) / sampleRate
            v += 0.045 * sin(2 * .pi * whistlePhase)

            // Intake / tyre noise bed.
            rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
            let noise = Double(Int64(bitPattern: rng % 2000) - 1000) / 1000.0
            v += noise * 0.06

            // Envelope: sharp in, small dip at each shift, tail out.
            var env = min(1.0, t / 0.03) * min(1.0, (duration - t) / 0.25)
            for shift in [0.50, 0.90] where abs(t - shift) < 0.03 {
                env *= 0.35 + 0.65 * abs(t - shift) / 0.03   // the lift-off blip
            }
            samples[i] = Float(v * env)
        }
        return buffer(from: samples)
    }

    // MARK: - radio: squelch, band-limited voice, squelch

    static func radioClip() -> AVAudioPCMBuffer? {
        let open = squelch()
        let close = squelch()
        let voice = radioVoice() ?? []
        var assembled: [Float] = []
        assembled.append(contentsOf: open)
        assembled.append(contentsOf: [Float](repeating: 0, count: Int(0.06 * sampleRate)))
        assembled.append(contentsOf: voice)
        assembled.append(contentsOf: [Float](repeating: 0, count: Int(0.05 * sampleRate)))
        assembled.append(contentsOf: close)
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

    /// "Box box, box box" — synthesised, then pushed through the radio chain:
    /// band-limit to ~300–3000 Hz, Apple's `.speechRadioTower` distortion, and
    /// a hiss bed underneath.
    private static func radioVoice() -> [Float]? {
        guard let raw = capturedSpeech() else { return nil }

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let eq = AVAudioUnitEQ(numberOfBands: 2)
        let distortion = AVAudioUnitDistortion()

        eq.bands[0].filterType = .highPass
        eq.bands[0].frequency = 320
        eq.bands[0].bypass = false
        eq.bands[1].filterType = .lowPass
        eq.bands[1].frequency = 2900
        eq.bands[1].bypass = false
        distortion.loadFactoryPreset(.speechRadioTower)
        distortion.wetDryMix = 55

        engine.attach(player); engine.attach(eq); engine.attach(distortion)
        engine.connect(player, to: eq, format: format)
        engine.connect(eq, to: distortion, format: format)
        engine.connect(distortion, to: engine.mainMixerNode, format: format)

        do {
            try engine.enableManualRenderingMode(.offline, format: format,
                                                 maximumFrameCount: 4096)
            try engine.start()
        } catch { return nil }

        player.scheduleBuffer(raw, at: nil)
        player.play()

        let total = AVAudioFrameCount(raw.frameLength) + AVAudioFrameCount(0.2 * sampleRate)
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total)
        else { return nil }

        while out.frameLength < total {
            let toRender = min(4096, total - out.frameLength)
            guard let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: toRender),
                  (try? engine.renderOffline(toRender, to: chunk)) == .success
            else { break }
            append(chunk, to: out)
        }
        engine.stop()

        guard let channel = out.floatChannelData else { return nil }
        var samples = Array(UnsafeBufferPointer(start: channel[0],
                                                count: Int(out.frameLength)))
        // Hiss bed under the whole transmission — radios are never silent.
        var rng: UInt64 = 0xF00DFACE
        for i in samples.indices {
            rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
            let noise = Float(Int64(bitPattern: rng % 2000) - 1000) / 1000.0
            samples[i] = samples[i] * 1.6 + noise * 0.025
        }
        return samples
    }

    /// Render the phrase with the speech synthesiser into a PCM buffer,
    /// converted to the working format. Blocks its (background) thread.
    private static func capturedSpeech() -> AVAudioPCMBuffer? {
        let utterance = AVSpeechUtterance(string: "Box box, box box.")
        utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
        utterance.rate = 0.48
        utterance.pitchMultiplier = 0.85

        // The synthesiser delivers buffers via a run loop, so a blocking
        // semaphore starves it — pump the loop instead. State is guarded: the
        // callback may arrive on an internal queue.
        let synthesizer = AVSpeechSynthesizer()
        let lock = NSLock()
        nonisolated(unsafe) var chunks: [AVAudioPCMBuffer] = []
        nonisolated(unsafe) var finished = false

        synthesizer.write(utterance) { buffer in
            lock.lock(); defer { lock.unlock() }
            guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                finished = true
                return
            }
            chunks.append(pcm)
        }
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            lock.lock(); let isDone = finished; lock.unlock()
            if isDone { break }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        lock.lock(); defer { lock.unlock() }
        guard let first = chunks.first else { return nil }

        // Concatenate in the synthesiser's native format...
        let native = first.format
        let totalFrames = chunks.reduce(AVAudioFrameCount(0)) { $0 + $1.frameLength }
        guard let joined = AVAudioPCMBuffer(pcmFormat: native, frameCapacity: totalFrames)
        else { return nil }
        for chunk in chunks { append(chunk, to: joined) }

        // ...then convert to the working format in one pass.
        let target = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard native != target else { return joined }
        guard let converter = AVAudioConverter(from: native, to: target) else { return nil }
        let capacity = AVAudioFrameCount(Double(totalFrames)
            * (sampleRate / native.sampleRate) + 1024)
        guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity)
        else { return nil }

        var fed = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return joined
        }
        return error == nil ? converted : nil
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
        case .launch: buffer = launchClip()
        case .radio:  buffer = radioClip()
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
