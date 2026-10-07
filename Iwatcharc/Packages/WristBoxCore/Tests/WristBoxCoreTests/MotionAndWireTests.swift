import XCTest
@testable import WristBoxCore

final class MotionAndWireTests: XCTestCase {
    // MARK: Filters

    func testMedianFilterRemovesIsolatedSpike() {
        var f = MedianFilter3()
        _ = f.apply(Vec3(0.1, 0, 0))
        _ = f.apply(Vec3(0.1, 0, 0))
        let spike = f.apply(Vec3(50, 0, 0))
        XCTAssertLessThan(spike.x, 1)
        let after = f.apply(Vec3(0.1, 0, 0))
        XCTAssertLessThan(after.x, 1)
    }

    func testMedianFilterKeepsSustainedMotion() {
        var f = MedianFilter3()
        var last = Vec3.zero
        for _ in 0..<5 { last = f.apply(Vec3(3, 0, 0)) }
        XCTAssertEqual(last.x, 3, accuracy: 1e-9)
    }

    func testEMASmoothsTowardInput() {
        var f = EMAFilter(alpha: 0.5)
        XCTAssertEqual(f.apply(10), 10)
        XCTAssertEqual(f.apply(0), 5, accuracy: 1e-9)
        XCTAssertEqual(f.apply(0), 2.5, accuracy: 1e-9)
    }

    // MARK: World frame

    private let r90x = RotationMatrix(1, 0, 0,
                                      0, 0, -1,
                                      0, 1, 0)

    func testWorldMapperDetectsWorldToDeviceMatrix() {
        var mapper = WorldFrameMapper()
        let world = Vec3(1, 2, 3)
        let device = r90x.multiply(world)                 // device = R * world
        let gravityDevice = r90x.multiply(Vec3(0, 0, -1))
        let mapped = mapper.toWorld(device, rotation: r90x, gravityDevice: gravityDevice)
        XCTAssertEqual(mapped.x, 1, accuracy: 1e-9)
        XCTAssertEqual(mapped.y, 2, accuracy: 1e-9)
        XCTAssertEqual(mapped.z, 3, accuracy: 1e-9)
        XCTAssertEqual(mapper.best, .worldToDevice)
    }

    func testWorldMapperDetectsDeviceToWorldMatrix() {
        var mapper = WorldFrameMapper()
        let m = RotationMatrix(1, 0, 0,
                               0, 0, 1,
                               0, -1, 0)                  // device -> world
        let device = Vec3(1, -3, 2)
        let gravityDevice = Vec3(0, 1, 0)                 // m * g = (0, 0, -1)
        let mapped = mapper.toWorld(device, rotation: m, gravityDevice: gravityDevice)
        XCTAssertEqual(mapped.x, 1, accuracy: 1e-9)
        XCTAssertEqual(mapped.y, 2, accuracy: 1e-9)
        XCTAssertEqual(mapped.z, 3, accuracy: 1e-9)
        XCTAssertEqual(mapper.best, .deviceToWorld)
    }

    func testWorldMapperLocksAfterEnoughSamples() {
        var mapper = WorldFrameMapper()
        mapper.lockAfter = 5
        let g = r90x.multiply(Vec3(0, 0, -1))
        for _ in 0..<6 { _ = mapper.toWorld(Vec3(1, 0, 0), rotation: r90x, gravityDevice: g) }
        XCTAssertEqual(mapper.locked, .worldToDevice)
    }

    // MARK: Calibration model

    func testLocalizeAndWorldAreInverse() {
        var cal = Calibration.default
        cal.forward = Vec3(0, 1, 0)
        let w = cal.world(forward: 2, lateral: -1, vertical: 0.5)
        let l = cal.localize(w)
        XCTAssertEqual(l.forward, 2, accuracy: 1e-9)
        XCTAssertEqual(l.lateral, -1, accuracy: 1e-9)
        XCTAssertEqual(l.vertical, 0.5, accuracy: 1e-9)
    }

    func testCalibrationCodableRoundTrip() throws {
        var cal = Calibration.default
        cal.hasNeutral = true
        cal.gyroBias = Vec3(0.01, -0.02, 0.003)
        let data = try JSONEncoder().encode(cal)
        let back = try JSONDecoder().decode(Calibration.self, from: data)
        XCTAssertEqual(back, cal)
    }

    // MARK: Latency

    func testClockSyncEstimatesOffset() {
        var sync = ClockSync()
        // Watch clock is 5 s ahead; 20 ms each way.
        sync.addSample(pingSent: 100.0, watchTime: 105.02, pongReceived: 100.04)
        XCTAssertEqual(sync.offset, 5.0, accuracy: 1e-6)
        XCTAssertEqual(sync.toPhoneTime(105.5), 100.5, accuracy: 1e-6)
        XCTAssertTrue(sync.isSynced)
    }

    func testClockSyncPrefersLowRoundTrip() {
        var sync = ClockSync()
        sync.addSample(pingSent: 0, watchTime: 5.4, pongReceived: 0.5)     // slow, asymmetric
        let rough = sync.offset
        sync.addSample(pingSent: 10, watchTime: 15.01, pongReceived: 10.02) // fast, accurate
        XCTAssertEqual(sync.offset, 5.0, accuracy: 0.001)
        XCTAssertNotEqual(rough, sync.offset)
    }

    func testLatencyTrackerStats() {
        var t = LatencyTracker(capacity: 10)
        [10.0, 20, 30].forEach { t.record(milliseconds: $0) }
        let s = t.stats
        XCTAssertEqual(s.last, 30)
        XCTAssertEqual(s.average, 20, accuracy: 1e-9)
        XCTAssertEqual(s.minimum, 10)
        XCTAssertEqual(s.maximum, 30)
        XCTAssertEqual(s.count, 3)
    }

    func testLatencyTrackerCapacityAndNegativeClamp() {
        var t = LatencyTracker(capacity: 3)
        for i in 0..<10 { t.record(milliseconds: Double(i)) }
        t.record(milliseconds: -5)
        t.record(milliseconds: .nan)
        XCTAssertEqual(t.stats.minimum, 0)   // negative clamped, NaN ignored
        XCTAssertEqual(t.stats.count, 11)
    }

    // MARK: Wire protocol

    private func roundTrip(_ m: WireMessage, file: StaticString = #filePath, line: UInt = #line) {
        guard let back = WireMessage(dictionary: m.dictionary) else {
            return XCTFail("failed to decode \(m)", file: file, line: line)
        }
        XCTAssertEqual(back, m, file: file, line: line)
    }

    func testWireRoundTripGestures() {
        let r = PunchResult(type: .cross, power: 0.7, accuracy: 0.9, speed: 0.6, confidence: 0.88, timestamp: 12.5)
        roundTrip(.gesture(.cross(r), seq: 4, sensorTime: 12.5, sentTime: 12.6))
        for type in PunchType.allCases {
            var p = r
            p.type = type
            roundTrip(.gesture(.punch(p), seq: 1, sensorTime: 12.5, sentTime: 13))
        }
        let m = MotionMeta(confidence: 0.77, timestamp: 3)
        roundTrip(.gesture(.dodgeLeft(m), seq: 1, sensorTime: 3, sentTime: 3.1))
        roundTrip(.gesture(.dodgeRight(m), seq: 2, sensorTime: 3, sentTime: 3.1))
        roundTrip(.gesture(.blockStart(m), seq: 3, sensorTime: 3, sentTime: 3.1))
        roundTrip(.gesture(.blockEnd(m), seq: 4, sensorTime: 3, sentTime: 3.1))
        roundTrip(.gesture(.guardBreak(m), seq: 5, sensorTime: 3, sentTime: 3.1))
    }

    func testWireRoundTripControlMessages() {
        roundTrip(.heartbeat(seq: 9, sentTime: 100, mode: .fight))
        roundTrip(.ping(id: 3, sentTime: 55))
        roundTrip(.pong(id: 3, pingSentTime: 55, watchTime: 60))
        roundTrip(.haptic(.perfectPunch))
        roundTrip(.decision(time: 5, label: "JAB", peak: 2.4, confidence: 0.9))
        roundTrip(.rawBatch(RawBatch(values: [1, 2, 3, 4, 5, 6, 7])))
        roundTrip(.state(GameStateSummary(phase: .fighting, round: 2, totalRounds: 3, remaining: 41.5, combo: 4, specialReady: true, sentTime: 9)))
        roundTrip(.calibrationProgress(CalibrationProgress(step: .neutral, progress: 0.4, secondsLeft: 2, message: "Hold still")))
        roundTrip(.calibrationResult(Calibration.default))
    }

    func testWireRoundTripCommands() {
        roundTrip(.command(.setMode(.practice)))
        roundTrip(.command(.startCalibration))
        roundTrip(.command(.cancelCalibration))
        roundTrip(.command(.setDebugStream(true)))
        roundTrip(.command(.setLocalHaptics(false)))
        roundTrip(.command(.setCalibration(Calibration.default)))
        var cfg = GestureConfig.default
        cfg.jabMin = 2.2
        roundTrip(.command(.setConfig(cfg)))
    }

    func testWireIgnoresMalformedMessages() {
        XCTAssertNil(WireMessage(dictionary: [:]))
        XCTAssertNil(WireMessage(dictionary: ["k": "nonsense"]))
        XCTAssertNil(WireMessage(dictionary: ["k": "g"]))
        XCTAssertNil(WireMessage(dictionary: ["k": "g", "n": "JAB"]))
        XCTAssertNil(WireMessage(dictionary: ["k": "g", "n": "WHAT", "seq": 1, "st": 1.0, "tx": 1.0]))
        XCTAssertNil(WireMessage(dictionary: ["k": "cmd", "c": "mode", "m": "bogus"]))
        XCTAssertNil(WireMessage(dictionary: ["k": "state", "d": Data([1, 2, 3])]))
        XCTAssertNil(WireMessage(dictionary: ["k": "haptic", "h": "unknown"]))
    }

    func testWireAcceptsIntegersWhereDoublesAreExpected() {
        // WatchConnectivity may hand back NSNumber-bridged ints for whole values.
        let d: [String: Any] = ["k": "g", "n": "JAB", "seq": 1, "st": 5, "tx": 6, "c": 1, "p": 1, "a": 1, "s": 1]
        guard case .gesture(let e, _, let sensor, _)? = WireMessage(dictionary: d) else {
            return XCTFail("did not decode")
        }
        XCTAssertEqual(sensor, 5)
        XCTAssertEqual(e.punchResult?.type, .jab)
    }

    func testRawBatchLastSample() {
        let s = MotionSample(timestamp: 7, userAccel: Vec3(1, 2, 3), gravity: Vec3(0, 0, -1),
                             rotationRate: Vec3(4, 5, 6), worldAccel: .zero)
        let b = RawBatch(samples: [s, s])
        XCTAssertEqual(b.count, 2)
        XCTAssertEqual(b.last?.accel, Vec3(1, 2, 3))
        XCTAssertEqual(b.last?.gyro, Vec3(4, 5, 6))
    }

    // MARK: Simulated controller

    func testSimulatedControllerProducesEveryInput() {
        var sim = SimulatedController(seed: 3)
        for input in SimulatedInput.allCases {
            let e = sim.event(for: input, at: 10)
            switch input {
            case .jab: XCTAssertEqual(e.punchResult?.type, .jab)
            case .cross: XCTAssertEqual(e.punchResult?.type, .cross)
            case .leftHook: XCTAssertEqual(e.punchResult?.type, .leftHook)
            case .rightHook: XCTAssertEqual(e.punchResult?.type, .rightHook)
            case .uppercut: XCTAssertEqual(e.punchResult?.type, .uppercut)
            case .power: XCTAssertEqual(e.punchResult?.type, .power)
            case .dodgeLeft: XCTAssertEqual(e.code, "DODGE_LEFT")
            case .dodgeRight: XCTAssertEqual(e.code, "DODGE_RIGHT")
            case .block: XCTAssertEqual(e.code, "BLOCK")
            case .special: XCTAssertEqual(e.code, "GUARD_BREAK")
            }
            XCTAssertEqual(e.timestamp, 10)
        }
        XCTAssertEqual(sim.releaseBlock(at: 11).code, "BLOCK_END")
    }

    func testSimulatedPunchQualityIsClamped() {
        var sim = SimulatedController(seed: 1, quality: 0.99, jitter: 0.5)
        for _ in 0..<200 {
            let r = sim.punch(.jab)
            XCTAssertTrue((0...1).contains(r.power))
            XCTAssertTrue((0...1).contains(r.accuracy))
            XCTAssertTrue((0...1).contains(r.speed))
        }
    }

    func testGestureEventTimestampRewrite() {
        let e = GestureEvent.jab(PunchResult(type: .jab, power: 1, accuracy: 1, speed: 1, timestamp: 1))
        XCTAssertEqual(e.withTimestamp(9).timestamp, 9)
        XCTAssertEqual(GestureEvent.blockStart(MotionMeta(timestamp: 1)).withTimestamp(4).timestamp, 4)
    }
}

final class SyncContextTests: XCTestCase {
    func testRoundTrip() {
        var cal = Calibration.default
        cal.hasNeutral = true
        cal.forward = Vec3(0, 1, 0)
        var cfg = GestureConfig.default
        cfg.crossMin = 3.9
        let ctx = SyncContext(calibration: cal, config: cfg, localHaptics: false)
        XCTAssertEqual(SyncContext(dictionary: ctx.dictionary), ctx)
    }

    func testPartialOrForeignDictionaries() {
        XCTAssertNil(SyncContext(dictionary: [:]))
        XCTAssertNil(SyncContext(dictionary: ["k": "other"]))
        let ctx = SyncContext(dictionary: ["k": "ctx", "cal": Data([1, 2, 3])])
        XCTAssertEqual(ctx?.calibration, .default)
        XCTAssertEqual(ctx?.config, .default)
        XCTAssertEqual(ctx?.localHaptics, true)
    }
}
