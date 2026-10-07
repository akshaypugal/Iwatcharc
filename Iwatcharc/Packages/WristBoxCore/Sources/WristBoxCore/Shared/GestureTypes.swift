import Foundation

public enum PunchType: String, Codable, CaseIterable, Sendable {
    case jab
    case cross
    case leftHook
    case rightHook
    case uppercut
    case power

    public var displayName: String {
        switch self {
        case .jab: return "JAB"
        case .cross: return "CROSS"
        case .leftHook: return "LEFT HOOK"
        case .rightHook: return "RIGHT HOOK"
        case .uppercut: return "UPPERCUT"
        case .power: return "POWER PUNCH"
        }
    }

    /// Debug-style identifier, e.g. `RIGHT_HOOK`.
    public var code: String {
        switch self {
        case .jab: return "JAB"
        case .cross: return "CROSS"
        case .leftHook: return "LEFT_HOOK"
        case .rightHook: return "RIGHT_HOOK"
        case .uppercut: return "UPPERCUT"
        case .power: return "POWER_PUNCH"
        }
    }
}

public enum Side: String, Codable, CaseIterable, Sendable {
    case left
    case right

    public var opposite: Side { self == .left ? .right : .left }
}

/// A recognised punch together with its quality scores (all 0...1).
public struct PunchResult: Codable, Equatable, Sendable {
    public var type: PunchType
    /// Overall strength: blend of peak acceleration and estimated hand speed.
    public var power: Double
    /// How well the motion direction matched the ideal axis for this punch.
    public var accuracy: Double
    /// Estimated hand speed, normalised.
    public var speed: Double
    /// Classifier confidence.
    public var confidence: Double
    /// Sensor time (unix seconds, Watch clock) when the punch was detected.
    public var timestamp: TimeInterval

    public init(type: PunchType,
                power: Double,
                accuracy: Double,
                speed: Double,
                confidence: Double = 1,
                timestamp: TimeInterval = 0) {
        self.type = type
        self.power = power
        self.accuracy = accuracy
        self.speed = speed
        self.confidence = confidence
        self.timestamp = timestamp
    }
}

/// Metadata for non-punch gestures.
public struct MotionMeta: Codable, Equatable, Sendable {
    public var confidence: Double
    public var timestamp: TimeInterval

    public init(confidence: Double = 1, timestamp: TimeInterval = 0) {
        self.confidence = confidence
        self.timestamp = timestamp
    }
}

/// High-level event consumed by the boxing game. The game never sees raw
/// sensor data - only these events. The Watch, the simulator buttons and the
/// unit tests all produce the same type.
public enum GestureEvent: Equatable, Sendable {
    case jab(PunchResult)
    case cross(PunchResult)
    case leftHook(PunchResult)
    case rightHook(PunchResult)
    case uppercut(PunchResult)
    case power(PunchResult)
    case dodgeLeft(MotionMeta)
    case dodgeRight(MotionMeta)
    case blockStart(MotionMeta)
    case blockEnd(MotionMeta)
    /// Vigorous shaking. Optional gesture - used to trigger the special.
    case guardBreak(MotionMeta)

    public static func punch(_ r: PunchResult) -> GestureEvent {
        switch r.type {
        case .jab: return .jab(r)
        case .cross: return .cross(r)
        case .leftHook: return .leftHook(r)
        case .rightHook: return .rightHook(r)
        case .uppercut: return .uppercut(r)
        case .power: return .power(r)
        }
    }

    public var punchResult: PunchResult? {
        switch self {
        case .jab(let r), .cross(let r), .leftHook(let r), .rightHook(let r), .uppercut(let r), .power(let r):
            return r
        default:
            return nil
        }
    }

    public var confidence: Double {
        if let r = punchResult { return r.confidence }
        switch self {
        case .dodgeLeft(let m), .dodgeRight(let m), .blockStart(let m), .blockEnd(let m), .guardBreak(let m):
            return m.confidence
        default:
            return 1
        }
    }

    public var timestamp: TimeInterval {
        if let r = punchResult { return r.timestamp }
        switch self {
        case .dodgeLeft(let m), .dodgeRight(let m), .blockStart(let m), .blockEnd(let m), .guardBreak(let m):
            return m.timestamp
        default:
            return 0
        }
    }

    /// Debug label, e.g. `RIGHT_HOOK`.
    public var code: String {
        switch self {
        case .jab: return "JAB"
        case .cross: return "CROSS"
        case .leftHook: return "LEFT_HOOK"
        case .rightHook: return "RIGHT_HOOK"
        case .uppercut: return "UPPERCUT"
        case .power: return "POWER_PUNCH"
        case .dodgeLeft: return "DODGE_LEFT"
        case .dodgeRight: return "DODGE_RIGHT"
        case .blockStart: return "BLOCK"
        case .blockEnd: return "BLOCK_END"
        case .guardBreak: return "GUARD_BREAK"
        }
    }

    /// Same event with a different timestamp (used when stamping on the Watch).
    public func withTimestamp(_ t: TimeInterval) -> GestureEvent {
        switch self {
        case .jab(var r): r.timestamp = t; return .jab(r)
        case .cross(var r): r.timestamp = t; return .cross(r)
        case .leftHook(var r): r.timestamp = t; return .leftHook(r)
        case .rightHook(var r): r.timestamp = t; return .rightHook(r)
        case .uppercut(var r): r.timestamp = t; return .uppercut(r)
        case .power(var r): r.timestamp = t; return .power(r)
        case .dodgeLeft(var m): m.timestamp = t; return .dodgeLeft(m)
        case .dodgeRight(var m): m.timestamp = t; return .dodgeRight(m)
        case .blockStart(var m): m.timestamp = t; return .blockStart(m)
        case .blockEnd(var m): m.timestamp = t; return .blockEnd(m)
        case .guardBreak(var m): m.timestamp = t; return .guardBreak(m)
        }
    }
}
