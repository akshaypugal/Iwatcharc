import Foundation

// MARK: - Supporting payload types

/// What the Watch's motion pipeline is doing.
public enum MotionMode: String, Codable, Sendable {
    /// Sensors off (battery friendly).
    case off
    /// Recognising gestures and streaming them to the iPhone.
    case fight
    /// Recognising gestures and showing them on the Watch only.
    case practice
}

public enum CalibrationStep: String, Codable, Sendable {
    case idle
    case neutral
    case guardPose
    case punch
    case done
    case failed
}

public struct CalibrationProgress: Codable, Equatable, Sendable {
    public var step: CalibrationStep
    /// 0...1 within the current step.
    public var progress: Double
    public var secondsLeft: Int
    public var message: String

    public init(step: CalibrationStep, progress: Double = 0, secondsLeft: Int = 0, message: String = "") {
        self.step = step
        self.progress = progress
        self.secondsLeft = secondsLeft
        self.message = message
    }
}

public enum WatchPhase: String, Codable, Sendable {
    case idle
    case countdown
    case fighting
    case knockdown
    case roundEnd
    case fightOver
}

/// What the Watch UI shows during a fight.
public struct GameStateSummary: Codable, Equatable, Sendable {
    public var phase: WatchPhase
    public var round: Int
    public var totalRounds: Int
    public var remaining: Double
    public var combo: Int
    public var specialReady: Bool
    public var sentTime: TimeInterval

    public init(phase: WatchPhase = .idle, round: Int = 1, totalRounds: Int = 3, remaining: Double = 0,
                combo: Int = 0, specialReady: Bool = false, sentTime: TimeInterval = 0) {
        self.phase = phase
        self.round = round
        self.totalRounds = totalRounds
        self.remaining = remaining
        self.combo = combo
        self.specialReady = specialReady
        self.sentTime = sentTime
    }
}

/// Haptic patterns the iPhone can ask the Watch to play.
public enum HapticCue: String, Codable, CaseIterable, Sendable {
    case punchLanded
    case perfectPunch
    case opponentHit      // the player got hit
    case blocked
    case dodged
    case counter
    case combo
    case ko
    case knockdown
    case roundStart
    case roundEnd
    case specialReady
    case special
    case victory
    case defeat
}

public enum WatchCommand: Equatable, Sendable {
    case setMode(MotionMode)
    case startCalibration
    case cancelCalibration
    case setDebugStream(Bool)
    case setConfig(GestureConfig)
    case setCalibration(Calibration)
    case setLocalHaptics(Bool)
}

/// A batch of raw sensor readings for the Debug screen. Flat array, stride 7:
/// `t, userAccelX, userAccelY, userAccelZ, gyroX, gyroY, gyroZ`.
public struct RawBatch: Equatable, Sendable {
    public static let stride = 7
    public var values: [Double]

    public init(values: [Double]) { self.values = values }

    public init(samples: [MotionSample]) {
        var v: [Double] = []
        v.reserveCapacity(samples.count * RawBatch.stride)
        for s in samples {
            v.append(contentsOf: [s.timestamp, s.userAccel.x, s.userAccel.y, s.userAccel.z,
                                  s.rotationRate.x, s.rotationRate.y, s.rotationRate.z])
        }
        values = v
    }

    public var count: Int { values.count / RawBatch.stride }

    /// The newest sample as (time, accel, gyro).
    public var last: (time: Double, accel: Vec3, gyro: Vec3)? {
        guard count > 0 else { return nil }
        let i = (count - 1) * RawBatch.stride
        return (values[i], Vec3(values[i + 1], values[i + 2], values[i + 3]), Vec3(values[i + 4], values[i + 5], values[i + 6]))
    }
}

// MARK: - Wire message

/// Everything exchanged between Watch and iPhone, encoded as a plist-safe
/// dictionary for WatchConnectivity.
public enum WireMessage: Equatable, Sendable {
    case gesture(GestureEvent, seq: Int, sensorTime: Double, sentTime: Double)
    case heartbeat(seq: Int, sentTime: Double, mode: MotionMode)
    case ping(id: Int, sentTime: Double)
    case pong(id: Int, pingSentTime: Double, watchTime: Double)
    case state(GameStateSummary)
    case haptic(HapticCue)
    case command(WatchCommand)
    case calibrationProgress(CalibrationProgress)
    case calibrationResult(Calibration)
    case rawBatch(RawBatch)
    case decision(time: Double, label: String, peak: Double, confidence: Double)

    // MARK: Encode

    public var dictionary: [String: Any] {
        switch self {
        case .gesture(let e, let seq, let sensor, let sent):
            var d: [String: Any] = ["k": "g", "seq": seq, "st": sensor, "tx": sent, "n": e.code, "c": e.confidence]
            if let r = e.punchResult {
                d["p"] = r.power
                d["a"] = r.accuracy
                d["s"] = r.speed
            }
            return d
        case .heartbeat(let seq, let sent, let mode):
            return ["k": "hb", "seq": seq, "tx": sent, "m": mode.rawValue]
        case .ping(let id, let sent):
            return ["k": "ping", "id": id, "tx": sent]
        case .pong(let id, let pingSent, let watchTime):
            return ["k": "pong", "id": id, "t0": pingSent, "tw": watchTime]
        case .state(let s):
            return ["k": "state", "d": Self.encode(s)]
        case .haptic(let cue):
            return ["k": "haptic", "h": cue.rawValue]
        case .command(let c):
            return Self.encodeCommand(c)
        case .calibrationProgress(let p):
            return ["k": "calp", "d": Self.encode(p)]
        case .calibrationResult(let c):
            return ["k": "calr", "d": Self.encode(c)]
        case .rawBatch(let b):
            return ["k": "raw", "v": b.values]
        case .decision(let t, let label, let peak, let conf):
            return ["k": "dec", "t": t, "l": label, "pk": peak, "c": conf]
        }
    }

    private static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ any: Any?) -> T? {
        guard let data = any as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encodeCommand(_ c: WatchCommand) -> [String: Any] {
        switch c {
        case .setMode(let m): return ["k": "cmd", "c": "mode", "m": m.rawValue]
        case .startCalibration: return ["k": "cmd", "c": "calStart"]
        case .cancelCalibration: return ["k": "cmd", "c": "calCancel"]
        case .setDebugStream(let on): return ["k": "cmd", "c": "debug", "b": on]
        case .setConfig(let cfg): return ["k": "cmd", "c": "config", "d": encode(cfg)]
        case .setCalibration(let cal): return ["k": "cmd", "c": "calibration", "d": encode(cal)]
        case .setLocalHaptics(let on): return ["k": "cmd", "c": "localHaptics", "b": on]
        }
    }

    // MARK: Decode

    private static func double(_ d: [String: Any], _ key: String) -> Double? {
        if let v = d[key] as? Double { return v }
        if let v = d[key] as? Int { return Double(v) }
        if let v = d[key] as? NSNumber { return v.doubleValue }
        return nil
    }

    private static func int(_ d: [String: Any], _ key: String) -> Int? {
        if let v = d[key] as? Int { return v }
        if let v = d[key] as? Double { return Int(v) }
        if let v = d[key] as? NSNumber { return v.intValue }
        return nil
    }

    /// Returns nil for malformed or unknown messages (never crashes on bad input).
    public init?(dictionary d: [String: Any]) {
        guard let kind = d["k"] as? String else { return nil }
        switch kind {
        case "g":
            guard let name = d["n"] as? String,
                  let seq = Self.int(d, "seq"),
                  let sensor = Self.double(d, "st"),
                  let sent = Self.double(d, "tx") else { return nil }
            let conf = Self.double(d, "c") ?? 1
            let meta = MotionMeta(confidence: conf, timestamp: sensor)
            func punch(_ type: PunchType) -> PunchResult {
                PunchResult(type: type,
                            power: Self.double(d, "p") ?? 0.5,
                            accuracy: Self.double(d, "a") ?? 0.5,
                            speed: Self.double(d, "s") ?? 0.5,
                            confidence: conf,
                            timestamp: sensor)
            }
            let event: GestureEvent
            switch name {
            case "JAB": event = .jab(punch(.jab))
            case "CROSS": event = .cross(punch(.cross))
            case "LEFT_HOOK": event = .leftHook(punch(.leftHook))
            case "RIGHT_HOOK": event = .rightHook(punch(.rightHook))
            case "UPPERCUT": event = .uppercut(punch(.uppercut))
            case "POWER_PUNCH": event = .power(punch(.power))
            case "DODGE_LEFT": event = .dodgeLeft(meta)
            case "DODGE_RIGHT": event = .dodgeRight(meta)
            case "BLOCK": event = .blockStart(meta)
            case "BLOCK_END": event = .blockEnd(meta)
            case "GUARD_BREAK": event = .guardBreak(meta)
            default: return nil
            }
            self = .gesture(event, seq: seq, sensorTime: sensor, sentTime: sent)

        case "hb":
            guard let seq = Self.int(d, "seq"), let sent = Self.double(d, "tx") else { return nil }
            let mode = (d["m"] as? String).flatMap(MotionMode.init(rawValue:)) ?? .off
            self = .heartbeat(seq: seq, sentTime: sent, mode: mode)

        case "ping":
            guard let id = Self.int(d, "id"), let sent = Self.double(d, "tx") else { return nil }
            self = .ping(id: id, sentTime: sent)

        case "pong":
            guard let id = Self.int(d, "id"), let t0 = Self.double(d, "t0"), let tw = Self.double(d, "tw") else { return nil }
            self = .pong(id: id, pingSentTime: t0, watchTime: tw)

        case "state":
            guard let s = Self.decode(GameStateSummary.self, d["d"]) else { return nil }
            self = .state(s)

        case "haptic":
            guard let raw = d["h"] as? String, let cue = HapticCue(rawValue: raw) else { return nil }
            self = .haptic(cue)

        case "cmd":
            guard let c = d["c"] as? String else { return nil }
            switch c {
            case "mode":
                guard let raw = d["m"] as? String, let m = MotionMode(rawValue: raw) else { return nil }
                self = .command(.setMode(m))
            case "calStart": self = .command(.startCalibration)
            case "calCancel": self = .command(.cancelCalibration)
            case "debug":
                guard let on = d["b"] as? Bool else { return nil }
                self = .command(.setDebugStream(on))
            case "config":
                guard let cfg = Self.decode(GestureConfig.self, d["d"]) else { return nil }
                self = .command(.setConfig(cfg))
            case "calibration":
                guard let cal = Self.decode(Calibration.self, d["d"]) else { return nil }
                self = .command(.setCalibration(cal))
            case "localHaptics":
                guard let on = d["b"] as? Bool else { return nil }
                self = .command(.setLocalHaptics(on))
            default: return nil
            }

        case "calp":
            guard let p = Self.decode(CalibrationProgress.self, d["d"]) else { return nil }
            self = .calibrationProgress(p)

        case "calr":
            guard let c = Self.decode(Calibration.self, d["d"]) else { return nil }
            self = .calibrationResult(c)

        case "raw":
            if let v = d["v"] as? [Double] {
                self = .rawBatch(RawBatch(values: v))
            } else if let v = d["v"] as? [NSNumber] {
                self = .rawBatch(RawBatch(values: v.map { $0.doubleValue }))
            } else {
                return nil
            }

        case "dec":
            guard let t = Self.double(d, "t"), let l = d["l"] as? String,
                  let pk = Self.double(d, "pk"), let c = Self.double(d, "c") else { return nil }
            self = .decision(time: t, label: l, peak: pk, confidence: c)

        default:
            return nil
        }
    }
}
