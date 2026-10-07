import XCTest
@testable import WristBoxCore

/// Watch connect / disconnect / reconnect, app restart and unavailable states.
final class ConnectionTests: XCTestCase {
    func testStartsInactiveUntilActivated() {
        let m = ConnectionMonitor()
        XCTAssertEqual(m.state(now: 0), .inactive)
    }

    func testConnectsWhenReachable() {
        var m = ConnectionMonitor(heartbeatTimeout: 4)
        m.update(activated: true, reachable: false, now: 0)
        XCTAssertEqual(m.state(now: 0), .disconnected)
        m.update(reachable: true, now: 1)
        XCTAssertEqual(m.state(now: 1), .connected)
        XCTAssertEqual(m.state(now: 1).headline, "WATCH CONNECTED")
    }

    func testDisconnectsWhenHeartbeatsStop() {
        var m = ConnectionMonitor(heartbeatTimeout: 4)
        m.update(activated: true, reachable: true, now: 0)
        XCTAssertEqual(m.state(now: 3.9), .connected)
        XCTAssertEqual(m.state(now: 4.5), .disconnected)
        XCTAssertEqual(m.state(now: 4.5).headline, "WATCH DISCONNECTED")
    }

    func testHeartbeatKeepsLinkAlive() {
        var m = ConnectionMonitor(heartbeatTimeout: 4)
        m.update(activated: true, reachable: true, now: 0)
        for t in stride(from: 1.0, through: 20.0, by: 1.0) {
            m.heard(at: t)
            XCTAssertEqual(m.state(now: t + 0.5), .connected)
        }
    }

    func testReconnectAfterDisconnect() {
        var m = ConnectionMonitor(heartbeatTimeout: 4)
        m.update(activated: true, reachable: true, now: 0)
        m.heard(at: 1)
        m.update(reachable: false, now: 2)
        XCTAssertEqual(m.state(now: 2), .disconnected)
        m.update(reachable: true, now: 10)
        XCTAssertEqual(m.state(now: 10), .connected, "stale heartbeat from before the drop must not count")
    }

    func testPairingAndInstallStates() {
        var m = ConnectionMonitor()
        m.update(supported: true, paired: false, appInstalled: false, activated: true, reachable: false, now: 0)
        XCTAssertEqual(m.state(now: 0), .notPaired)
        m.update(paired: true, now: 0)
        XCTAssertEqual(m.state(now: 0), .appNotInstalled)
        m.update(appInstalled: true, now: 0)
        XCTAssertEqual(m.state(now: 0), .disconnected)
        m.update(supported: false, now: 0)
        XCTAssertEqual(m.state(now: 0), .unsupported)
    }

    func testAppRestartResetsToInactive() {
        var m = ConnectionMonitor()
        m.update(activated: true, reachable: true, now: 0)
        m.heard(at: 0)
        m.reset()
        XCTAssertEqual(m.state(now: 0.1), .inactive)
        m.update(activated: true, now: 1)
        XCTAssertEqual(m.state(now: 1), .disconnected)   // not reachable yet
    }

    func testEveryStateHasHumanText() {
        for s in [LinkState.unsupported, .notPaired, .appNotInstalled, .inactive, .disconnected, .connected] {
            XCTAssertFalse(s.detail.isEmpty)
            XCTAssertFalse(s.headline.isEmpty)
        }
    }

    // MARK: Fight reacts to a lost controller

    func testDisconnectReleasesHeldBlock() {
        let engine = FightEngine(opponent: passiveOpponent())
        engine.startAndFight()
        engine.handle(.blockStart(meta))
        XCTAssertTrue(engine.playerBlocking)
        engine.controllerDisconnected()
        XCTAssertFalse(engine.playerBlocking)
        XCTAssertTrue(engine.drainEvents().contains(.playerBlock(false)))
    }

    func testFightKeepsRunningAndIgnoresInputWhilePaused() {
        let engine = FightEngine(opponent: passiveOpponent())
        engine.startAndFight()
        engine.isPaused = true
        let before = engine.roundTimeLeft
        engine.run(5)
        XCTAssertEqual(engine.roundTimeLeft, before, accuracy: 1e-9)
        engine.isPaused = false
        engine.run(1)
        XCTAssertLessThan(engine.roundTimeLeft, before)
    }

    func testReconnectResumesInput() {
        let engine = FightEngine(opponent: passiveOpponent())
        engine.startAndFight()
        engine.controllerDisconnected()
        engine.handle(.blockStart(meta))     // the Watch is back and reports block again
        XCTAssertTrue(engine.playerBlocking)
        engine.handle(punchEvent())
        XCTAssertEqual(engine.stats.punchesThrown, 1)
    }
}
