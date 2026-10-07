import AVFoundation
import Foundation

/// Sound effects synthesised in code - no audio assets to ship or license.
/// Each effect is rendered once into an in-memory WAV and played from a small
/// pool of players so rapid punches can overlap.
final class SoundService {
    enum Effect: CaseIterable {
        case tick, bell, whoosh, punch, heavyPunch, perfect, counter, block, hurt, special, ko, combo, victory, defeat
    }

    var enabled = true

    private var pools: [Effect: [AVAudioPlayer]] = [:]
    private var cursor: [Effect: Int] = [:]
    private let sampleRate = 22_050.0

    init() {
        configureSession()
        for effect in Effect.allCases {
            guard let data = render(effect) else { continue }
            var players: [AVAudioPlayer] = []
            for _ in 0..<3 {
                if let p = try? AVAudioPlayer(data: data) {
                    p.prepareToPlay()
                    players.append(p)
                }
            }
            pools[effect] = players
        }
    }

    func play(_ effect: Effect) {
        guard enabled, let players = pools[effect], !players.isEmpty else { return }
        let i = (cursor[effect] ?? 0) % players.count
        cursor[effect] = i + 1
        let p = players[i]
        p.currentTime = 0
        p.play()
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    // MARK: Synthesis

    private func render(_ effect: Effect) -> Data? {
        switch effect {
        case .tick:
            return wav(duration: 0.12) { t in sine(880, t) * env(t, 0.12, attack: 0.002) * 0.5 }
        case .bell:
            return wav(duration: 1.1) { t in
                let e = exp(-t * 3.2)
                return (sine(880, t) + 0.5 * sine(1_760, t) + 0.25 * sine(2_640, t)) * e * 0.35
            }
        case .whoosh:
            var rng = SystemRandomNumberGenerator()
            return wav(duration: 0.18) { t in
                let noise = Double.random(in: -1...1, using: &rng)
                return noise * env(t, 0.18, attack: 0.05) * 0.25 * (1 - t / 0.18)
            }
        case .punch:
            return thud(duration: 0.22, startHz: 150, endHz: 55, noise: 0.45, gain: 0.9)
        case .heavyPunch:
            return thud(duration: 0.34, startHz: 120, endHz: 38, noise: 0.6, gain: 1.0)
        case .perfect:
            return wav(duration: 0.4) { t in
                let f = t < 0.12 ? 880.0 : 1_320.0
                return (sine(f, t) + 0.3 * sine(f * 2, t)) * exp(-t * 6) * 0.5
            }
        case .counter:
            return wav(duration: 0.5) { t in
                let f = 440 + 1_200 * t
                return (sine(f, t) + 0.4 * sine(f * 1.5, t)) * exp(-t * 4) * 0.5
            }
        case .block:
            return thud(duration: 0.12, startHz: 320, endHz: 200, noise: 0.5, gain: 0.5)
        case .hurt:
            return thud(duration: 0.3, startHz: 100, endHz: 45, noise: 0.7, gain: 1.0)
        case .special:
            return wav(duration: 0.9) { t in
                let f = 220 + 900 * t * t
                return (sine(f, t) + 0.5 * sine(f * 2, t)) * env(t, 0.9, attack: 0.05) * 0.45
            }
        case .ko:
            return wav(duration: 1.4) { t in
                let f = 180 * exp(-t * 1.6)
                return (sine(f, t) + 0.3 * sine(f * 0.5, t)) * exp(-t * 2.2) * 0.9
            }
        case .combo:
            return wav(duration: 0.28) { t in
                let f = t < 0.1 ? 660.0 : 990.0
                return sine(f, t) * exp(-t * 9) * 0.5
            }
        case .victory:
            return wav(duration: 1.2) { t in
                let notes: [Double] = [523, 659, 784, 1_046]
                let idx = min(notes.count - 1, Int(t / 0.22))
                let local = t - Double(idx) * 0.22
                return (sine(notes[idx], t) + 0.3 * sine(notes[idx] * 2, t)) * exp(-local * 3) * 0.5
            }
        case .defeat:
            return wav(duration: 1.0) { t in
                let notes: [Double] = [392, 349, 311, 262]
                let idx = min(notes.count - 1, Int(t / 0.22))
                let local = t - Double(idx) * 0.22
                return sine(notes[idx], t) * exp(-local * 2.5) * 0.5
            }
        }
    }

    private func thud(duration: Double, startHz: Double, endHz: Double, noise: Double, gain: Double) -> Data? {
        var rng = SystemRandomNumberGenerator()
        var phase = 0.0
        return wav(duration: duration) { t in
            let k = t / duration
            let hz = startHz + (endHz - startHz) * k
            phase += 2 * Double.pi * hz / self.sampleRate
            let body = sin(phase) * exp(-t * 14)
            let click = Double.random(in: -1...1, using: &rng) * exp(-t * 60)
            return (body * (1 - noise * 0.5) + click * noise) * gain * 0.9
        }
    }

    private func sine(_ hz: Double, _ t: Double) -> Double { sin(2 * Double.pi * hz * t) }

    private func env(_ t: Double, _ duration: Double, attack: Double) -> Double {
        let a = min(1, t / attack)
        let r = min(1, (duration - t) / 0.03)
        return max(0, min(a, r))
    }

    /// Renders mono 16-bit PCM and wraps it in a WAV container.
    private func wav(duration: Double, generator: (Double) -> Double) -> Data? {
        let count = Int(duration * sampleRate)
        guard count > 0 else { return nil }
        var pcm = Data(capacity: count * 2)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let v = max(-1, min(1, generator(t)))
            var s = Int16(v * 32_000).littleEndian
            withUnsafeBytes(of: &s) { pcm.append(contentsOf: $0) }
        }
        var header = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { header.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { header.append(contentsOf: $0) } }
        header.append(contentsOf: Array("RIFF".utf8))
        u32(UInt32(36 + pcm.count))
        header.append(contentsOf: Array("WAVE".utf8))
        header.append(contentsOf: Array("fmt ".utf8))
        u32(16)
        u16(1)                              // PCM
        u16(1)                              // mono
        u32(UInt32(sampleRate))
        u32(UInt32(sampleRate) * 2)         // byte rate
        u16(2)                              // block align
        u16(16)                             // bits per sample
        header.append(contentsOf: Array("data".utf8))
        u32(UInt32(pcm.count))
        return header + pcm
    }
}
