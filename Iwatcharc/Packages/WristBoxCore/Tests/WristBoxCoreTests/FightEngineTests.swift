import XCTest
@testable import WristBoxCore

/// The boxing game, tested with simulated gestures and no sensors.
final class FightEngineTests: XCTestCase {
    // MARK: Flow

    func testCountdownThenFightBegins() {
        let engine = FightEngine(opponent: passiveOpponent())
        engine.start()
        var events = engine.drainEvents()
        events += engine.run(3.2)
        XCTAssertTrue(events.contains(.countdown(3)))
        XCTAssertTrue(events.contains(.countdown(2)))
        XCTAssertTrue(events.contains(.countdown(1)))
        XCTAssertTrue(events.contains(.roundStarted(1)))
        XCTAssertEqual(engine.phase, .fighting)
    }

    func testPunchesAreIgnoredBeforeTheBell() {
        let engine = FightEngine(opponent: passiveOpponent())
        engine.start()
        engine.handle(punchEvent())
        XCTAssertEqual(engine.stats.punchesThrown, 0)
    }

    func testRoundTimerCountsDown() {
        let engine = FightEngine(opponent: passiveOpponent())
        engine.startAndFight()
        engine.run(10)
        XCTAssertEqual(engine.roundTimeLeft, 50, accuracy: 0.2)
    }

    // MARK: Punches, damage, accuracy

    func testCleanPunchDamagesOpponent() {
        let engine = FightEngine(opponent: passiveOpponent(health: 500))
        engine.startAndFight()
        engine.handle(punchEvent(.cross, power: 0.8, accuracy: 0.9))
        let events = engine.drainEvents()
        XCTAssertLessThan(engine.opponentHealth, 500)
        XCTAssertEqual(engine.stats.punchesLanded, 1)
        XCTAssertGreaterThan(engine.stats.damageDealt, 0)
        guard case .playerPunch(let p)? = events.first(where: { if case .playerPunch = $0 { return true } else { return false } }) else {
            return XCTFail("no punch event")
        }
        XCTAssertEqual(p.outcome, .hit)
        XCTAssertGreaterThan(p.damage, 0)
    }

    func testStrongerAndMoreAccuratePunchesDealMoreDamage() {
        func damage(power: Double, accuracy: Double, type: PunchType = .jab) -> Double {
            let e = FightEngine(opponent: passiveOpponent(health: 500))
            e.startAndFight()
            e.handle(punchEvent(type, power: power, accuracy: accuracy))
            return e.stats.damageDealt
        }
        XCTAssertGreaterThan(damage(power: 0.9, accuracy: 0.9), damage(power: 0.3, accuracy: 0.9))
        XCTAssertGreaterThan(damage(power: 0.7, accuracy: 0.95), damage(power: 0.7, accuracy: 0.4))
        XCTAssertGreaterThan(damage(power: 0.7, accuracy: 0.9, type: .cross), damage(power: 0.7, accuracy: 0.9, type: .jab))
    }

    func testSloppyPunchMissesAndBreaksCombo() {
        let engine = FightEngine(opponent: passiveOpponent(health: 500))
        engine.startAndFight()
        engine.handle(punchEvent())
        engine.handle(punchEvent())
        XCTAssertEqual(engine.combo, 2)
        engine.drainEvents()
        engine.handle(punchEvent(accuracy: 0.1))
        let events = engine.drainEvents()
        XCTAssertEqual(engine.combo, 0)
        XCTAssertTrue(events.contains(.comboBroken(count: 2)))
        XCTAssertEqual(engine.stats.punchesLanded, 2)
        XCTAssertEqual(engine.stats.punchesThrown, 3)
    }

    func testUpgradesIncreaseDamage() {
        func damage(_ u: PlayerUpgrades) -> Double {
            let e = FightEngine(opponent: passiveOpponent(health: 500), upgrades: u)
            e.startAndFight()
            e.handle(punchEvent())
            return e.stats.damageDealt
        }
        XCTAssertGreaterThan(damage(PlayerUpgrades(power: 5)), damage(PlayerUpgrades()))
    }

    // MARK: Combos

    func testComboBuildsAndNamesKnownSequences() {
        let engine = FightEngine(opponent: passiveOpponent(health: 500))
        engine.startAndFight()
        engine.handle(punchEvent(.jab))
        engine.run(0.3)
        engine.handle(punchEvent(.cross))
        XCTAssertEqual(engine.combo, 2)
        XCTAssertEqual(engine.comboName, "ONE-TWO")
        engine.run(0.3)
        engine.handle(punchEvent(.leftHook))
        XCTAssertEqual(engine.combo, 3)
        XCTAssertEqual(engine.comboName, "ONE-TWO-HOOK")
        engine.run(0.3)
        engine.handle(punchEvent(.rightHook))
        XCTAssertEqual(engine.combo, 4)
        XCTAssertEqual(engine.comboName, "THE FULL COMBO")
        XCTAssertEqual(engine.stats.maxCombo, 4)
        XCTAssertEqual(engine.stats.combos, 1)
        XCTAssertTrue(engine.drainEvents().contains(.combo(count: 4, name: "THE FULL COMBO")))
    }

    func testLongerCombosHitHarder() {
        let engine = FightEngine(opponent: passiveOpponent(health: 5_000))
        engine.startAndFight()
        var damages: [Double] = []
        for _ in 0..<5 {
            let before = engine.stats.damageDealt
            engine.handle(punchEvent(.jab, power: 0.7, accuracy: 0.9))
            damages.append(engine.stats.damageDealt - before)
            engine.run(0.25)
        }
        XCTAssertGreaterThan(damages[4], damages[0])
    }

    func testComboExpiresAfterWindow() {
        let engine = FightEngine(opponent: passiveOpponent(health: 500))
        engine.startAndFight()
        engine.handle(punchEvent())
        engine.handle(punchEvent())
        engine.drainEvents()
        let events = engine.run(2.5)
        XCTAssertEqual(engine.combo, 0)
        XCTAssertTrue(events.contains(.comboBroken(count: 2)))
    }

    func testGettingHitBreaksCombo() {
        let engine = FightEngine(opponent: singleJabOpponent())
        engine.startAndFight()
        engine.handle(punchEvent())
        engine.handle(punchEvent())
        XCTAssertEqual(engine.combo, 2)
        // Keep the combo alive while the opponent's jab lands.
        var broke = false
        for _ in 0..<600 {
            engine.update(1.0 / 60)
            let events = engine.drainEvents()
            if events.contains(where: { if case .opponentAttack(_, .hit, _) = $0 { return true } else { return false } }) {
                broke = true
                break
            }
            if engine.combo > 0, Int(engine.time * 60) % 40 == 0 { engine.handle(punchEvent()) }
        }
        XCTAssertTrue(broke)
        XCTAssertEqual(engine.combo, 0)
    }

    // MARK: Defence, dodge, counter

    func testUnansweredAttackHurtsPlayer() {
        let engine = FightEngine(opponent: singleJabOpponent())
        engine.startAndFight()
        let events = engine.run(until: { if case .opponentAttack = $0 { return true } else { return false } })
        guard case .opponentAttack(let kind, let result, let damage)? = events.last else { return XCTFail("no attack") }
        XCTAssertEqual(kind, .jab)
        XCTAssertEqual(result, .hit)
        XCTAssertEqual(engine.playerHealth, 100 - damage, accuracy: 1e-9)
        XCTAssertGreaterThan(damage, 0)
    }

    func testBlockingReducesDamage() {
        let hit = FightEngine(opponent: singleJabOpponent())
        hit.startAndFight()
        _ = hit.run(until: { if case .opponentAttack = $0 { return true } else { return false } })

        let blocked = FightEngine(opponent: singleJabOpponent())
        blocked.startAndFight()
        blocked.handle(.blockStart(meta))
        let events = blocked.run(until: { if case .opponentAttack = $0 { return true } else { return false } })
        guard case .opponentAttack(_, let result, _)? = events.last else { return XCTFail("no attack") }
        XCTAssertEqual(result, .blocked)
        XCTAssertGreaterThan(blocked.playerHealth, hit.playerHealth)
        XCTAssertEqual(blocked.stats.blocks, 1)
    }

    func testBlockingCostsStaminaAndRegeneratesIt() {
        let engine = FightEngine(opponent: singleJabOpponent())
        engine.startAndFight()
        engine.handle(.blockStart(meta))
        _ = engine.run(until: { if case .opponentAttack = $0 { return true } else { return false } })
        XCTAssertLessThan(engine.stamina, engine.staminaMax)
    }

    /// Wait for the wind-up, then dodge `delayAfterTelegraph` seconds into it.
    private func dodge(engine: FightEngine, side: Side, secondsBeforeImpact: Double) -> [FightEvent] {
        var events = engine.run(until: { if case .opponentTelegraph = $0 { return true } else { return false } })
        let telegraph = events.last { if case .opponentTelegraph = $0 { return true } else { return false } }
        guard case .opponentTelegraph(_, let duration, _)? = telegraph else { return events }
        events += engine.run(max(0, duration - secondsBeforeImpact))
        engine.handle(side == .left ? .dodgeLeft(meta) : .dodgeRight(meta))
        events += engine.drainEvents()
        events += engine.run(until: { if case .opponentAttack = $0 { return true } else { return false } })
        return events
    }

    func testWellTimedDodgeAvoidsTheAttack() {
        let engine = FightEngine(opponent: singleJabOpponent())
        engine.startAndFight()
        let events = dodge(engine: engine, side: .left, secondsBeforeImpact: 0.3)
        XCTAssertTrue(events.contains(.opponentAttack(.jab, result: .dodged, damage: 0)))
        XCTAssertEqual(engine.playerHealth, 100, accuracy: 1e-9)
        XCTAssertEqual(engine.stats.dodges, 1)
        XCTAssertTrue(engine.snapshot.counterWindowOpen)
    }

    func testDodgeThatIsTooEarlyDoesNothing() {
        let engine = FightEngine(opponent: singleJabOpponent())
        engine.startAndFight()
        let events = dodge(engine: engine, side: .left, secondsBeforeImpact: 5)   // right away
        XCTAssertFalse(events.contains(.opponentAttack(.jab, result: .dodged, damage: 0)))
        XCTAssertLessThan(engine.playerHealth, 100)
    }

    func testPerfectDodgeThenPunchIsAPerfectCounter() {
        let engine = FightEngine(opponent: singleJabOpponent())
        engine.startAndFight()
        var events = dodge(engine: engine, side: .right, secondsBeforeImpact: 0.1)
        XCTAssertTrue(events.contains(.playerDodge(.right, success: true, perfect: true)))

        engine.handle(punchEvent(.cross, power: 0.8, accuracy: 0.9))
        events = engine.drainEvents()
        XCTAssertTrue(events.contains(.counter(perfect: true)), "events: \(events)")
        XCTAssertTrue(events.contains(.perfectPunch))
        XCTAssertEqual(engine.stats.counters, 1)
        XCTAssertEqual(engine.stats.perfectPunches, 1)
    }

    func testCounterDealsBonusDamage() {
        func damage(counter: Bool) -> Double {
            let engine = FightEngine(opponent: singleJabOpponent())
            engine.startAndFight()
            if counter {
                _ = dodge(engine: engine, side: .left, secondsBeforeImpact: 0.3)
            } else {
                engine.run(0.1)
            }
            let before = engine.stats.damageDealt
            engine.handle(punchEvent(.cross, power: 0.8, accuracy: 0.9))
            return engine.stats.damageDealt - before
        }
        XCTAssertGreaterThan(damage(counter: true), damage(counter: false) * 1.5)
    }

    func testCounterWindowExpires() {
        let engine = FightEngine(opponent: singleJabOpponent())
        engine.startAndFight()
        _ = dodge(engine: engine, side: .left, secondsBeforeImpact: 0.3)
        engine.run(3)
        XCTAssertFalse(engine.snapshot.counterWindowOpen)
        engine.handle(punchEvent())
        XCTAssertFalse(engine.drainEvents().contains { if case .counter = $0 { return true } else { return false } })
    }

    func testHookMustBeDodgedTheRightWay() {
        var p = singleJabOpponent()
        p.patterns = [AttackPattern("hook", [.attack(.leftHook)])]
        // A left hook comes from the left: dodging left is wrong, right is correct.
        let wrong = FightEngine(opponent: p)
        wrong.startAndFight()
        let e1 = dodge(engine: wrong, side: .left, secondsBeforeImpact: 0.3)
        XCTAssertFalse(e1.contains(.opponentAttack(.leftHook, result: .dodged, damage: 0)))

        let right = FightEngine(opponent: p)
        right.startAndFight()
        let e2 = dodge(engine: right, side: .right, secondsBeforeImpact: 0.3)
        XCTAssertTrue(e2.contains(.opponentAttack(.leftHook, result: .dodged, damage: 0)))
    }

    func testDefenseUpgradeReducesDamageTaken() {
        func health(_ u: PlayerUpgrades) -> Double {
            let e = FightEngine(opponent: singleJabOpponent(), upgrades: u)
            e.startAndFight()
            _ = e.run(until: { if case .opponentAttack = $0 { return true } else { return false } })
            return e.playerHealth
        }
        XCTAssertGreaterThan(health(PlayerUpgrades(defense: 8)), health(PlayerUpgrades()))
    }

    // MARK: Perfect punch

    func testPunchingAnOpeningIsPerfect() {
        // Beginner always opens up after finishing a pattern.
        var p = OpponentProfile.roster[0]
        p.patterns = [AttackPattern("jab", [.attack(.jab)])]
        p.openingChance = 1
        p.health = 1_000
        p.blockChance = 0
        p.dodgeChance = 0
        let engine = FightEngine(opponent: p)
        engine.startAndFight()
        var perfect = false
        for _ in 0..<1800 {
            engine.update(1.0 / 60)
            _ = engine.drainEvents()
            if engine.ai.state == .vulnerable, engine.ai.perfectWindowOpen {
                engine.handle(punchEvent())
                perfect = engine.drainEvents().contains(.perfectPunch)
                break
            }
        }
        XCTAssertTrue(perfect)
        XCTAssertEqual(engine.stats.perfectPunches, 1)
    }

    // MARK: Stamina

    func testPunchingDrainsStaminaAndRestingRestoresIt() {
        let engine = FightEngine(opponent: passiveOpponent())
        engine.startAndFight()
        for _ in 0..<10 { engine.handle(punchEvent()) }
        XCTAssertLessThan(engine.stamina, engine.staminaMax * 0.7)
        engine.run(8)
        XCTAssertEqual(engine.stamina, engine.staminaMax, accuracy: 0.5)
    }

    func testLowStaminaWeakensPunchesAndPreventsInfiniteSpam() {
        let engine = FightEngine(opponent: passiveOpponent(health: 100_000))
        engine.startAndFight()
        var powers: [Double] = []
        for _ in 0..<40 {
            engine.handle(punchEvent(.jab, power: 0.9, accuracy: 0.9))
            for e in engine.drainEvents() {
                if case .playerPunch(let p) = e { powers.append(p.power) }
            }
        }
        XCTAssertEqual(powers.first ?? 0, 0.9, accuracy: 1e-9)
        XCTAssertLessThan(powers.last ?? 1, 0.6)
        XCTAssertEqual(engine.stamina, 0, accuracy: 1e-9)
    }

    func testStaminaUpgradeRaisesTheBar() {
        let a = FightEngine(opponent: passiveOpponent())
        let b = FightEngine(opponent: passiveOpponent(), upgrades: PlayerUpgrades(stamina: 5))
        XCTAssertGreaterThan(b.staminaMax, a.staminaMax)
    }

    // MARK: Special

    private func chargeSpecial(_ engine: FightEngine) -> Bool {
        for _ in 0..<120 {
            engine.handle(punchEvent(.jab, power: 0.9, accuracy: 0.9))
            engine.run(0.3)
            if engine.specialReady { return true }
        }
        return false
    }

    func testSpecialMeterFillsAndPowerComboFires() {
        let engine = FightEngine(opponent: passiveOpponent(health: 100_000))
        engine.startAndFight()
        engine.drainEvents()
        XCTAssertTrue(chargeSpecial(engine))
        XCTAssertGreaterThanOrEqual(engine.special, 100)

        let before = engine.opponentHealth
        engine.handle(.power(PunchResult(type: .power, power: 1, accuracy: 1, speed: 1)))
        XCTAssertTrue(engine.specialActive)
        XCTAssertEqual(engine.special, 0)
        let events = engine.run(3.5)
        XCTAssertTrue(events.contains(.specialStarted))
        XCTAssertEqual(events.filter { if case .specialHit = $0 { return true } else { return false } }.count, 6)
        XCTAssertTrue(events.contains(.specialEnded))
        XCTAssertFalse(engine.specialActive)
        XCTAssertGreaterThan(before - engine.opponentHealth, 25)
    }

    func testSpecialAlsoTriggersFromShake() {
        let engine = FightEngine(opponent: passiveOpponent(health: 100_000))
        engine.startAndFight()
        XCTAssertTrue(chargeSpecial(engine))
        engine.handle(.guardBreak(meta))
        XCTAssertTrue(engine.specialActive)
    }

    func testPlayerIsInvulnerableDuringSpecial() {
        var p = singleJabOpponent()
        p.health = 100_000
        let engine = FightEngine(opponent: p)
        engine.startAndFight()
        XCTAssertTrue(chargeSpecial(engine))
        let healthBefore = engine.playerHealth
        engine.handle(.guardBreak(meta))
        engine.run(0.5)
        XCTAssertEqual(engine.playerHealth, healthBefore, accuracy: 1e-9)
    }

    func testPowerPunchBeforeSpecialIsReadyIsJustAPunch() {
        let engine = FightEngine(opponent: passiveOpponent(health: 500))
        engine.startAndFight()
        engine.handle(.power(PunchResult(type: .power, power: 1, accuracy: 1, speed: 1)))
        XCTAssertFalse(engine.specialActive)
        XCTAssertEqual(engine.stats.punchesLanded, 1)
    }

    // MARK: Knockdown, KO, rounds, fight result

    private func tinyOpponent() -> OpponentProfile {
        var p = passiveOpponent(health: 1)
        p.poise = 1_000
        return p
    }

    func testKnockdownThenGetUp() {
        let engine = FightEngine(opponent: tinyOpponent())
        engine.startAndFight()
        engine.handle(punchEvent())
        var events = engine.drainEvents()
        XCTAssertTrue(events.contains(.knockdown(.opponent, number: 1)))
        XCTAssertEqual(engine.ai.state, .knockedDown)
        if case .knockdown(.opponent, _) = engine.phase {} else { XCTFail("expected knockdown phase, got \(engine.phase)") }

        // Punches during the count do nothing.
        engine.handle(punchEvent())
        XCTAssertEqual(engine.stats.punchesLanded, 1)

        events = engine.run(3.5)
        XCTAssertTrue(events.contains(.getUp(.opponent)))
        XCTAssertEqual(engine.phase, .fighting)
        XCTAssertGreaterThan(engine.opponentHealth, 0)
    }

    func testSecondKnockdownIsAKnockout() {
        let engine = FightEngine(opponent: tinyOpponent())
        engine.startAndFight()
        engine.handle(punchEvent())
        engine.run(3.5)
        engine.run(1.0)    // let the AI recover and the combo reset
        engine.handle(punchEvent())
        let events = engine.drainEvents()
        XCTAssertTrue(events.contains(.ko(winner: .player)), "events: \(events)")
        XCTAssertEqual(engine.playerRoundWins, 1)
        if case .roundEnd = engine.phase {} else { XCTFail("expected round end, got \(engine.phase)") }
    }

    func testWinningTwoRoundsByKOEndsTheFight() {
        let engine = FightEngine(opponent: tinyOpponent())
        engine.startAndFight()
        for _ in 0..<2 {
            // Knock them down twice to stop the round.
            for _ in 0..<2 {
                engine.run(1.0)
                engine.handle(punchEvent())
                engine.run(3.6)
            }
            engine.run(4.0)   // round break + countdown
        }
        // Some more time for the break after round 2.
        engine.run(5)
        guard let outcome = engine.outcome else { return XCTFail("fight did not finish, phase \(engine.phase)") }
        XCTAssertEqual(outcome.winner, .player)
        XCTAssertEqual(outcome.method, .ko)
        XCTAssertEqual(outcome.playerRoundsWon, 2)
        XCTAssertEqual(outcome.rounds.count, 2)
        XCTAssertTrue(engine.isOver)
    }

    func testPlayerCanBeKnockedOutAndLose() {
        var p = OpponentProfile.roster[4]
        p.damageScale = 20     // absurdly hard hitting, to end the fight quickly
        let engine = FightEngine(opponent: p)
        engine.startAndFight()
        engine.run(600)
        guard let outcome = engine.outcome else { return XCTFail("fight did not finish, phase \(engine.phase)") }
        XCTAssertEqual(outcome.winner, .opponent)
        XCTAssertFalse(outcome.playerWon)
        XCTAssertEqual(outcome.opponentRoundsWon, 2)
    }

    func testPassivePlayerLosesOnPointsToAnAttacker() {
        let engine = FightEngine(opponent: OpponentProfile.roster[3])
        engine.startAndFight()
        engine.run(900)
        XCTAssertNotNil(engine.outcome)
        XCTAssertEqual(engine.outcome?.winner, .opponent)
    }

    func testPlayerWinsOnDecisionByLandingPunchesOnAPassiveOpponent() {
        let engine = FightEngine(opponent: passiveOpponent(health: 100_000))
        engine.startAndFight()
        for _ in 0..<3 {
            for _ in 0..<5 {
                engine.handle(punchEvent(.cross))
                engine.run(0.5)
            }
            engine.run(60)    // run the clock out
            engine.run(6)     // round break and countdown
        }
        guard let outcome = engine.outcome else { return XCTFail("fight did not finish, phase \(engine.phase)") }
        XCTAssertEqual(outcome.winner, .player)
        XCTAssertEqual(outcome.method, .decision)
        XCTAssertGreaterThanOrEqual(outcome.playerRoundsWon, 2)
    }

    func testFightOutcomeCarriesStats() {
        let engine = FightEngine(opponent: tinyOpponent())
        engine.startAndFight()
        for _ in 0..<2 {
            for _ in 0..<2 {
                engine.run(1.0)
                engine.handle(punchEvent())
                engine.run(3.6)
            }
            engine.run(4.0)
        }
        engine.run(5)
        XCTAssertEqual(engine.outcome?.stats.punchesLanded, engine.stats.punchesLanded)
        XCTAssertGreaterThan(engine.outcome?.stats.damageDealt ?? 0, 0)
    }

    func testNextRoundResetsHealthPartially() {
        var p = passiveOpponent(health: 1_000)
        p.poise = 1_000
        let engine = FightEngine(opponent: p)
        engine.startAndFight()
        for _ in 0..<5 { engine.handle(punchEvent(.cross)); engine.run(0.4) }
        let damaged = engine.opponentHealth
        XCTAssertLessThan(damaged, 1_000)
        engine.run(61)       // timer ends round 1
        XCTAssertEqual(engine.roundResults.count, 1)
        engine.run(3.2 + 2.2)
        XCTAssertEqual(engine.round, 2)
        XCTAssertGreaterThan(engine.opponentHealth, damaged)
        XCTAssertEqual(engine.stamina, engine.staminaMax, accuracy: 0.01)
    }

    // MARK: Events, haptics, snapshot

    func testHapticCuesForKeyMoments() {
        XCTAssertEqual(FightEvent.perfectPunch.hapticCue, .perfectPunch)
        XCTAssertEqual(FightEvent.counter(perfect: false).hapticCue, .counter)
        XCTAssertEqual(FightEvent.ko(winner: .player).hapticCue, .ko)
        XCTAssertEqual(FightEvent.roundStarted(1).hapticCue, .roundStart)
        XCTAssertEqual(FightEvent.specialReady.hapticCue, .specialReady)
        XCTAssertEqual(FightEvent.opponentAttack(.jab, result: .hit, damage: 3).hapticCue, .opponentHit)
        XCTAssertEqual(FightEvent.combo(count: 3, name: nil).hapticCue, .combo)
        XCTAssertNil(FightEvent.combo(count: 2, name: nil).hapticCue)
        let plain = PunchEvent(type: .jab, outcome: .hit, damage: 3, power: 0.5, accuracy: 0.8,
                               perfect: false, counter: false, critical: false, combo: 1)
        XCTAssertEqual(FightEvent.playerPunch(plain).hapticCue, .punchLanded)
        var perfect = plain
        perfect.perfect = true
        XCTAssertNil(FightEvent.playerPunch(perfect).hapticCue, "perfect plays its own cue")
    }

    func testSnapshotAndWatchSummaryReflectState() {
        let engine = FightEngine(opponent: passiveOpponent(health: 500))
        XCTAssertEqual(engine.watchSummary.phase, .idle)
        engine.startAndFight()
        engine.handle(punchEvent())
        engine.handle(.blockStart(meta))
        let s = engine.snapshot
        XCTAssertEqual(s.phase, .fighting)
        XCTAssertEqual(s.combo, 1)
        XCTAssertTrue(s.playerBlocking)
        XCTAssertLessThan(s.opponentHealth, s.opponentMaxHealth)
        let w = engine.watchSummary
        XCTAssertEqual(w.phase, .fighting)
        XCTAssertEqual(w.combo, 1)
        XCTAssertEqual(w.round, 1)
    }

    func testSimulatedControllerCanPlayAWholeRound() {
        // The simulator buttons must be enough to drive the game end to end.
        var sim = SimulatedController(seed: 5)
        let engine = FightEngine(opponent: OpponentProfile.roster[0])
        engine.startAndFight()
        engine.handle(sim.event(for: .block))
        var t = 0.0
        while t < 60, !engine.isOver {
            engine.update(1.0 / 30)
            engine.drainEvents().forEach { event in
                if case .opponentTelegraph = event { engine.handle(sim.event(for: .dodgeLeft)) }
            }
            if Int(t * 30) % 20 == 0 { engine.handle(sim.event(for: .jab)) }
            t += 1.0 / 30
        }
        XCTAssertGreaterThan(engine.stats.punchesThrown, 10)
        XCTAssertGreaterThan(engine.stats.punchesLanded, 0)
        XCTAssertEqual(engine.playerRoundWins + engine.opponentRoundWins >= 0, true)
    }

    func testEveryOpponentCanBeFought() {
        for profile in OpponentProfile.roster {
            let engine = FightEngine(opponent: profile, seed: UInt64(profile.id))
            engine.startAndFight()
            engine.run(30)
            XCTAssertNotEqual(engine.phase, .notStarted)
            XCTAssertGreaterThan(engine.opponentMaxHealth, 0)
        }
    }
}
