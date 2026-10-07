import XCTest
@testable import WristBoxCore

/// CoreMotion's world heading is arbitrary and changes whenever the sensors
/// restart. The recogniser re-learns "forward" so punches never silently stop working.
final class HeadingRecoveryTests: XCTestCase {
    /// A player who is facing world -x, while the recogniser still believes forward is +x.
    private var facingBackwards: Calibration {
        var c = Calibration.default
        c.forward = Vec3(-1, 0, 0)
        return c
    }

    func testFirstPunchLocksInForwardWhenRequired() {
        let recognizer = GestureRecognizer()
        recognizer.requireForwardLock = true
        XCTAssertFalse(recognizer.forwardLocked)
        var recentered: Calibration?
        recognizer.onRecenter = { recentered = $0 }

        var synth = MotionSynth(calibration: facingBackwards)
        var samples = synth.rest(0.3)
        samples += synth.pulse(LocalVec(forward: 1), peak: 2.8, duration: 0.12)
        samples += synth.rest(0.6)
        samples += synth.pulse(LocalVec(forward: 1), peak: 2.8, duration: 0.12)
        samples += synth.rest(0.6)
        let events = recognizer.process(samples)

        XCTAssertTrue(recognizer.forwardLocked)
        XCTAssertEqual(events.count, 2, "got \(events)")
        guard case .jab? = events.first else { return XCTFail("the locking punch itself must count, got \(events)") }
        XCTAssertNotNil(recentered)
        XCTAssertGreaterThan(recognizer.calibration.forward.dot(Vec3(-1, 0, 0)), 0.98)
    }

    func testHooksAfterLockInStillMapToTheRightSides() {
        let recognizer = GestureRecognizer()
        recognizer.requireForwardLock = true
        var synth = MotionSynth(calibration: facingBackwards)
        var samples = synth.rest(0.3)
        samples += synth.pulse(LocalVec(forward: 1), peak: 2.8, duration: 0.12)
        samples += synth.rest(0.6)
        samples += synth.pulse(LocalVec(lateral: -1), peak: 3.5, duration: 0.12, yaw: 10)
        samples += synth.rest(0.6)
        samples += synth.pulse(LocalVec(lateral: 1), peak: 3.5, duration: 0.12, yaw: 10)
        samples += synth.rest(0.6)
        let events = recognizer.process(samples)
        XCTAssertEqual(events.map { $0.code }, ["JAB", "LEFT_HOOK", "RIGHT_HOOK"])
    }

    func testLockInIgnoresWeakMovementsAndVerticalBursts() {
        let recognizer = GestureRecognizer()
        recognizer.requireForwardLock = true
        var synth = MotionSynth()
        var samples = synth.rest(0.3)
        samples += synth.pulse(LocalVec(forward: 1), peak: 1.2, duration: 0.12)      // too weak
        samples += synth.rest(0.4)
        samples += synth.pulse(LocalVec(vertical: 1), peak: 3.5, duration: 0.12)     // uppercut, not horizontal
        samples += synth.rest(0.4)
        _ = recognizer.process(samples)
        XCTAssertFalse(recognizer.forwardLocked)
    }

    func testResetRequiresLockInAgain() {
        let recognizer = GestureRecognizer()
        recognizer.requireForwardLock = true
        var synth = MotionSynth()
        _ = recognizer.process(synth.rest(0.3) + synth.jab(peak: 2.8) + synth.settle())
        XCTAssertTrue(recognizer.forwardLocked)
        recognizer.reset()
        XCTAssertFalse(recognizer.forwardLocked)
    }

    func testAutoRecenterAfterTwoConsistentBackwardPunches() {
        let recognizer = GestureRecognizer()   // no lock-in required: calibration assumed good
        var recentered = 0
        recognizer.onRecenter = { _ in recentered += 1 }
        var synth = MotionSynth(calibration: facingBackwards)
        var samples = synth.rest(0.3)
        for _ in 0..<4 {
            samples += synth.pulse(LocalVec(forward: 1), peak: 4.0, duration: 0.12)
            samples += synth.rest(0.8)
        }
        let events = recognizer.process(samples)
        XCTAssertEqual(recentered, 1)
        // The first two were lost while re-learning; the last two count.
        XCTAssertEqual(events.count, 2, "got \(events)")
        XCTAssertTrue(events.allSatisfy { if case .cross = $0 { return true } else { return false } })
    }

    func testPunchRetractPairsDoNotTriggerRecenter() {
        let recognizer = GestureRecognizer()
        var recentered = 0
        recognizer.onRecenter = { _ in recentered += 1 }
        var synth = MotionSynth()
        var samples = synth.rest(0.3)
        for _ in 0..<5 {
            samples += synth.pulse(LocalVec(forward: 1), peak: 5.0, duration: 0.12, retract: 4.0)
            samples += synth.rest(0.7)
        }
        _ = recognizer.process(samples)
        XCTAssertEqual(recentered, 0)
    }

    func testNormalPlayDoesNotRecenter() {
        let recognizer = GestureRecognizer()
        var recentered = 0
        recognizer.onRecenter = { _ in recentered += 1 }
        var synth = MotionSynth()
        var samples = synth.rest(0.3)
        samples += synth.jab()
        samples += synth.rest(0.5)
        samples += synth.pulse(LocalVec(lateral: -1), peak: 3.5, duration: 0.12, yaw: 10)
        samples += synth.rest(0.5)
        samples += synth.pulse(LocalVec(vertical: 1), peak: 3.5, duration: 0.12)
        samples += synth.rest(0.5)
        _ = recognizer.process(samples)
        XCTAssertEqual(recentered, 0)
    }
}
