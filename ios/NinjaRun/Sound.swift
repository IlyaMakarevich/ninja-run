import AVFoundation

/// Retro sound effects synthesized at launch — no audio files needed.
enum SFX: CaseIterable {
    case jump, wallJump, land, gold, switchOn, doorOpen, key, launchpad
    case death, explosion, zap, lockOn, gauss, rocket, win, tap
}

final class Sound {
    static let shared = Sound()

    var enabled: Bool {
        get { !UserDefaults.standard.bool(forKey: "muted") }
        set { UserDefaults.standard.set(!newValue, forKey: "muted") }
    }

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [SFX: AVAudioPCMBuffer] = [:]
    private var next = 0
    private let rate: Double = 44100
    private let format: AVAudioFormat

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        for _ in 0..<10 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        engine.mainMixerNode.outputVolume = 0.4
        for s in SFX.allCases { buffers[s] = synth(s) }
        start()
    }

    private func start() {
        guard !engine.isRunning else { return }
        try? engine.start()
        for p in players { p.play() }
    }

    func play(_ s: SFX) {
        guard enabled, let buf = buffers[s] else { return }
        if !engine.isRunning { start() }
        guard engine.isRunning else { return }
        let p = players[next]
        next = (next + 1) % players.count
        p.scheduleBuffer(buf, at: nil, options: .interrupts)
        if !p.isPlaying { p.play() }
    }

    // MARK: - Synthesis

    /// Renders a sound with a soft attack, smooth release and a low-pass filter to take the edge off.
    private func render(_ duration: Double, _ volume: Float, attack: Double = 0.008, cutoff: Double = 2500,
                        _ f: (_ t: Double, _ k: Double) -> Double) -> AVAudioPCMBuffer {
        let n = AVAudioFrameCount(duration * rate)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n)!
        buf.frameLength = n
        let data = buf.floatChannelData![0]
        let alpha = 1 - exp(-2 * .pi * cutoff / rate)
        var lp1 = 0.0, lp2 = 0.0
        for i in 0..<Int(n) {
            let t = Double(i) / rate
            let k = t / duration                          // 0…1 progress
            let env = min(1, t / attack) * min(1, (duration - t) / 0.02)
            let x = f(t, k) * env
            lp1 += alpha * (x - lp1)                      // two-pole low-pass
            lp2 += alpha * (lp1 - lp2)
            data[i] = Float(lp2) * volume
        }
        return buf
    }

    func synth(_ s: SFX) -> AVAudioPCMBuffer {
        var osc = Osc()
        var osc2 = Osc()
        var noise = Noise()
        func decay(_ k: Double, _ p: Double = 2) -> Double { pow(1 - k, p) }
        switch s {
        case .jump:
            return render(0.12, 0.10) { _, k in osc.triangle(260 + 220 * k) * decay(k) }
        case .wallJump:
            return render(0.13, 0.10) { _, k in osc.triangle(330 + 260 * k) * decay(k) }
        case .land:
            return render(0.08, 0.20, attack: 0.004, cutoff: 600) { _, k in noise.low(0.05) * decay(k, 3) }
        case .gold:
            return render(0.18, 0.14) { t, k in osc.sine(t < 0.05 ? 1046 : 1318) * decay(k, 1.5) }
        case .switchOn:
            return render(0.18, 0.13) { t, k in osc.sine(t < 0.07 ? 587 : 784) * decay(k, 1.5) }
        case .doorOpen:
            return render(0.36, 0.11) { t, k in osc.triangle([523, 659, 784][min(2, Int(t / 0.12))]) * decay(k, 1.2) }
        case .key:
            return render(0.3, 0.13) { _, k in (osc.sine(1175) + 0.4 * osc2.sine(1568)) * decay(k, 2) }
        case .launchpad:
            return render(0.28, 0.18) { _, k in osc.sine(160 + 420 * k * k) * decay(k, 1.5) }
        case .death:
            return render(0.5, 0.28, cutoff: 900) { _, k in (noise.low(0.12) * 0.8 + osc.triangle(200 - 130 * k) * 0.4) * decay(k, 2) }
        case .explosion:
            return render(0.65, 0.40, attack: 0.005, cutoff: 700) { _, k in noise.low(0.06 + 0.08 * (1 - k)) * decay(k, 2.5) }
        case .zap:
            return render(0.3, 0.10, cutoff: 1800) { t, k in osc.triangle(220 + 60 * sin(2 * .pi * 40 * t)) * decay(k, 1.5) }
        case .lockOn:
            return render(0.1, 0.07) { _, k in osc.sine(1046) * decay(k) }
        case .gauss:
            return render(0.32, 0.18, cutoff: 1500) { _, k in (osc.sine(900 * decay(k) + 120) * 0.6 + noise.low(0.15) * 0.4) * decay(k, 1.5) }
        case .rocket:
            return render(0.38, 0.16, attack: 0.04, cutoff: 900) { _, k in noise.low(0.1) * sin(.pi * k) }
        case .win:
            return render(0.6, 0.12) { t, k in osc.triangle([523, 659, 784, 1046][min(3, Int(t / 0.11))]) * decay(k, 0.8) }
        case .tap:
            return render(0.05, 0.06) { _, k in osc.sine(700) * decay(k) }
        }
    }
}

/// Phase-continuous oscillator (so frequency sweeps don't click).
private struct Osc {
    var phase = 0.0
    mutating func advance(_ hz: Double) -> Double {
        phase += hz / 44100
        phase -= floor(phase)
        return phase
    }
    mutating func sine(_ hz: Double) -> Double { sin(2 * .pi * advance(hz)) }
    mutating func triangle(_ hz: Double) -> Double { 1 - 4 * abs(advance(hz) - 0.5) }
}

private struct Noise {
    var last = 0.0
    mutating func white() -> Double { Double.random(in: -1...1) }
    /// One-pole low-passed noise; smaller `a` = darker.
    mutating func low(_ a: Double) -> Double {
        last += a * (white() - last)
        return last * 2.5
    }
}
