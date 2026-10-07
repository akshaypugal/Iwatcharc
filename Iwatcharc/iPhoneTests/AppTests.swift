import XCTest
import WristBoxCore
@testable import WristBox

/// App-level tests: persistence, rewards, the simulated controller feeding the
/// game, and the fight view model. They need no Apple Watch.
final class AppTests: XCTestCase {
    private func makeEnv(store: ProfileStore = InMemoryProfileStore()) -> AppEnvironment {
        AppEnvironment(store: store)
    }

    private func winningOutcome(opponent: Int = 0) -> FightOutcome {
        var stats = FightStats()
        stats.punchesThrown = 30
        stats.punchesLanded = 24
        stats.maxCombo = 4
        stats.counters = 1
        return FightOutcome(winner: .player, method: .decision, playerRoundsWon: 2, opponentRoundsWon: 0,
                            rounds: [], stats: stats, duration: 100, opponentID: opponent)
    }

    func testFreshProfile() {
        let env = makeEnv()
        XCTAssertEqual(env.profile.level, 1)
        XCTAssertEqual(env.profile.coins, 0)
        XCTAssertEqual(env.profile.careerProgress, 0)
    }

    func testFinishFightAwardsRewardsAndSaves() {
        let store = InMemoryProfileStore()
        let env = makeEnv(store: store)
        let opponent = env.opponent(id: 0, tier: 0)
        env.finishFight(winningOutcome(), opponent: opponent, tier: 0)
        XCTAssertNotNil(env.lastResult)
        XCTAssertGreaterThan(env.profile.coins, 0)
        XCTAssertGreaterThan(env.profile.totalXP, 0)
        XCTAssertEqual(env.profile.careerProgress, 1)
        XCTAssertEqual(store.load()?.careerProgress, 1, "profile is saved after every change")
    }

    func testBuyingAnUpgradeSpendsCoins() {
        let env = makeEnv()
        var p = env.profile
        p.coins = 500
        env.profile = p
        XCTAssertTrue(env.buy(.power))
        XCTAssertEqual(env.profile.upgrades.power, 1)
        XCTAssertEqual(env.profile.coins, 500 - PlayerUpgrades.cost(fromLevel: 0))
        var broke = env.profile
        broke.coins = 0
        env.profile = broke
        XCTAssertFalse(env.buy(.speed))
    }

    func testSettingsArePersisted() {
        let store = InMemoryProfileStore()
        let env = makeEnv(store: store)
        env.updateSettings { $0.soundEnabled = false; $0.gestureConfig.jabMin = 2.4 }
        XCTAssertFalse(env.sound.enabled)
        XCTAssertEqual(store.load()?.settings.soundEnabled, false)
        XCTAssertEqual(store.load()?.settings.gestureConfig.jabMin, 2.4)
    }

    func testSecondLaunchRestoresTheProfile() {
        let store = InMemoryProfileStore()
        let first = makeEnv(store: store)
        var p = first.profile
        p.level = 9
        p.coins = 77
        first.profile = p
        let second = makeEnv(store: store)
        XCTAssertEqual(second.profile.level, 9)
        XCTAssertEqual(second.profile.coins, 77)
    }

    func testSimulatedControllerFeedsTheGame() {
        let env = makeEnv()
        var received: [GestureEvent] = []
        env.controller.onGesture = { received.append($0) }
        for input in SimulatedInput.allCases { env.controller.simulate(input) }
        env.controller.simulateBlock(pressed: true)
        env.controller.simulateBlock(pressed: false)
        XCTAssertEqual(received.count, SimulatedInput.allCases.count + 2)
        XCTAssertFalse(env.controller.eventLog.isEmpty)
        XCTAssertEqual(env.controller.lastGesture, "BLOCK_END")
    }

    func testWithoutAWatchTheControllerReportsDisconnected() {
        let env = makeEnv()
        XCTAssertFalse(env.controller.linkState.isConnected)
        XCTAssertEqual(env.controller.linkState.headline, "WATCH DISCONNECTED")
    }

    func testCalibrationCallbackIsStoredInTheProfile() {
        let env = makeEnv()
        var cal = Calibration.default
        cal.hasNeutral = true
        cal.hasForward = true
        env.controller.onCalibration?(cal)
        XCTAssertTrue(env.profile.calibration.isCalibrated)
        env.controller.resetCalibration()
        XCTAssertFalse(env.profile.calibration.isCalibrated)
    }

    func testRouterReplaceTop() {
        let router = AppRouter()
        router.push(.career)
        router.push(.fight(opponent: 0, tier: 0))
        router.replaceTop(with: .result)
        XCTAssertEqual(router.path.count, 2)
        router.popToRoot()
        XCTAssertTrue(router.path.isEmpty)
    }

    func testFightViewModelRunsAFightWithSimulatedInput() {
        let env = makeEnv()
        env.updateSettings { $0.simulatedController = true }
        let vm = FightViewModel(env: env, opponentID: 0, tier: 0)
        vm.begin()
        vm.engine.update(0.1)
        // Skip the countdown.
        for _ in 0..<40 { vm.engine.update(0.1) }
        XCTAssertEqual(vm.engine.phase, .fighting)
        env.controller.simulate(.jab)
        XCTAssertEqual(vm.engine.stats.punchesThrown, 1)
        XCTAssertNotNil(vm.lastPunch)
        env.controller.simulateBlock(pressed: true)
        XCTAssertTrue(vm.engine.playerBlocking)
        vm.end()
        XCTAssertNil(env.controller.onGesture)
    }

    func testFightPausesWhenNoControllerIsAvailable() {
        let env = makeEnv()
        env.updateSettings { $0.simulatedController = false }
        let vm = FightViewModel(env: env, opponentID: 0, tier: 0)
        vm.begin()
        let lost = self.expectation(description: "controller loss is published")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { lost.fulfill() }
        waitForExpectations(timeout: 2)
        XCTAssertTrue(vm.controllerLost)
        XCTAssertTrue(vm.engine.isPaused)
        vm.useSimulatedController()
        let resumed = self.expectation(description: "resumes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { resumed.fulfill() }
        waitForExpectations(timeout: 2)
        XCTAssertFalse(vm.controllerLost)
        vm.end()
    }

    func testSoundEffectsRenderWithoutCrashing() {
        let sound = SoundService()
        for effect in SoundService.Effect.allCases { sound.play(effect) }
    }
}
