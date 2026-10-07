import Foundation

/// The buttons of the Developer Controller Mode.
public enum SimulatedInput: String, CaseIterable, Sendable {
    case jab, cross, leftHook, rightHook, uppercut, dodgeLeft, dodgeRight, block, power, special

    public var title: String {
        switch self {
        case .jab: return "JAB"
        case .cross: return "CROSS"
        case .leftHook: return "L HOOK"
        case .rightHook: return "R HOOK"
        case .uppercut: return "UPPERCUT"
        case .dodgeLeft: return "DODGE L"
        case .dodgeRight: return "DODGE R"
        case .block: return "BLOCK"
        case .power: return "POWER"
        case .special: return "SPECIAL"
        }
    }

    /// Keyboard shortcut key used in the Simulator.
    public var shortcutKey: Character {
        switch self {
        case .jab: return "j"
        case .cross: return "k"
        case .leftHook: return "u"
        case .rightHook: return "i"
        case .uppercut: return "o"
        case .dodgeLeft: return "a"
        case .dodgeRight: return "d"
        case .block: return "s"
        case .power: return "p"
        case .special: return " "
        }
    }
}

/// Produces `GestureEvent`s exactly like the Watch would, from button presses.
/// The boxing game cannot tell the difference, which is the point: the whole
/// game can be developed and tested without hardware.
public struct SimulatedController: Sendable {
    public var rng: SeededRNG
    /// Mean quality of simulated punches (0...1).
    public var quality: Double
    /// Random spread around `quality`.
    public var jitter: Double

    public init(seed: UInt64 = 1, quality: Double = 0.8, jitter: Double = 0.1) {
        rng = SeededRNG(seed: seed)
        self.quality = quality
        self.jitter = jitter
    }

    public func punchType(for input: SimulatedInput) -> PunchType? {
        switch input {
        case .jab: return .jab
        case .cross: return .cross
        case .leftHook: return .leftHook
        case .rightHook: return .rightHook
        case .uppercut: return .uppercut
        case .power, .special: return .power
        default: return nil
        }
    }

    /// Event for a button press. `block` returns `blockStart`; use `releaseBlock` for the release.
    public mutating func event(for input: SimulatedInput, at time: TimeInterval = Date().timeIntervalSince1970) -> GestureEvent {
        let meta = MotionMeta(confidence: 1, timestamp: time)
        switch input {
        case .dodgeLeft: return .dodgeLeft(meta)
        case .dodgeRight: return .dodgeRight(meta)
        case .block: return .blockStart(meta)
        case .special: return .guardBreak(meta)
        default:
            let type = punchType(for: input) ?? .jab
            return .punch(punch(type, time: time))
        }
    }

    public func releaseBlock(at time: TimeInterval = Date().timeIntervalSince1970) -> GestureEvent {
        .blockEnd(MotionMeta(confidence: 1, timestamp: time))
    }

    /// A punch of a specific type with explicit or randomised quality.
    public mutating func punch(_ type: PunchType,
                               power: Double? = nil,
                               accuracy: Double? = nil,
                               time: TimeInterval = Date().timeIntervalSince1970) -> PunchResult {
        let p = power ?? clamp(quality + rng.range(-jitter, jitter))
        let a = accuracy ?? clamp(quality + 0.1 + rng.range(-jitter, jitter))
        let s = clamp(quality + rng.range(-jitter, jitter))
        return PunchResult(type: type, power: p, accuracy: a, speed: s, confidence: 1, timestamp: time)
    }
}
