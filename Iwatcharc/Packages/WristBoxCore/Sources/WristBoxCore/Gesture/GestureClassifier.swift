import Foundation

/// Gestures the classifier can emit from a single burst of motion.
public enum GestureKind: String, CaseIterable, Sendable {
    case jab, cross, leftHook, rightHook, uppercut, power, dodgeLeft, dodgeRight

    public var isPunch: Bool {
        switch self {
        case .dodgeLeft, .dodgeRight: return false
        default: return true
        }
    }

    public var punchType: PunchType? {
        switch self {
        case .jab: return .jab
        case .cross: return .cross
        case .leftHook: return .leftHook
        case .rightHook: return .rightHook
        case .uppercut: return .uppercut
        case .power: return .power
        default: return nil
        }
    }
}

public enum RejectionReason: String, Sendable {
    case weak            // below the minimum movement / acceleration threshold
    case tooShort        // single-sample glitch
    case tooLong         // waving, not a punch
    case wrongDirection  // downward / backward motion
    case ambiguous       // no dominant axis
    case lowConfidence
    case cooldown
    case rateLimited
    case retract         // the arm coming back after a punch
    case implausible     // absurd acceleration
    case lockout         // suppressed after a shake
}

/// Summary of one burst of motion, after peak detection.
public struct BurstFeatures: Equatable, Sendable {
    /// Peak filtered acceleration magnitude, g.
    public var peak: Double
    /// Unit direction of the burst in player coordinates.
    public var direction: LocalVec
    public var duration: Double
    /// Peak total angular speed, rad/s.
    public var peakGyro: Double
    /// Peak absolute yaw rate (rotation about the vertical axis), rad/s.
    public var peakYaw: Double
    /// Estimated hand speed, m/s.
    public var speed: Double

    public init(peak: Double, direction: LocalVec, duration: Double, peakGyro: Double, peakYaw: Double, speed: Double) {
        self.peak = peak
        self.direction = direction
        self.duration = duration
        self.peakGyro = peakGyro
        self.peakYaw = peakYaw
        self.speed = speed
    }
}

public enum Classification: Equatable, Sendable {
    case accepted(kind: GestureKind, power: Double, accuracy: Double, speed: Double, confidence: Double)
    case rejected(RejectionReason)
}

/// Pure function from burst features to a gesture. No state, no sensors:
/// directly unit-testable.
public enum GestureClassifier {
    public static func classify(_ f: BurstFeatures, config c: GestureConfig) -> Classification {
        if f.peak > c.maxPeak { return .rejected(.implausible) }
        if f.peak < c.minPeak { return .rejected(.weak) }
        if f.duration < c.minDuration { return .rejected(.tooShort) }
        if f.duration > c.maxDuration { return .rejected(.tooLong) }

        let d = f.direction
        let fwd = d.forward
        let lat = c.mirror ? -d.lateral : d.lateral
        let vert = d.vertical

        // Upward motion -> uppercut.
        if vert >= c.uppercutVerticalFrac {
            guard f.peak >= c.uppercutMin else { return .rejected(.weak) }
            return accept(.uppercut, cosine: vert, f, c)
        }
        if vert <= -c.uppercutVerticalFrac { return .rejected(.wrongDirection) }

        // Sideways motion -> hook (rotational) or dodge (translational).
        if abs(lat) >= c.lateralFrac {
            let left = lat < 0
            if f.peakYaw >= c.hookYawMin {
                guard f.peak >= c.hookMin else { return .rejected(.weak) }
                return accept(left ? .leftHook : .rightHook, cosine: abs(lat), f, c)
            }
            if f.peak >= c.dodgeMin, f.peak <= c.dodgeMax, f.peakGyro <= c.dodgeGyroMax {
                return accept(left ? .dodgeLeft : .dodgeRight, cosine: abs(lat), f, c)
            }
            return .rejected(f.peak < c.dodgeMin ? .weak : .ambiguous)
        }

        // Forward motion -> straight punches, ordered by strength.
        if fwd >= c.forwardFrac {
            if f.speed < c.minPunchSpeed { return .rejected(.weak) }
            if f.peak >= c.powerMin { return accept(.power, cosine: fwd, f, c) }
            if f.peak >= c.crossMin { return accept(.cross, cosine: fwd, f, c) }
            if f.peak >= c.jabMin { return accept(.jab, cosine: fwd, f, c) }
            return .rejected(.weak)
        }
        if fwd <= -c.forwardFrac { return .rejected(.wrongDirection) }
        return .rejected(.ambiguous)
    }

    private static func accept(_ kind: GestureKind, cosine: Double, _ f: BurstFeatures, _ c: GestureConfig) -> Classification {
        let accuracy = clamp((cosine - 0.45) / 0.5)
        let speed01 = clamp(f.speed / c.speedReference)
        let peakRef = c.peakReference * c.peakScale(for: kind)
        let power = clamp(0.55 * (f.peak / peakRef) + 0.45 * speed01)
        let dirConf = clamp((cosine - 0.5) / 0.4)
        let peakConf = clamp(f.peak / (c.minPeak(for: kind) * 1.5))
        let confidence = clamp(0.35 + 0.35 * dirConf + 0.30 * peakConf)
        if confidence < c.confidenceMin { return .rejected(.lowConfidence) }
        return .accepted(kind: kind, power: power, accuracy: accuracy, speed: speed01, confidence: confidence)
    }
}
