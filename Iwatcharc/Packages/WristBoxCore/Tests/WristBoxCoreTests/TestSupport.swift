import Foundation
@testable import WristBoxCore

/// Generates synthetic Watch motion so the whole gesture pipeline and the game
/// can be tested without any hardware.
///
/// Motion is described in *player coordinates* (forward / lateral-right / up) and
/// converted to the world frame with the calibration, exactly the inverse of what
/// the recogniser does.
struct MotionSynth {
    var calibration: Calibration
    var rate = 100.0
    var time = 1_000.0
    /// Std-dev of per-axis sensor noise (g and rad/s).
    var noise = 0.02
    var rng = SeededRNG(seed: 99)
    /// Device-frame gravity of the stream. Flat and face-up by default: far from the guard pose.
    var gravity = Vec3(0, 0, -1)

    init(calibration: Calibration = .default) {
        self.calibration = calibration
    }

    private mutating func noiseVec() -> Vec3 {
        Vec3(rng.gaussian(sigma: noise), rng.gaussian(sigma: noise), rng.gaussian(sigma: noise))
    }

    mutating func sample(local: LocalVec = LocalVec(), gyro: Vec3 = .zero) -> MotionSample {
        let world = calibration.world(forward: local.forward, lateral: local.lateral, vertical: local.vertical) + noiseVec()
        let s = MotionSample(timestamp: time, userAccel: world, gravity: gravity,
                             rotationRate: gyro + noiseVec(), worldAccel: world)
        time += 1 / rate
        return s
    }

    /// Stillness for `seconds`.
    mutating func rest(_ seconds: Double) -> [MotionSample] {
        (0..<Int(seconds * rate)).map { _ in sample() }
    }

    /// A half-sine acceleration pulse along `direction` (player coordinates), with a
    /// matching yaw-rate envelope, optionally followed by an opposite "retract" lobe.
    mutating func pulse(_ direction: LocalVec,
                        peak: Double,
                        duration: Double,
                        yaw: Double = 0,
                        retract: Double = 0) -> [MotionSample] {
        var out: [MotionSample] = []
        let dir = direction.normalized
        let n = max(2, Int(duration * rate))
        for k in 0..<n {
            let env = sin(Double.pi * (Double(k) + 0.5) / Double(n))
            out.append(sample(local: dir * (peak * env), gyro: Vec3(0, 0, yaw * env)))
        }
        if retract > 0 {
            let m = max(2, Int(duration * 1.3 * rate))
            for k in 0..<m {
                let env = sin(Double.pi * (Double(k) + 0.5) / Double(m))
                out.append(sample(local: dir * (-retract * env)))
            }
        }
        return out
    }

    // MARK: Convenience gestures

    mutating func jab(peak: Double = 2.6) -> [MotionSample] {
        pulse(LocalVec(forward: 1), peak: peak, duration: 0.12)
    }

    mutating func settle(_ seconds: Double = 0.5) -> [MotionSample] { rest(seconds) }
}

func events(for samples: [MotionSample], recognizer: GestureRecognizer) -> [GestureEvent] {
    recognizer.process(samples)
}

// MARK: - Fight helpers

/// An opponent that never attacks (for testing offence in isolation).
func passiveOpponent(health: Double = 1_000) -> OpponentProfile {
    var p = OpponentProfile.roster[0]
    p.patterns = []
    p.health = health
    p.blockChance = 0
    p.dodgeChance = 0
    p.counterChance = 0
    return p
}

/// An opponent that throws one jab, then rests for a long time.
func singleJabOpponent() -> OpponentProfile {
    var p = OpponentProfile.roster[0]
    p.patterns = [AttackPattern("test jab", [.attack(.jab)])]
    p.telegraphScale = 1.0
    p.openingChance = 0
    p.restMin = 20
    p.restMax = 20
    p.blockChance = 0
    p.dodgeChance = 0
    p.counterChance = 0
    return p
}

extension FightEngine {
    /// Advance in small steps, collecting events.
    @discardableResult
    func run(_ seconds: Double, step: Double = 1.0 / 60.0) -> [FightEvent] {
        var all: [FightEvent] = []
        var t = 0.0
        while t < seconds {
            update(step)
            all.append(contentsOf: drainEvents())
            t += step
        }
        return all
    }

    /// Run until `predicate` matches an event (or `limit` seconds pass).
    func run(until predicate: (FightEvent) -> Bool, limit: Double = 30, step: Double = 1.0 / 60.0) -> [FightEvent] {
        var all: [FightEvent] = []
        var t = 0.0
        while t < limit {
            update(step)
            let es = drainEvents()
            all.append(contentsOf: es)
            if es.contains(where: predicate) { break }
            t += step
        }
        return all
    }

    /// Start the fight and skip the countdown.
    func startAndFight() {
        start()
        run(config.firstCountdown + 0.1)
    }
}

func punchEvent(_ type: PunchType = .jab, power: Double = 0.8, accuracy: Double = 0.9) -> GestureEvent {
    .punch(PunchResult(type: type, power: power, accuracy: accuracy, speed: 0.8, confidence: 1, timestamp: 0))
}

let meta = MotionMeta(confidence: 1, timestamp: 0)
