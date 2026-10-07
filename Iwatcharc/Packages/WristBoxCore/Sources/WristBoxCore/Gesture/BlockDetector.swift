import Foundation

/// Detects the defensive "guard" pose: the wrist held in the calibrated guard
/// orientation and (almost) still for `blockHoldTime`.
struct BlockDetector {
    var config: GestureConfig
    var guardGravity: Vec3

    private(set) var isBlocking = false
    private var candidateSince: TimeInterval?

    init(config: GestureConfig, guardGravity: Vec3) {
        self.config = config
        self.guardGravity = guardGravity
    }

    mutating func reset() {
        isBlocking = false
        candidateSince = nil
    }

    /// - Parameters:
    ///   - gravity: device-frame gravity of this sample.
    ///   - accelMag: filtered acceleration magnitude (g).
    ///   - gyroMag: filtered angular speed (rad/s).
    mutating func process(time: TimeInterval, gravity: Vec3, accelMag: Double, gyroMag: Double) -> GestureEvent? {
        let angle = gravity.angle(to: guardGravity) * 180.0 / .pi
        if isBlocking {
            if angle > config.blockExitAngleDegrees || accelMag > config.blockExitAccel {
                isBlocking = false
                candidateSince = nil
                return .blockEnd(MotionMeta(confidence: 1, timestamp: time))
            }
            return nil
        }
        let inPose = angle <= config.blockAngleDegrees
        let quiet = accelMag <= config.blockQuietAccel && gyroMag <= config.blockQuietGyro
        guard inPose, quiet else {
            candidateSince = nil
            return nil
        }
        if candidateSince == nil { candidateSince = time }
        if let since = candidateSince, time - since >= config.blockHoldTime {
            isBlocking = true
            let confidence = clamp(1.0 - 0.4 * (angle / config.blockAngleDegrees))
            return .blockStart(MotionMeta(confidence: confidence, timestamp: time))
        }
        return nil
    }
}
