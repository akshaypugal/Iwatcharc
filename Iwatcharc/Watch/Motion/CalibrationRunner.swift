import Foundation
import WristBoxCore

/// Runs the guided calibration on the Watch, driven by incoming motion samples
/// (so it keeps working with the sensor clock, no timers needed):
///
///   1. neutral   (3 s)  - wrist still: acceleration baseline, orientation, gyro baseline
///   2. guard     (4 s)  - fists up and still: the block pose (first 1.2 s to get into position)
///   3. punch     (wait) - one punch: the forward direction
final class CalibrationRunner {
    private enum Phase {
        case idle
        case neutral(start: Double)
        case guardPose(start: Double)
        case punchWait(start: Double)
        case punchCapture(trigger: Double)
    }

    static let neutralDuration = 3.0
    static let guardDuration = 4.0
    static let guardSettle = 1.2
    static let punchTimeout = 15.0
    static let punchTrigger = 2.0   // g of horizontal acceleration

    /// Progress updates for the iPhone and the Watch UI (any queue).
    var onProgress: ((CalibrationProgress) -> Void)?
    /// Called once when the run ends: a calibration, or nil when it failed/cancelled.
    var onFinished: ((Calibration?) -> Void)?

    /// `start`/`cancel` come from the main thread, `feed` from the motion queue.
    private let lock = NSLock()
    private var phase = Phase.idle
    private var builder = CalibrationBuilder()
    private var recent: [MotionSample] = []
    private var lastEmitted = -1

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    private var running: Bool {
        if case .idle = phase { return false }
        return true
    }

    func start(at time: Double) {
        lock.lock()
        defer { lock.unlock() }
        builder = CalibrationBuilder()
        recent.removeAll()
        lastEmitted = -1
        phase = .neutral(start: time)
        emit(.neutral, 0, Int(Self.neutralDuration), "Hands relaxed. Keep your wrist still.")
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        guard running else { return }
        phase = .idle
        onFinished?(nil)
    }

    func feed(_ s: MotionSample) {
        lock.lock()
        defer { lock.unlock() }
        let t = s.timestamp
        switch phase {
        case .idle:
            return

        case .neutral(let start):
            builder.addNeutral(s)
            let e = max(0, t - start)
            progress(.neutral, e, Self.neutralDuration, "Hands relaxed. Keep your wrist still.")
            if e >= Self.neutralDuration {
                if builder.neutralIsStill, builder.neutralSampleCount >= 50 {
                    phase = .guardPose(start: t)
                    lastEmitted = -1
                    emit(.guardPose, 0, Int(Self.guardDuration), "Raise your fists like you're defending. Hold still.")
                } else {
                    fail("You moved. Rest your arm and keep your wrist still, then try again.")
                }
            }

        case .guardPose(let start):
            let e = max(0, t - start)
            if e >= Self.guardSettle { builder.addGuard(s) }
            progress(.guardPose, e, Self.guardDuration, "Raise your fists like you're defending. Hold still.")
            if e >= Self.guardDuration {
                if builder.guardSampleCount >= 40, builder.guardIsStill, builder.guardDiffersFromNeutral {
                    phase = .punchWait(start: t)
                    recent.removeAll()
                    emit(.punch, 0, 0, "Face your opponent and throw one straight punch.")
                } else {
                    fail("Hold your fists clearly higher than your resting pose and keep still, then try again.")
                }
            }

        case .punchWait(let start):
            recent.append(s)
            if recent.count > 30 { recent.removeFirst(recent.count - 30) }
            let horizontal = (s.worldAccel.x * s.worldAccel.x + s.worldAccel.y * s.worldAccel.y).squareRoot()
            if horizontal >= Self.punchTrigger {
                for r in recent { builder.addPunch(r) }
                phase = .punchCapture(trigger: t)
            } else if t - start > Self.punchTimeout {
                fail("No punch detected. Punch straight ahead a little harder.")
            }

        case .punchCapture(let trigger):
            builder.addPunch(s)
            if t - trigger >= 0.4 {
                if builder.hasPunch, let calibration = builder.build(now: Date().timeIntervalSince1970) {
                    phase = .idle
                    emit(.done, 1, 0, "Calibrated")
                    onFinished?(calibration)
                } else {
                    // Not a clean forward punch: wait for another.
                    builder.resetPunch()
                    recent.removeAll()
                    phase = .punchWait(start: t)
                    emit(.punch, 0, 0, "That wasn't a straight punch. Try again.")
                }
            }
        }
    }

    // MARK: Helpers

    private func progress(_ step: CalibrationStep, _ elapsed: Double, _ duration: Double, _ message: String) {
        let left = max(0, Int((duration - elapsed).rounded(.up)))
        guard left != lastEmitted else { return }
        lastEmitted = left
        emit(step, min(1, elapsed / duration), left, message)
    }

    private func emit(_ step: CalibrationStep, _ progress: Double, _ secondsLeft: Int, _ message: String) {
        onProgress?(CalibrationProgress(step: step, progress: progress, secondsLeft: secondsLeft, message: message))
    }

    private func fail(_ message: String) {
        phase = .idle
        emit(.failed, 0, 0, message)
        onFinished?(nil)
    }
}
