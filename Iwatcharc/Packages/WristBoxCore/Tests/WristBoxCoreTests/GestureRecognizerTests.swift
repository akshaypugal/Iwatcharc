import XCTest
@testable import WristBoxCore

/// Gesture recognition from synthetic motion: every gesture, plus the edge cases
/// from the spec (weak, random, extremely fast, repeated and noisy movement).
final class GestureRecognizerTests: XCTestCase {
    private func run(_ build: (inout MotionSynth) -> [MotionSample],
                     calibration: Calibration = .default,
                     config: GestureConfig = .default,
                     gravity: Vec3? = nil) -> [GestureEvent] {
        var synth = MotionSynth(calibration: calibration)
        if let g = gravity { synth.gravity = g }
        let recognizer = GestureRecognizer(config: config, calibration: calibration)
        var samples = synth.rest(0.3)
        samples += build(&synth)
        samples += synth.rest(0.6)
        return recognizer.process(samples)
    }

    // MARK: Punches

    func testJab() {
        let events = run { $0.pulse(LocalVec(forward: 1), peak: 2.6, duration: 0.12) }
        XCTAssertEqual(events.count, 1)
        guard case .jab(let r)? = events.first else { return XCTFail("expected jab, got \(events)") }
        XCTAssertGreaterThan(r.accuracy, 0.8)
        XCTAssertGreaterThan(r.power, 0.2)
        XCTAssertGreaterThan(r.confidence, 0.6)
    }

    func testCross() {
        let events = run { $0.pulse(LocalVec(forward: 1), peak: 4.6, duration: 0.12) }
        guard case .cross? = events.first else { return XCTFail("expected cross, got \(events)") }
        XCTAssertEqual(events.count, 1)
    }

    func testPowerPunch() {
        let events = run { $0.pulse(LocalVec(forward: 1), peak: 9, duration: 0.12) }
        guard case .power(let r)? = events.first else { return XCTFail("expected power, got \(events)") }
        XCTAssertGreaterThan(r.power, 0.6)
    }

    func testStrongerPunchScoresHigherPower() {
        let jab = run { $0.pulse(LocalVec(forward: 1), peak: 2.4, duration: 0.12) }.first?.punchResult
        let cross = run { $0.pulse(LocalVec(forward: 1), peak: 4.6, duration: 0.12) }.first?.punchResult
        XCTAssertNotNil(jab)
        XCTAssertNotNil(cross)
        XCTAssertGreaterThan(cross?.power ?? 0, jab?.power ?? 1)
    }

    func testLeftHook() {
        let events = run { $0.pulse(LocalVec(lateral: -1), peak: 3.5, duration: 0.12, yaw: 10) }
        guard case .leftHook? = events.first else { return XCTFail("expected left hook, got \(events)") }
        XCTAssertEqual(events.count, 1)
    }

    func testRightHook() {
        let events = run { $0.pulse(LocalVec(lateral: 1), peak: 3.5, duration: 0.12, yaw: 10) }
        guard case .rightHook? = events.first else { return XCTFail("expected right hook, got \(events)") }
    }

    func testUppercut() {
        let events = run { $0.pulse(LocalVec(vertical: 1), peak: 3.5, duration: 0.12) }
        guard case .uppercut(let r)? = events.first else { return XCTFail("expected uppercut, got \(events)") }
        XCTAssertGreaterThan(r.accuracy, 0.8)
    }

    func testUppercutWithSomeForwardMotionStillCounts() {
        let events = run { $0.pulse(LocalVec(forward: 0.4, vertical: 0.9), peak: 3.5, duration: 0.12) }
        guard case .uppercut? = events.first else { return XCTFail("expected uppercut, got \(events)") }
    }

    // MARK: Dodges

    func testDodgeLeft() {
        let events = run { $0.pulse(LocalVec(lateral: -1), peak: 1.6, duration: 0.30, yaw: 0.5) }
        guard case .dodgeLeft? = events.first else { return XCTFail("expected dodge left, got \(events)") }
        XCTAssertEqual(events.count, 1)
    }

    func testDodgeRight() {
        let events = run { $0.pulse(LocalVec(lateral: 1), peak: 1.6, duration: 0.30, yaw: 0.5) }
        guard case .dodgeRight? = events.first else { return XCTFail("expected dodge right, got \(events)") }
    }

    func testHookIsNotMistakenForDodge() {
        // Same direction as a dodge, but with strong rotation and more acceleration.
        let events = run { $0.pulse(LocalVec(lateral: -1), peak: 3.5, duration: 0.14, yaw: 12) }
        if case .dodgeLeft? = events.first { XCTFail("hook classified as dodge") }
    }

    func testMirrorSwapsSides() {
        var config = GestureConfig.default
        config.mirror = true
        let events = run({ $0.pulse(LocalVec(lateral: -1), peak: 3.5, duration: 0.12, yaw: 10) }, config: config)
        guard case .rightHook? = events.first else { return XCTFail("expected right hook, got \(events)") }
    }

    // MARK: Block

    func testBlockStartsAfterHoldingGuardPose() {
        let guardGravity = Calibration.default.guardGravity
        let events = run({ $0.rest(0.6) }, gravity: guardGravity)
        let blocks = events.filter { if case .blockStart = $0 { return true } else { return false } }
        XCTAssertEqual(blocks.count, 1)
    }

    func testNoBlockInWrongPose() {
        let events = run({ $0.rest(1.0) })   // flat, face up
        XCTAssertTrue(events.isEmpty, "got \(events)")
    }

    func testBlockEndsWhenPoseIsLeft() {
        var synth = MotionSynth()
        synth.gravity = Calibration.default.guardGravity
        let recognizer = GestureRecognizer()
        var all = recognizer.process(synth.rest(0.6))
        synth.gravity = Vec3(0, 0, -1)   // lower the hands
        all += recognizer.process(synth.rest(0.3))
        XCTAssertTrue(all.contains { if case .blockStart = $0 { return true } else { return false } })
        XCTAssertTrue(all.contains { if case .blockEnd = $0 { return true } else { return false } })
        XCTAssertFalse(recognizer.isBlocking)
    }

    func testBlockEndsWhenPunching() {
        var synth = MotionSynth()
        synth.gravity = Calibration.default.guardGravity
        let recognizer = GestureRecognizer()
        var all = recognizer.process(synth.rest(0.6))
        all += recognizer.process(synth.pulse(LocalVec(forward: 1), peak: 4, duration: 0.12))
        all += recognizer.process(synth.rest(0.3))
        let blockEnd = all.firstIndex { if case .blockEnd = $0 { return true } else { return false } }
        XCTAssertNotNil(blockEnd)
    }

    // MARK: Edge cases

    func testWeakMovementIsIgnored() {
        let events = run { $0.pulse(LocalVec(forward: 1), peak: 0.5, duration: 0.15) }
        XCTAssertTrue(events.isEmpty, "got \(events)")
    }

    func testBorderlineMovementBelowJabThresholdIsIgnored() {
        let events = run { $0.pulse(LocalVec(forward: 1), peak: 1.4, duration: 0.12) }
        XCTAssertTrue(events.isEmpty, "got \(events)")
    }

    func testRandomMovementProducesNoGestures() {
        var synth = MotionSynth()
        synth.noise = 0.3
        let recognizer = GestureRecognizer()
        let events = recognizer.process(synth.rest(6))
        XCTAssertTrue(events.isEmpty, "got \(events)")
    }

    func testSingleSampleSpikeIsFilteredOut() {
        var synth = MotionSynth()
        var samples = synth.rest(0.3)
        samples.append(synth.sample(local: LocalVec(forward: 60)))   // sensor glitch
        samples += synth.rest(0.5)
        XCTAssertTrue(GestureRecognizer().process(samples).isEmpty)
    }

    func testExtremelyFastMovementIsRejectedAsImplausible() {
        let events = run { $0.pulse(LocalVec(forward: 1), peak: 40, duration: 0.12) }
        XCTAssertTrue(events.isEmpty, "got \(events)")
    }

    func testVeryFastButPlausibleMovementIsAPowerPunch() {
        let events = run { $0.pulse(LocalVec(forward: 1), peak: 14, duration: 0.10) }
        guard case .power? = events.first else { return XCTFail("expected power, got \(events)") }
    }

    func testRetractAfterPunchIsNotCountedAsAnotherPunch() {
        let events = run { $0.pulse(LocalVec(forward: 1), peak: 3.0, duration: 0.12, retract: 2.0) }
        XCTAssertEqual(events.count, 1, "got \(events)")
        guard case .jab? = events.first else { return XCTFail("expected jab, got \(events)") }
    }

    func testBackwardMotionIsNotAPunch() {
        let events = run { $0.pulse(LocalVec(forward: -1), peak: 4, duration: 0.12) }
        XCTAssertTrue(events.isEmpty, "got \(events)")
    }

    func testRepeatedMovementIsRateLimited() {
        var synth = MotionSynth()
        let recognizer = GestureRecognizer()
        var samples = synth.rest(0.3)
        for _ in 0..<14 {
            samples += synth.pulse(LocalVec(forward: 1), peak: 2.6, duration: 0.10)
            samples += synth.rest(0.05)
        }
        samples += synth.rest(0.5)
        let events = recognizer.process(samples)
        XCTAssertGreaterThan(events.count, 3)
        XCTAssertLessThan(events.count, 14)
        // Never more than the configured maximum in any rolling second.
        let times = events.map { $0.timestamp }
        for t in times {
            let inWindow = times.filter { $0 <= t && $0 > t - 1.0 }.count
            XCTAssertLessThanOrEqual(inWindow, GestureConfig.default.maxPunchesPerSecond)
        }
    }

    func testNoisySensorStillRecognisesAJab() {
        var synth = MotionSynth()
        synth.noise = 0.12
        var samples = synth.rest(0.4)
        samples.append(synth.sample(local: LocalVec(forward: 10)))   // glitch in the noise
        samples += synth.rest(0.3)
        samples += synth.pulse(LocalVec(forward: 1), peak: 3.0, duration: 0.12)
        samples += synth.rest(0.5)
        let events = GestureRecognizer().process(samples)
        XCTAssertEqual(events.count, 1, "got \(events)")
        guard case .jab? = events.first else { return XCTFail("expected jab, got \(events)") }
    }

    func testShakeProducesGuardBreak() {
        var synth = MotionSynth()
        var samples = synth.rest(0.3)
        for i in 0..<6 {
            let sign: Double = i % 2 == 0 ? 1 : -1
            samples += synth.pulse(LocalVec(lateral: sign), peak: 6, duration: 0.10)
        }
        samples += synth.rest(0.5)
        let events = GestureRecognizer().process(samples)
        XCTAssertTrue(events.contains { if case .guardBreak = $0 { return true } else { return false } },
                      "got \(events)")
    }

    func testPunchRetractPairsAreNotAShake() {
        var synth = MotionSynth()
        let recognizer = GestureRecognizer()
        var samples = synth.rest(0.3)
        for _ in 0..<3 {
            samples += synth.pulse(LocalVec(forward: 1), peak: 5, duration: 0.12, retract: 2.5)
            samples += synth.rest(0.4)
        }
        let events = recognizer.process(samples)
        XCTAssertFalse(events.contains { if case .guardBreak = $0 { return true } else { return false } })
    }

    // MARK: Calibration

    func testRotatedCalibrationStillRecognisesAJab() {
        var cal = Calibration.default
        cal.forward = Vec3(0, 1, 0)   // the player faces world +y
        cal.hasForward = true
        let events = run({ $0.pulse(LocalVec(forward: 1), peak: 2.6, duration: 0.12) }, calibration: cal)
        guard case .jab? = events.first else { return XCTFail("expected jab, got \(events)") }
    }

    func testCalibrationBuilderFindsForwardAxisAndBias() {
        var cal = Calibration.default
        cal.forward = Vec3(0, 1, 0)
        var synth = MotionSynth(calibration: cal)
        var builder = CalibrationBuilder()
        for s in synth.rest(1.5) { builder.addNeutral(s) }
        synth.gravity = Calibration.default.guardGravity
        for s in synth.rest(1.5) { builder.addGuard(s) }
        for s in synth.pulse(LocalVec(forward: 1), peak: 3.0, duration: 0.12, retract: 1.5) { builder.addPunch(s) }

        XCTAssertTrue(builder.neutralIsStill)
        XCTAssertTrue(builder.guardIsStill)
        XCTAssertTrue(builder.guardDiffersFromNeutral)
        XCTAssertTrue(builder.hasPunch)
        guard let built = builder.build(now: 5) else { return XCTFail("no calibration") }
        XCTAssertTrue(built.isCalibrated)
        XCTAssertTrue(built.hasGuard)
        XCTAssertGreaterThan(built.forward.dot(Vec3(0, 1, 0)), 0.98)
        XCTAssertLessThan(built.noiseFloor, 0.1)
        XCTAssertLessThan(built.gyroBias.magnitude, 0.1)
    }

    func testCalibrationRejectsMovingNeutral() {
        var synth = MotionSynth()
        synth.noise = 0.02
        var builder = CalibrationBuilder()
        for s in synth.pulse(LocalVec(forward: 1), peak: 2, duration: 1.5, yaw: 3) { builder.addNeutral(s) }
        XCTAssertFalse(builder.neutralIsStill)
    }

    func testCalibrationNeedsEnoughNeutralSamples() {
        var builder = CalibrationBuilder()
        var synth = MotionSynth()
        for s in synth.rest(0.05) { builder.addNeutral(s) }
        XCTAssertNil(builder.build(now: 0))
    }

    // MARK: Classifier directly

    func testClassifierRejectsWeakAndImplausible() {
        let dir = LocalVec(forward: 1)
        XCTAssertEqual(GestureClassifier.classify(BurstFeatures(peak: 0.3, direction: dir, duration: 0.1, peakGyro: 0, peakYaw: 0, speed: 2), config: .default),
                       .rejected(.weak))
        XCTAssertEqual(GestureClassifier.classify(BurstFeatures(peak: 30, direction: dir, duration: 0.1, peakGyro: 0, peakYaw: 0, speed: 2), config: .default),
                       .rejected(.implausible))
        XCTAssertEqual(GestureClassifier.classify(BurstFeatures(peak: 3, direction: dir, duration: 0.01, peakGyro: 0, peakYaw: 0, speed: 2), config: .default),
                       .rejected(.tooShort))
        XCTAssertEqual(GestureClassifier.classify(BurstFeatures(peak: 3, direction: dir, duration: 2.0, peakGyro: 0, peakYaw: 0, speed: 2), config: .default),
                       .rejected(.tooLong))
    }

    func testClassifierRejectsAmbiguousDirection() {
        // Diagonal in all three axes: no axis dominates.
        let dir = LocalVec(forward: 0.57, lateral: 0.57, vertical: 0.59).normalized
        let result = GestureClassifier.classify(BurstFeatures(peak: 3, direction: dir, duration: 0.1, peakGyro: 1, peakYaw: 1, speed: 2), config: .default)
        XCTAssertEqual(result, .rejected(.ambiguous))
    }

    func testSloppyDirectionScoresLowAccuracy() {
        let straight = BurstFeatures(peak: 3, direction: LocalVec(forward: 1), duration: 0.1, peakGyro: 1, peakYaw: 0, speed: 2)
        let sloppy = BurstFeatures(peak: 3, direction: LocalVec(forward: 0.7, lateral: 0.5, vertical: 0.3).normalized, duration: 0.1, peakGyro: 1, peakYaw: 0, speed: 2)
        guard case .accepted(_, _, let a1, _, _) = GestureClassifier.classify(straight, config: .default),
              case .accepted(_, _, let a2, _, _) = GestureClassifier.classify(sloppy, config: .default) else {
            return XCTFail("expected both accepted")
        }
        XCTAssertGreaterThan(a1, a2)
    }

    func testRecognizerReportsDecisionsForDebugging() {
        var decisions: [DecisionRecord] = []
        var synth = MotionSynth()
        let recognizer = GestureRecognizer()
        recognizer.onDecision = { decisions.append($0) }
        _ = recognizer.process(synth.rest(0.3) + synth.jab() + synth.settle())
        XCTAssertEqual(decisions.last?.label, "JAB")
        XCTAssertEqual(recognizer.lastDecision?.accepted, true)
    }
}
