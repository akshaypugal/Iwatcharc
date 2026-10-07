import Foundation

/// Motion expressed relative to the player: forward (the way they punch),
/// lateral (positive = player's right) and vertical (positive = up).
public struct LocalVec: Equatable, Sendable {
    public var forward: Double
    public var lateral: Double
    public var vertical: Double

    public init(forward: Double = 0, lateral: Double = 0, vertical: Double = 0) {
        self.forward = forward
        self.lateral = lateral
        self.vertical = vertical
    }

    public var magnitude: Double {
        (forward * forward + lateral * lateral + vertical * vertical).squareRoot()
    }

    public var normalized: LocalVec {
        let m = magnitude
        return m > 1e-9 ? LocalVec(forward: forward / m, lateral: lateral / m, vertical: vertical / m) : LocalVec()
    }

    public func dot(_ o: LocalVec) -> Double {
        forward * o.forward + lateral * o.lateral + vertical * o.vertical
    }

    public static func + (l: LocalVec, r: LocalVec) -> LocalVec {
        LocalVec(forward: l.forward + r.forward, lateral: l.lateral + r.lateral, vertical: l.vertical + r.vertical)
    }

    public static func * (l: LocalVec, r: Double) -> LocalVec {
        LocalVec(forward: l.forward * r, lateral: l.lateral * r, vertical: l.vertical * r)
    }
}

/// Everything the recognizer learns about *this* player and *this* wrist.
public struct Calibration: Codable, Equatable, Sendable {
    /// Gyro reading at rest (device frame, rad/s) - "gyro baseline".
    public var gyroBias: Vec3
    /// Mean device-frame user acceleration at rest (g) - "acceleration baseline".
    public var accelBaseline: Vec3
    /// Std-dev of acceleration magnitude at rest (g); the noise floor.
    public var noiseFloor: Double
    /// Gravity direction (device frame) in the neutral pose - "orientation".
    public var neutralGravity: Vec3
    /// Gravity direction (device frame) in the guard / block pose.
    public var guardGravity: Vec3
    /// Horizontal unit vector (world frame) pointing the way the player punches.
    public var forward: Vec3
    public var hasNeutral: Bool
    public var hasGuard: Bool
    public var hasForward: Bool
    public var createdAt: TimeInterval

    public init(gyroBias: Vec3 = .zero,
                accelBaseline: Vec3 = .zero,
                noiseFloor: Double = 0.02,
                neutralGravity: Vec3 = Vec3(0, 0, -1),
                guardGravity: Vec3 = Vec3(0, -0.9, -0.43).normalized,
                forward: Vec3 = Vec3(1, 0, 0),
                hasNeutral: Bool = false,
                hasGuard: Bool = false,
                hasForward: Bool = false,
                createdAt: TimeInterval = 0) {
        self.gyroBias = gyroBias
        self.accelBaseline = accelBaseline
        self.noiseFloor = noiseFloor
        self.neutralGravity = neutralGravity
        self.guardGravity = guardGravity
        self.forward = forward
        self.hasNeutral = hasNeutral
        self.hasGuard = hasGuard
        self.hasForward = hasForward
        self.createdAt = createdAt
    }

    /// Factory defaults - good enough for development and the unit tests.
    public static let `default` = Calibration()

    public var isCalibrated: Bool { hasNeutral && hasForward }

    public var up: Vec3 { Vec3(0, 0, 1) }

    /// The player's right-hand direction (world frame): forward x up.
    public var right: Vec3 { forward.cross(up) }

    /// Project a world-frame acceleration onto the player's axes.
    public func localize(_ world: Vec3) -> LocalVec {
        LocalVec(forward: world.dot(forward), lateral: world.dot(right), vertical: world.z)
    }

    /// Build a world-frame vector from player-relative components (inverse of `localize`).
    public func world(forward f: Double, lateral l: Double, vertical v: Double) -> Vec3 {
        forward * f + right * l + Vec3(0, 0, v)
    }
}

/// Accumulates samples during the three calibration steps and produces a `Calibration`.
public struct CalibrationBuilder: Sendable {
    private var neutralCount = 0
    private var gyroSum = Vec3.zero
    private var accelSum = Vec3.zero
    private var gravitySum = Vec3.zero
    private var gyroMagSum = 0.0
    private var accelMagSum = 0.0
    private var accelMagSqSum = 0.0

    private var guardCount = 0
    private var guardGravitySum = Vec3.zero
    private var guardGyroMagSum = 0.0

    private var punchSamples: [MotionSample] = []

    public init() {}

    public var neutralSampleCount: Int { neutralCount }
    public var guardSampleCount: Int { guardCount }

    public mutating func addNeutral(_ s: MotionSample) {
        neutralCount += 1
        gyroSum = gyroSum + s.rotationRate
        accelSum = accelSum + s.userAccel
        gravitySum = gravitySum + s.gravity
        gyroMagSum += s.rotationRate.magnitude
        let a = s.userAccel.magnitude
        accelMagSum += a
        accelMagSqSum += a * a
    }

    public mutating func addGuard(_ s: MotionSample) {
        guardCount += 1
        guardGravitySum = guardGravitySum + s.gravity
        guardGyroMagSum += s.rotationRate.magnitude
    }

    public mutating func addPunch(_ s: MotionSample) {
        punchSamples.append(s)
    }

    public mutating func resetNeutral() {
        let keepGuard = (guardCount, guardGravitySum, guardGyroMagSum)
        self = CalibrationBuilder()
        (guardCount, guardGravitySum, guardGyroMagSum) = keepGuard
    }

    public mutating func resetGuard() {
        guardCount = 0
        guardGravitySum = .zero
        guardGyroMagSum = 0
    }

    public mutating func resetPunch() { punchSamples.removeAll() }

    /// The wrist was held still enough during the neutral step.
    public var neutralIsStill: Bool {
        guard neutralCount > 0 else { return false }
        let n = Double(neutralCount)
        return gyroMagSum / n < 0.45 && accelMagSum / n < 0.15
    }

    public var guardIsStill: Bool {
        guard guardCount > 0 else { return false }
        return guardGyroMagSum / Double(guardCount) < 0.6
    }

    /// Guard pose must be clearly different from the neutral pose, otherwise
    /// the player would be "blocking" all the time.
    public var guardDiffersFromNeutral: Bool {
        guard neutralCount > 0, guardCount > 0 else { return false }
        let neutral = (gravitySum / Double(neutralCount)).normalized
        let guardG = (guardGravitySum / Double(guardCount)).normalized
        return neutral.angle(to: guardG) > 25.0 * .pi / 180.0
    }

    /// World-frame forward direction from the first lobe of the captured punch, if any.
    public func forwardFromPunch(minPeak: Double = 1.5) -> Vec3? {
        guard !punchSamples.isEmpty else { return nil }
        let horizontal = punchSamples.map { Vec3($0.worldAccel.x, $0.worldAccel.y, 0) }
        var peakIndex = 0
        var peak = 0.0
        for (i, h) in horizontal.enumerated() where h.magnitude > peak {
            peak = h.magnitude
            peakIndex = i
        }
        guard peak >= minPeak else { return nil }
        let dir0 = horizontal[peakIndex].normalized
        var sum = Vec3.zero
        // Walk outwards from the peak while we stay in the same lobe.
        var i = peakIndex
        while i >= 0, horizontal[i].dot(dir0) > 0, horizontal[i].magnitude >= peak * 0.4 {
            sum = sum + horizontal[i]
            i -= 1
        }
        i = peakIndex + 1
        while i < horizontal.count, horizontal[i].dot(dir0) > 0, horizontal[i].magnitude >= peak * 0.4 {
            sum = sum + horizontal[i]
            i += 1
        }
        let f = sum.normalized
        return f == .zero ? nil : f
    }

    public var hasPunch: Bool { forwardFromPunch() != nil }

    /// Builds the calibration. Needs at least a neutral capture; guard pose and
    /// forward direction are optional and fall back to defaults.
    public func build(now: TimeInterval) -> Calibration? {
        guard neutralCount >= 10 else { return nil }
        let n = Double(neutralCount)
        var c = Calibration.default
        c.gyroBias = gyroSum / n
        c.accelBaseline = accelSum / n
        let meanMag = accelMagSum / n
        let variance = max(0, accelMagSqSum / n - meanMag * meanMag)
        c.noiseFloor = max(0.005, variance.squareRoot())
        c.neutralGravity = (gravitySum / n).normalized
        c.hasNeutral = true
        if guardCount >= 10 {
            c.guardGravity = (guardGravitySum / Double(guardCount)).normalized
            c.hasGuard = true
        }
        if let f = forwardFromPunch() {
            c.forward = f
            c.hasForward = true
        }
        c.createdAt = now
        return c
    }
}
