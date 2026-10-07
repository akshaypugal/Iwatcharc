import Foundation

/// One accepted or rejected burst, for the Debug screen and the event log.
public struct DecisionRecord: Equatable, Sendable {
    public var time: TimeInterval
    public var label: String
    public var accepted: Bool
    public var peak: Double
    public var confidence: Double
    public var reason: RejectionReason?

    public init(time: TimeInterval, label: String, accepted: Bool, peak: Double, confidence: Double, reason: RejectionReason? = nil) {
        self.time = time
        self.label = label
        self.accepted = accepted
        self.peak = peak
        self.confidence = confidence
        self.reason = reason
    }
}

/// Latest filtered values, exposed for debugging.
public struct LiveReading: Equatable, Sendable {
    public var local = LocalVec()
    public var magnitude = 0.0
    public var yawRate = 0.0
    public var gyroMagnitude = 0.0
    public init() {}
}

/// The motion-processing pipeline:
///
///     raw sample -> noise filtering -> baseline calibration -> motion vector
///               -> peak detection -> direction detection -> classification
///               -> validation (cooldown, rate limit, retract, shake) -> GestureEvent
///
/// It is a plain state machine: feed it `MotionSample`s in time order and it
/// returns zero or more `GestureEvent`s. It knows nothing about boxing.
public final class GestureRecognizer {
    public var config: GestureConfig {
        didSet {
            blockDetector.config = config
            accelEMA.alpha = config.smoothing
            gyroEMA.alpha = config.smoothing
            yawEMA.alpha = config.smoothing
        }
    }

    public var calibration: Calibration {
        didSet { blockDetector.guardGravity = calibration.guardGravity }
    }

    /// When true, the first strong horizontal punch after `reset()` defines "forward"
    /// (the Watch uses this because the world heading changes whenever sensors restart).
    public var requireForwardLock = false {
        didSet { forwardLocked = !requireForwardLock }
    }

    /// True once the forward direction is trusted for this session.
    public private(set) var forwardLocked = true

    /// Called when the recogniser re-learned the forward direction.
    public var onRecenter: ((Calibration) -> Void)?

    /// Called for every accepted or rejected burst.
    public var onDecision: ((DecisionRecord) -> Void)?

    public private(set) var lastDecision: DecisionRecord?
    public private(set) var live = LiveReading()
    public var isBlocking: Bool { blockDetector.isBlocking }

    // MARK: State
    private enum Phase { case idle, burst, refractory }

    private struct Burst {
        var startTime = 0.0
        var peak = 0.0
        var peakTime = 0.0
        var dirSum = LocalVec()
        var speedIntegral = 0.0
        var peakGyro = 0.0
        var peakYaw = 0.0

        mutating func begin(at t: Double) {
            self = Burst()
            startTime = t
        }

        mutating func add(time: Double, local: LocalVec, mag: Double, yaw: Double, gyro: Double, dt: Double) {
            if mag > peak {
                peak = mag
                peakTime = time
            }
            dirSum = dirSum + local * mag
            speedIntegral += mag * 9.80665 * dt
            peakGyro = max(peakGyro, gyro)
            peakYaw = max(peakYaw, abs(yaw))
        }
    }

    private struct ShakeBurst {
        var time: Double
        var axis: Int
        var sign: Int
        var peak: Double
    }

    private var median = MedianFilter3()
    private var accelEMA: Vec3EMA
    private var gyroEMA: EMAFilter
    private var yawEMA: EMAFilter
    private var blockDetector: BlockDetector

    private var phase = Phase.idle
    private var burst = Burst()
    private var lockoutUntil = 0.0
    private var lastBurstDirection = LocalVec()
    private var lastTimestamp: TimeInterval?

    private var lastAccepted: [GestureKind: TimeInterval] = [:]
    private var recentPunchTimes: [TimeInterval] = []
    private var lastMotion: (time: TimeInterval, dir: LocalVec, kind: GestureKind)?
    private var shakeBursts: [ShakeBurst] = []
    private var shakeLockoutUntil = 0.0
    private var recenterCandidates: [(time: Double, dir: Vec3)] = []

    public init(config: GestureConfig = .default, calibration: Calibration = .default) {
        self.config = config
        self.calibration = calibration
        accelEMA = Vec3EMA(alpha: config.smoothing)
        gyroEMA = EMAFilter(alpha: config.smoothing)
        yawEMA = EMAFilter(alpha: config.smoothing)
        blockDetector = BlockDetector(config: config, guardGravity: calibration.guardGravity)
    }

    /// Forget all motion state (call when a fight starts or the stream restarts).
    public func reset() {
        median.reset()
        accelEMA.reset()
        gyroEMA.reset()
        yawEMA.reset()
        blockDetector.reset()
        phase = .idle
        burst = Burst()
        lockoutUntil = 0
        lastBurstDirection = LocalVec()
        lastTimestamp = nil
        lastAccepted.removeAll()
        recentPunchTimes.removeAll()
        lastMotion = nil
        shakeBursts.removeAll()
        shakeLockoutUntil = 0
        recenterCandidates.removeAll()
        forwardLocked = !requireForwardLock
    }

    public func process(_ samples: [MotionSample]) -> [GestureEvent] {
        var out: [GestureEvent] = []
        for s in samples { out.append(contentsOf: process(s)) }
        return out
    }

    // MARK: Pipeline

    public func process(_ s: MotionSample) -> [GestureEvent] {
        var events: [GestureEvent] = []
        let now = s.timestamp

        if let last = lastTimestamp, now < last - 1.0 { reset() }   // clock jumped backwards
        let dt: Double
        if let last = lastTimestamp {
            dt = min(max(now - last, 0.001), 0.05)
        } else {
            dt = 0.01
        }
        lastTimestamp = now

        // 1. Noise filtering: median kills single-sample spikes, EMA smooths the rest.
        let acc = accelEMA.apply(median.apply(s.worldAccel))

        // 2. Baseline calibration: remove gyro bias; yaw = rotation about the vertical axis.
        let gyro = s.rotationRate - calibration.gyroBias
        var up = (-s.gravity).normalized
        if up == .zero { up = Vec3(0, 0, 1) }
        let yaw = yawEMA.apply(gyro.dot(up))
        let gyroMag = gyroEMA.apply(gyro.magnitude)

        // 3. Motion vector in player coordinates.
        let local = calibration.localize(acc)
        let mag = acc.magnitude
        live = LiveReading()
        live.local = local
        live.magnitude = mag
        live.yawRate = yaw
        live.gyroMagnitude = gyroMag

        // Guard pose runs alongside the punch detector.
        if let b = blockDetector.process(time: now, gravity: s.gravity, accelMag: mag, gyroMag: gyroMag) {
            events.append(b)
            record(DecisionRecord(time: now, label: b.code, accepted: true, peak: mag, confidence: b.confidence))
        }

        // 4. Peak detection.
        let startThreshold = max(config.startThreshold, calibration.noiseFloor * 6)
        switch phase {
        case .idle:
            if mag >= startThreshold, now >= lockoutUntil {
                burst.begin(at: now)
                burst.add(time: now, local: local, mag: mag, yaw: yaw, gyro: gyroMag, dt: dt)
                phase = .burst
            }
        case .burst:
            burst.add(time: now, local: local, mag: mag, yaw: yaw, gyro: gyroMag, dt: dt)
            if now - burst.startTime > config.maxDuration {
                record(DecisionRecord(time: now, label: "REJECT tooLong", accepted: false, peak: burst.peak, confidence: 0, reason: .tooLong))
                phase = .refractory
                lockoutUntil = now + 0.1
            } else if mag < burst.peak * config.peakDropRatio {
                events.append(contentsOf: finalizeBurst(now: now))
                phase = .refractory
            }
        case .refractory:
            if now >= lockoutUntil {
                if mag < startThreshold {
                    phase = .idle
                } else if local.normalized.dot(lastBurstDirection) < -0.5 {
                    // Continuous oscillation (shaking, or a punch flowing into its
                    // retract): the opposite lobe starts without a quiet gap.
                    burst.begin(at: now)
                    burst.add(time: now, local: local, mag: mag, yaw: yaw, gyro: gyroMag, dt: dt)
                    phase = .burst
                }
            }
        }
        return events
    }

    // MARK: Burst finalisation

    private func finalizeBurst(now: TimeInterval) -> [GestureEvent] {
        var dir = burst.dirSum.normalized
        // Lock in the forward direction from the first strong horizontal punch.
        if !forwardLocked, burst.peak >= config.lockInMinPeak, burst.peak <= config.maxPeak,
           let h = horizontalWorldDirection(of: dir, minFraction: 0.7) {
            let world = calibration.world(forward: dir.forward, lateral: dir.lateral, vertical: dir.vertical)
            calibration.forward = h
            calibration.hasForward = true
            forwardLocked = true
            dir = calibration.localize(world).normalized
            onRecenter?(calibration)
        }
        lastBurstDirection = dir
        let features = BurstFeatures(peak: burst.peak,
                                     direction: dir,
                                     duration: now - burst.startTime,
                                     peakGyro: burst.peakGyro,
                                     peakYaw: burst.peakYaw,
                                     speed: burst.speedIntegral * config.speedCompensation)
        lockoutUntil = now + 0.03

        // Shake / guard break: several strong alternating bursts on one axis.
        if burst.peak >= config.shakeMinPeak, burst.peak <= config.maxPeak,
           registerShake(direction: dir, peak: burst.peak, time: now) {
            shakeLockoutUntil = now + config.shakeLockout
            let meta = MotionMeta(confidence: 0.9, timestamp: burst.peakTime)
            record(DecisionRecord(time: now, label: "GUARD_BREAK", accepted: true, peak: burst.peak, confidence: 0.9))
            return [.guardBreak(meta)]
        }

        switch GestureClassifier.classify(features, config: config) {
        case .rejected(let reason):
            record(DecisionRecord(time: now, label: "REJECT \(reason.rawValue)", accepted: false, peak: burst.peak, confidence: 0, reason: reason))
            considerRecenter(reason: reason, direction: dir, now: now)
            return []

        case .accepted(let kind, let power, let accuracy, let speed, let confidence):
            if let reason = validate(kind: kind, direction: dir, now: now) {
                record(DecisionRecord(time: now, label: "REJECT \(reason.rawValue)", accepted: false, peak: burst.peak, confidence: confidence, reason: reason))
                return []
            }
            lastAccepted[kind] = now
            lastMotion = (now, dir, kind)
            if kind.isPunch { recentPunchTimes.append(now) }
            let event = makeEvent(kind: kind, power: power, accuracy: accuracy, speed: speed,
                                  confidence: confidence, time: burst.peakTime)
            record(DecisionRecord(time: now, label: event.code, accepted: true, peak: burst.peak, confidence: confidence))
            return [event]
        }
    }

    /// World-frame horizontal unit vector of a player-relative direction, if it is mostly horizontal.
    private func horizontalWorldDirection(of d: LocalVec, minFraction: Double) -> Vec3? {
        let w = calibration.world(forward: d.forward, lateral: d.lateral, vertical: d.vertical)
        let h = Vec3(w.x, w.y, 0)
        guard w.magnitude > 1e-9, h.magnitude / w.magnitude >= minFraction else { return nil }
        return h.normalized
    }

    /// Two strong punches in the same horizontal direction that were rejected as
    /// backwards/ambiguous mean the player is facing another way: re-learn forward.
    private func considerRecenter(reason: RejectionReason, direction d: LocalVec, now: TimeInterval) {
        guard config.autoRecenter, reason == .wrongDirection || reason == .ambiguous,
              burst.peak >= config.crossMin, burst.peak <= config.maxPeak else { return }
        // Ignore the arm coming back after a punch.
        if let lm = lastMotion, now - lm.time < config.recovery(for: lm.kind) * 1.5 { return }
        guard let h = horizontalWorldDirection(of: d, minFraction: 0.7) else { return }
        recenterCandidates.removeAll { now - $0.time > config.recenterWindow }
        recenterCandidates.append((now, h))
        guard recenterCandidates.count >= 2 else { return }
        let last = recenterCandidates[recenterCandidates.count - 1].dir
        let prev = recenterCandidates[recenterCandidates.count - 2].dir
        if last.dot(prev) >= cos(config.recenterAngleDegrees * .pi / 180) {
            calibration.forward = (last + prev).normalized
            calibration.hasForward = true
            forwardLocked = true
            recenterCandidates.removeAll()
            lastMotion = nil
            onRecenter?(calibration)
        }
    }

    /// Anti-cheat: cooldown, rate limit, retract detection, post-shake lockout.
    private func validate(kind: GestureKind, direction: LocalVec, now: TimeInterval) -> RejectionReason? {
        if now < shakeLockoutUntil { return .lockout }
        if let last = lastAccepted[kind], now - last < config.cooldown(for: kind) { return .cooldown }
        if kind.isPunch {
            recentPunchTimes.removeAll { now - $0 > 1.0 }
            if recentPunchTimes.count >= config.maxPunchesPerSecond { return .rateLimited }
        }
        if let lm = lastMotion, now - lm.time < config.recovery(for: lm.kind),
           lm.dir.dot(direction) < config.retractDot {
            return .retract
        }
        return nil
    }

    /// A shake is several strong bursts of *similar* strength alternating along one
    /// axis. The similarity test keeps normal punch/retract pairs (retract is much
    /// weaker than the punch) from looking like a shake.
    private func registerShake(direction d: LocalVec, peak: Double, time: TimeInterval) -> Bool {
        let comps = [d.forward, d.lateral, d.vertical]
        var axis = 0
        for i in 1..<3 where abs(comps[i]) > abs(comps[axis]) { axis = i }
        let sign = comps[axis] >= 0 ? 1 : -1
        shakeBursts.append(ShakeBurst(time: time, axis: axis, sign: sign, peak: peak))
        shakeBursts.removeAll { time - $0.time > config.shakeWindow }
        guard shakeBursts.count >= config.shakeBursts else { return false }
        let recent = Array(shakeBursts.suffix(config.shakeBursts))
        let sameAxis = recent.allSatisfy { $0.axis == recent[0].axis }
        var alternating = true
        var similar = true
        for i in 1..<recent.count {
            if recent[i].sign == recent[i - 1].sign { alternating = false }
            let lo = min(recent[i].peak, recent[i - 1].peak)
            let hi = max(recent[i].peak, recent[i - 1].peak)
            if hi <= 0 || lo / hi < 0.65 { similar = false }
        }
        if sameAxis && alternating && similar {
            shakeBursts.removeAll()
            return true
        }
        return false
    }

    private func makeEvent(kind: GestureKind, power: Double, accuracy: Double, speed: Double,
                           confidence: Double, time: TimeInterval) -> GestureEvent {
        if let type = kind.punchType {
            return .punch(PunchResult(type: type, power: power, accuracy: accuracy, speed: speed,
                                      confidence: confidence, timestamp: time))
        }
        let meta = MotionMeta(confidence: confidence, timestamp: time)
        return kind == .dodgeLeft ? .dodgeLeft(meta) : .dodgeRight(meta)
    }

    private func record(_ d: DecisionRecord) {
        lastDecision = d
        onDecision?(d)
    }
}
