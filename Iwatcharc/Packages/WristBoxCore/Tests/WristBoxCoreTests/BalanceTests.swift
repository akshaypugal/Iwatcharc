import XCTest
@testable import WristBoxCore

/// Plays whole fights with a scripted "player" to check that the difficulty
/// curve is sensible: a skilled player beats the early opponents, a button
/// masher does not beat the late ones, and nobody wins by only dodging.
final class BalanceTests: XCTestCase {
    struct Bot {
        /// Seconds between punches.
        var punchInterval = 0.5
        /// Human reaction time to a wind-up (nil = never defends).
        var reaction: Double? = 0.30
        /// Chance a reaction dodge is correct.
        var dodgeSkill = 0.8
        var punchQuality = 0.75
    }

    /// Returns (won, outcome).
    private func fight(opponent: Int, bot: Bot, seed: UInt64, tier: Int = 0) -> FightOutcome? {
        let profile = OpponentProfile.roster[opponent].scaled(tier: tier)
        let engine = FightEngine(opponent: profile, seed: seed)
        var rng = SeededRNG(seed: seed &* 31 &+ 7)
        var sim = SimulatedController(seed: seed, quality: bot.punchQuality, jitter: 0.1)
        engine.start()

        let punches: [SimulatedInput] = [.jab, .jab, .cross, .leftHook, .jab, .cross, .rightHook, .uppercut]
        var punchIndex = 0
        var nextPunch = 0.0
        var pendingDodge: (at: Double, side: Side)?
        let dt = 1.0 / 60
        var t = 0.0
        while t < 900, !engine.isOver {
            engine.update(dt)
            t += dt

            for e in engine.drainEvents() {
                switch e {
                case .opponentAttack(_, let r, _): diag["attack-\(r)", default: 0] += 1
                case .opponentStateChanged(let st): diag["state-\(st)", default: 0] += 1
                case .specialStarted: diag["special", default: 0] += 1
                case .knockdown(let who, _): diag["knockdown-\(who)", default: 0] += 1
                case .interrupted: diag["interrupted", default: 0] += 1
                default: break
                }
                if case .opponentTelegraph(let kind, let duration, let feint) = e, let r = bot.reaction, !feint {
                    let at = engine.time + r + rng.range(-0.05, 0.08)
                    if r < duration - 0.05, rng.chance(bot.dodgeSkill) {
                        let side = kind.dodgeSides.count == 1 ? kind.dodgeSides[0] : (rng.chance(0.5) ? Side.left : Side.right)
                        pendingDodge = (at, side)
                    } else if r < duration - 0.05, kind.dodgeSides.count == 1 {
                        pendingDodge = (at, kind.dodgeSides[0].opposite)   // dodged the wrong way
                    }
                }
            }
            if let d = pendingDodge, engine.time >= d.at {
                engine.handle(d.side == .left ? sim.event(for: .dodgeLeft) : sim.event(for: .dodgeRight))
                pendingDodge = nil
            }
            if engine.phase == .fighting, engine.time >= nextPunch {
                engine.handle(sim.event(for: punches[punchIndex % punches.count]))
                punchIndex += 1
                nextPunch = engine.time + bot.punchInterval
            }
            if engine.specialReady { engine.handle(sim.event(for: .special)) }
        }
        return engine.outcome
    }

    private func winRate(opponent: Int, bot: Bot, seeds: Int = 12, tier: Int = 0) -> Double {
        var wins = 0
        var finished = 0
        var kos = 0
        var duration = 0.0
        for s in 1...seeds {
            if let o = fight(opponent: opponent, bot: bot, seed: UInt64(s), tier: tier) {
                finished += 1
                duration += o.duration
                if o.method == .ko { kos += 1 }
                if o.playerWon { wins += 1 }
            }
        }
        lastSummary = "ko \(kos)/\(finished) avg \(Int(duration / Double(max(1, finished))))s"
        
        XCTAssertEqual(finished, seeds, "every fight must finish")
        return Double(wins) / Double(seeds)
    }

    private var lastSummary = ""
    private var diag: [String: Int] = [:]

    func testPrintDiagnostics() {
        for (name, bot) in [("skilled", Bot()), ("masher", Bot(punchInterval: 0.2, reaction: nil, punchQuality: 0.6))] {
            for opp in [0, 4] {
                diag = [:]
                let o = fight(opponent: opp, bot: bot, seed: 1)
                let items = diag.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
                print("DIAG \(name) opp\(opp) dur=\(Int(o?.duration ?? 0)) landed=\(o?.stats.punchesLanded ?? 0)/\(o?.stats.punchesThrown ?? 0) dealt=\(Int(o?.stats.damageDealt ?? 0)) taken=\(Int(o?.stats.damageTaken ?? 0)) \(items)")
            }
        }
    }

    func testPrintWinRates() {
        let skilled = Bot(punchInterval: 0.55, reaction: 0.38, dodgeSkill: 0.75)
        let average = Bot(punchInterval: 0.7, reaction: 0.5, dodgeSkill: 0.5)
        let masher = Bot(punchInterval: 0.2, reaction: nil, punchQuality: 0.6)
        var lines: [String] = []
        for i in 0..<5 {
            let a = winRate(opponent: i, bot: skilled)
            let sa = lastSummary
            let m = winRate(opponent: i, bot: average)
            let sm = lastSummary
            let b = winRate(opponent: i, bot: masher)
            lines.append("opp \(i): skilled \(a) (\(sa)) | average \(m) (\(sm)) | masher \(b) (\(lastSummary))")
        }
        print("BALANCE\n" + lines.joined(separator: "\n"))
    }

    private let skilled = Bot(punchInterval: 0.55, reaction: 0.38, dodgeSkill: 0.75)
    private let average = Bot(punchInterval: 0.7, reaction: 0.5, dodgeSkill: 0.5)
    private let masher = Bot(punchInterval: 0.2, reaction: nil, punchQuality: 0.6)

    func testBeginnerIsBeatableByAveragePlayers() {
        XCTAssertGreaterThanOrEqual(winRate(opponent: 0, bot: average), 0.8)
        XCTAssertGreaterThanOrEqual(winRate(opponent: 0, bot: skilled), 0.9)
    }

    func testMashingWithoutDefenceFailsAgainstTheLateOpponents() {
        XCTAssertLessThanOrEqual(winRate(opponent: 3, bot: masher), 0.2)
        XCTAssertLessThanOrEqual(winRate(opponent: 4, bot: masher), 0.2)
    }

    func testAveragePlayersStruggleAgainstTheChampion() {
        XCTAssertLessThanOrEqual(winRate(opponent: 4, bot: average), 0.34)
    }

    func testDefenceSkillMattersAgainstTheChampion() {
        XCTAssertGreaterThan(winRate(opponent: 4, bot: skilled), winRate(opponent: 4, bot: average))
    }

    func testDifficultyRisesAcrossTheCareer() {
        XCTAssertGreaterThan(winRate(opponent: 0, bot: average), winRate(opponent: 3, bot: average))
        XCTAssertGreaterThan(winRate(opponent: 0, bot: average), winRate(opponent: 4, bot: average))
    }

    func testEveryFightEndsWithinAReasonableTime() {
        for i in 0..<5 {
            guard let o = fight(opponent: i, bot: average, seed: 3) else { return XCTFail("fight \(i) did not finish") }
            XCTAssertLessThan(o.duration, 400)
        }
    }
}
