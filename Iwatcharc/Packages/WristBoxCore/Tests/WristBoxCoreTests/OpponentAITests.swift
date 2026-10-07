import XCTest
@testable import WristBoxCore

final class OpponentAITests: XCTestCase {
    private func collect(_ ai: OpponentAI, seconds: Double, step: Double = 1.0 / 60.0,
                         onImpact: (AttackKind) -> Void = { _ in }) -> [AIEvent] {
        var all: [AIEvent] = []
        var t = 0.0
        while t < seconds {
            let events = ai.update(step)
            for e in events {
                all.append(e)
                if case .impact(let k) = e { onImpact(k) }
            }
            t += step
        }
        return all
    }

    private func profile(patterns: [AttackPattern]) -> OpponentProfile {
        var p = OpponentProfile.roster[0]
        p.patterns = patterns
        p.openingChance = 0
        p.restMin = 0.5
        p.restMax = 0.5
        p.blockChance = 0
        p.dodgeChance = 0
        p.counterChance = 0
        return p
    }

    func testStartsIdleAndWaitsBeforeAttacking() {
        let ai = OpponentAI(profile: profile(patterns: [AttackPattern("jab", [.attack(.jab)])]))
        XCTAssertEqual(ai.state, .idle)
        let early = collect(ai, seconds: 0.5)
        XCTAssertFalse(early.contains { if case .telegraphStarted = $0 { return true } else { return false } })
    }

    func testAttackPatternPlaysInOrderWithTelegraphs() {
        let p = profile(patterns: [AttackPattern("one-two", [.attack(.jab), .wait(0.4), .attack(.cross)])])
        let ai = OpponentAI(profile: p)
        let events = collect(ai, seconds: 8)
        var order: [String] = []
        for e in events {
            switch e {
            case .telegraphStarted(let k, _, _): order.append("tele-\(k.rawValue)")
            case .impact(let k): order.append("hit-\(k.rawValue)")
            default: break
            }
        }
        XCTAssertEqual(Array(order.prefix(4)), ["tele-jab", "hit-jab", "tele-cross", "hit-cross"])
    }

    func testTelegraphDurationScalesWithOpponentSpeed() {
        func firstTelegraph(_ p: OpponentProfile) -> Double {
            var q = p
            q.patterns = [AttackPattern("jab", [.attack(.jab)])]
            let ai = OpponentAI(profile: q)
            for e in collect(ai, seconds: 5) {
                if case .telegraphStarted(_, let d, _) = e { return d }
            }
            return .infinity
        }
        XCTAssertLessThan(firstTelegraph(OpponentProfile.roster[4]), firstTelegraph(OpponentProfile.roster[0]))
    }

    func testStateMachineVisitsAttackAndWatch() {
        let p = profile(patterns: [AttackPattern("p", [.attack(.jab), .wait(0.5), .attack(.cross)])])
        let ai = OpponentAI(profile: p)
        var seen = Set<OpponentState>()
        var t = 0.0
        while t < 8 {
            _ = ai.update(1.0 / 60)
            seen.insert(ai.state)
            t += 1.0 / 60
        }
        XCTAssertTrue(seen.contains(.idle))
        XCTAssertTrue(seen.contains(.attack))
        XCTAssertTrue(seen.contains(.watch))
    }

    func testDodgedAttackLeavesOpponentVulnerableAndPerfectWindowOpen() {
        let ai = OpponentAI(profile: profile(patterns: [AttackPattern("jab", [.attack(.jab)])]))
        _ = collect(ai, seconds: 6) { _ in ai.attackResolved(.dodged) }
        // The impact happened and was resolved as dodged at some point; replay precisely:
        let ai2 = OpponentAI(profile: profile(patterns: [AttackPattern("jab", [.attack(.jab)])]))
        var resolvedAt = -1.0
        var t = 0.0
        while t < 6, resolvedAt < 0 {
            for e in ai2.update(1.0 / 60) {
                if case .impact = e {
                    ai2.attackResolved(.dodged)
                    resolvedAt = t
                }
            }
            t += 1.0 / 60
        }
        XCTAssertGreaterThan(resolvedAt, 0)
        XCTAssertEqual(ai2.state, .vulnerable)
        XCTAssertTrue(ai2.isExposed)
        XCTAssertTrue(ai2.perfectWindowOpen)
        _ = collect(ai2, seconds: 0.5)
        XCTAssertFalse(ai2.perfectWindowOpen, "the perfect window is short")
    }

    func testSurvivingTheWholePatternCanLeaveAnOpening() {
        var p = profile(patterns: [AttackPattern("jab", [.attack(.jab)])])
        p.openingChance = 1
        let ai = OpponentAI(profile: p)
        var sawVulnerable = false
        var t = 0.0
        while t < 8 {
            _ = ai.update(1.0 / 60)
            if ai.state == .vulnerable { sawVulnerable = true }
            t += 1.0 / 60
        }
        XCTAssertTrue(sawVulnerable)
    }

    func testPoiseBreaksIntoStun() {
        let ai = OpponentAI(profile: OpponentProfile.roster[0])
        XCTAssertFalse(ai.absorb(damage: 1))
        XCTAssertTrue(ai.absorb(damage: ai.profile.poise + 1))
        XCTAssertEqual(ai.state, .stunned)
        XCTAssertTrue(ai.isExposed)
        XCTAssertFalse(ai.absorb(damage: 100), "already stunned")
        _ = collect(ai, seconds: 1.5)
        XCTAssertNotEqual(ai.state, .stunned)
    }

    func testStunCancelsAnAttackInProgress() {
        let ai = OpponentAI(profile: profile(patterns: [AttackPattern("jab", [.attack(.jab)])]))
        var impacted = false
        var t = 0.0
        while t < 6, !ai.isTelegraphing {
            _ = ai.update(1.0 / 60)
            t += 1.0 / 60
        }
        XCTAssertTrue(ai.isTelegraphing)
        ai.stun(duration: 2)
        for e in collect(ai, seconds: 1.5) { if case .impact = e { impacted = true } }
        XCTAssertFalse(impacted)
        XCTAssertEqual(ai.state, .stunned)
    }

    func testInterruptDuringWindupCancelsTheAttack() {
        let ai = OpponentAI(profile: profile(patterns: [AttackPattern("cross", [.attack(.cross)])]))
        var t = 0.0
        while t < 6, !ai.isTelegraphing {
            _ = ai.update(1.0 / 60)
            t += 1.0 / 60
        }
        XCTAssertTrue(ai.interruptAttack())
        XCTAssertEqual(ai.state, .vulnerable)
        XCTAssertFalse(ai.interruptAttack(), "nothing left to interrupt")
    }

    func testBlockReactionHappensAfterReactionTime() {
        var p = profile(patterns: [])
        p.blockChance = 1
        p.reactionTime = 0.3
        p.blockDuration = 0.6
        let ai = OpponentAI(profile: p)
        XCTAssertEqual(ai.incomingPlayerPunch(), .takesHit, "first punch lands before the guard comes up")
        XCTAssertEqual(ai.incomingPlayerPunch(), .takesHit)
        _ = collect(ai, seconds: 0.35)
        XCTAssertEqual(ai.state, .block)
        XCTAssertEqual(ai.incomingPlayerPunch(), .blocked)
        _ = collect(ai, seconds: 0.8)
        XCTAssertNotEqual(ai.state, .block)
    }

    func testDodgeReaction() {
        var p = profile(patterns: [])
        p.blockChance = 0
        p.dodgeChance = 1
        p.reactionTime = 0.2
        let ai = OpponentAI(profile: p)
        _ = ai.incomingPlayerPunch()
        _ = collect(ai, seconds: 0.25)
        XCTAssertEqual(ai.state, .dodge)
        XCTAssertEqual(ai.incomingPlayerPunch(), .dodged)
    }

    func testCounterAttackFollowsADefendedPunch() {
        var p = profile(patterns: [])
        p.blockChance = 1
        p.counterChance = 1
        p.reactionTime = 0.1
        p.blockDuration = 0.3
        let ai = OpponentAI(profile: p)
        _ = ai.incomingPlayerPunch()
        _ = collect(ai, seconds: 0.15)
        XCTAssertEqual(ai.incomingPlayerPunch(), .blocked)   // sets counter intent
        let events = collect(ai, seconds: 2.0)
        XCTAssertTrue(events.contains { if case .telegraphStarted = $0 { return true } else { return false } })
    }

    func testFeintStartsWindupThenCancels() {
        let p = profile(patterns: [AttackPattern("feint", [.feint(.jab), .attack(.cross)])])
        let ai = OpponentAI(profile: p)
        let events = collect(ai, seconds: 6)
        var order: [String] = []
        for e in events {
            switch e {
            case .telegraphStarted(let k, _, let feint): order.append(feint ? "feint-\(k.rawValue)" : "tele-\(k.rawValue)")
            case .feintCancelled: order.append("cancelled")
            case .impact(let k): order.append("hit-\(k.rawValue)")
            default: break
            }
        }
        XCTAssertEqual(Array(order.prefix(4)), ["feint-jab", "cancelled", "tele-cross", "hit-cross"])
    }

    func testKnockedDownOpponentDoesNothingUntilGetUp() {
        let ai = OpponentAI(profile: profile(patterns: [AttackPattern("jab", [.attack(.jab)])]))
        ai.knockDown()
        let events = collect(ai, seconds: 5)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(ai.state, .knockedDown)
        ai.getUp()
        XCTAssertEqual(ai.state, .vulnerable)
    }

    // MARK: Roster design

    func testFiveOpponentsWithDistinctStyles() {
        let roster = OpponentProfile.roster
        XCTAssertEqual(roster.count, 5)
        XCTAssertEqual(roster.map { $0.styleTitle },
                       ["BEGINNER", "STREET FIGHTER", "COUNTER BOXER", "AGGRESSIVE BOXER", "CHAMPION"])
        XCTAssertEqual(roster.map { $0.rank }, CareerRank.allCases)
        XCTAssertEqual(Set(roster.map { $0.id }).count, 5)
    }

    func testDifficultyIsNotJustHealth() {
        let r = OpponentProfile.roster
        // Faster attacks as you climb (champion fastest).
        XCTAssertLessThan(r[1].telegraphScale, r[0].telegraphScale)
        XCTAssertLessThan(r[4].telegraphScale, r[1].telegraphScale)
        // Counter boxer blocks the most.
        XCTAssertEqual(r.max(by: { $0.blockChance < $1.blockChance })?.id, 2)
        // Aggressive boxer rests the least between combos.
        XCTAssertEqual(r.min(by: { $0.restMax < $1.restMax })?.id, 3)
        // The champion reacts fastest, counters and dodges most.
        XCTAssertEqual(r.min(by: { $0.reactionTime < $1.reactionTime })?.id, 4)
        XCTAssertEqual(r.max(by: { $0.counterChance < $1.counterChance })?.id, 4)
        XCTAssertEqual(r.max(by: { $0.dodgeChance < $1.dodgeChance })?.id, 4)
        // Health grows only modestly.
        let health = r.map { $0.health }
        XCTAssertLessThan(health.max()! / health.min()!, 1.7)
        // Only the champion feints.
        let feints = r.map { p in p.patterns.contains { $0.steps.contains { if case .feint = $0 { return true } else { return false } } } }
        XCTAssertEqual(feints, [false, false, false, false, true])
        // Combo lengths differ.
        func longest(_ p: OpponentProfile) -> Int {
            p.patterns.map { $0.steps.filter { if case .attack = $0 { return true } else { return false } }.count }.max() ?? 0
        }
        XCTAssertLessThan(longest(r[0]), longest(r[3]))
    }

    func testTitleDefenceScalingMakesRematchesHarder() {
        let base = OpponentProfile.roster[2]
        let hard = base.scaled(tier: 1)
        XCTAssertLessThan(hard.reactionTime, base.reactionTime)
        XCTAssertLessThan(hard.telegraphScale, base.telegraphScale)
        XCTAssertGreaterThan(hard.damageScale, base.damageScale)
        XCTAssertGreaterThan(hard.rewardScale, base.rewardScale)
        XCTAssertEqual(base.scaled(tier: 0).reactionTime, base.reactionTime)
    }

    func testAIIsDeterministicForAGivenSeed() {
        func trace(seed: UInt64) -> [String] {
            let ai = OpponentAI(profile: OpponentProfile.roster[1], seed: seed)
            return collect(ai, seconds: 20).compactMap {
                if case .telegraphStarted(let k, _, _) = $0 { return k.rawValue } else { return nil }
            }
        }
        XCTAssertEqual(trace(seed: 11), trace(seed: 11))
    }
}
