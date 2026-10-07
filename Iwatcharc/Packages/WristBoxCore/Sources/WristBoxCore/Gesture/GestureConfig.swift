import Foundation

/// All tunable thresholds of the gesture recogniser in one place.
///
/// Accelerations are in g (user acceleration, gravity removed), rotation rates in
/// rad/s, times in seconds. The defaults are a first guess that behaves well with
/// synthetic data; tune them with the Debug screen on a real Watch (Phase 6).
public struct GestureConfig: Codable, Equatable, Sendable {
    // MARK: Noise filtering
    /// EMA coefficient applied after the 3-sample median (higher = less smoothing, less latency).
    public var smoothing: Double = 0.55

    // MARK: Peak detection
    /// A burst of motion starts when the filtered magnitude exceeds this.
    public var startThreshold: Double = 0.8
    /// Classification fires once the magnitude drops below `peak * peakDropRatio`.
    public var peakDropRatio: Double = 0.72
    /// Bursts shorter than this are sensor glitches.
    public var minDuration: Double = 0.03
    /// Bursts longer than this are waving, not punching.
    public var maxDuration: Double = 0.65
    /// Estimated speed is the integrated rising phase times this factor.
    public var speedCompensation: Double = 1.3

    // MARK: Anti-cheat / validation
    /// Minimum filtered peak for any gesture (minimum movement threshold).
    public var minPeak: Double = 0.9
    /// Peaks above this are treated as sensor glitches / abuse.
    public var maxPeak: Double = 24
    /// Minimum estimated hand speed (m/s) for punches.
    public var minPunchSpeed: Double = 0.7
    /// Gestures below this confidence are dropped.
    public var confidenceMin: Double = 0.45
    /// Maximum punches (any punch type) accepted in a rolling second.
    public var maxPunchesPerSecond: Int = 6

    // MARK: Direction thresholds (cosines of the unit direction vector)
    public var forwardFrac: Double = 0.6
    public var lateralFrac: Double = 0.62
    public var uppercutVerticalFrac: Double = 0.62

    // MARK: Peak thresholds (g)
    public var jabMin: Double = 1.8
    public var crossMin: Double = 3.2
    public var powerMin: Double = 5.5
    public var hookMin: Double = 2.0
    public var uppercutMin: Double = 1.7
    public var dodgeMin: Double = 0.9
    public var dodgeMax: Double = 3.2

    // MARK: Rotation thresholds (rad/s)
    /// Yaw rate above which lateral motion is a hook instead of a dodge.
    public var hookYawMin: Double = 5.0
    /// Dodges are mostly translation; above this total rotation it is not a dodge.
    public var dodgeGyroMax: Double = 4.0

    // MARK: Cooldowns (seconds between two gestures of the same kind)
    public var jabCooldown: Double = 0.12
    public var crossCooldown: Double = 0.20
    public var hookCooldown: Double = 0.28
    public var uppercutCooldown: Double = 0.28
    public var powerCooldown: Double = 0.50
    public var dodgeCooldown: Double = 0.35

    // MARK: Recovery / retract rejection
    /// After a punch, an opposite-direction burst inside this window is the arm coming back.
    public var punchRecovery: Double = 0.28
    public var hookRecovery: Double = 0.34
    public var dodgeRecovery: Double = 0.50
    /// dot(previous direction, new direction) below this counts as "opposite".
    public var retractDot: Double = -0.2

    // MARK: Block
    public var blockAngleDegrees: Double = 28
    public var blockExitAngleDegrees: Double = 38
    public var blockHoldTime: Double = 0.22
    public var blockQuietAccel: Double = 0.35
    public var blockQuietGyro: Double = 2.0
    public var blockExitAccel: Double = 1.2

    // MARK: Shake / guard break
    public var shakeBursts: Int = 4
    public var shakeWindow: Double = 0.9
    public var shakeMinPeak: Double = 3.0
    public var shakeLockout: Double = 1.0

    // MARK: Quality scoring
    /// Peak that corresponds to power = 1 (before the per-type scale).
    public var peakReference: Double = 7.0
    /// Hand speed (m/s) that corresponds to speed = 1.
    public var speedReference: Double = 4.0

    // MARK: Heading (forward direction) recovery
    /// CoreMotion's world heading is arbitrary and changes whenever the sensors restart,
    /// so the calibrated "forward" can be stale. These settings re-learn it automatically.
    /// Minimum peak (g) for the first punch of a session to lock in the forward direction.
    public var lockInMinPeak: Double = 2.0
    /// Re-centre forward after two strong, consistent punches were rejected as backwards/ambiguous.
    public var autoRecenter: Bool = true
    public var recenterWindow: Double = 4.0
    public var recenterAngleDegrees: Double = 25

    // MARK: Handedness
    /// Flip left/right (for players who prefer the opposite mapping).
    public var mirror: Bool = false

    public init() {}

    public static let `default` = GestureConfig()

    func cooldown(for kind: GestureKind) -> Double {
        switch kind {
        case .jab: return jabCooldown
        case .cross: return crossCooldown
        case .leftHook, .rightHook: return hookCooldown
        case .uppercut: return uppercutCooldown
        case .power: return powerCooldown
        case .dodgeLeft, .dodgeRight: return dodgeCooldown
        }
    }

    func recovery(for kind: GestureKind) -> Double {
        switch kind {
        case .jab, .cross, .uppercut, .power: return punchRecovery
        case .leftHook, .rightHook: return hookRecovery
        case .dodgeLeft, .dodgeRight: return dodgeRecovery
        }
    }

    func minPeak(for kind: GestureKind) -> Double {
        switch kind {
        case .jab: return jabMin
        case .cross: return crossMin
        case .leftHook, .rightHook: return hookMin
        case .uppercut: return uppercutMin
        case .power: return powerMin
        case .dodgeLeft, .dodgeRight: return dodgeMin
        }
    }

    /// Per-type scale of `peakReference` so a good jab can still score high power.
    func peakScale(for kind: GestureKind) -> Double {
        switch kind {
        case .jab: return 0.65
        case .cross, .leftHook, .rightHook: return 1.0
        case .uppercut: return 0.9
        case .power: return 1.4
        case .dodgeLeft, .dodgeRight: return 0.4
        }
    }
}
