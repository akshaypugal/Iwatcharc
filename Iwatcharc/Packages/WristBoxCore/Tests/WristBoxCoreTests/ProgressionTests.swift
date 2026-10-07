import XCTest
@testable import WristBoxCore

final class ProgressionTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func outcome(won: Bool, opponent: Int = 0, method: FightMethod = .decision,
                         stats: FightStats = FightStats()) -> FightOutcome {
        FightOutcome(winner: won ? .player : .opponent, method: method,
                     playerRoundsWon: won ? 2 : 0, opponentRoundsWon: won ? 0 : 2,
                     rounds: [], stats: stats, duration: 120, opponentID: opponent)
    }

    private func goodStats() -> FightStats {
        var s = FightStats()
        s.punchesThrown = 40
        s.punchesLanded = 32
        s.perfectPunches = 3
        s.counters = 2
        s.maxCombo = 5
        s.damageDealt = 120
        s.combos = 3
        return s
    }

    // MARK: Level and XP

    func testXPLevelsUp() {
        var p = PlayerProfile()
        XCTAssertEqual(p.level, 1)
        XCTAssertEqual(p.addXP(PlayerProfile.xpNeeded(forLevel: 1)), 1)
        XCTAssertEqual(p.level, 2)
        XCTAssertEqual(p.xp, 0)
        let gained = p.addXP(10_000)
        XCTAssertGreaterThan(gained, 3)
        XCTAssertEqual(p.totalXP, PlayerProfile.xpNeeded(forLevel: 1) + 10_000)
        XCTAssertTrue((0...1).contains(p.xpFraction))
    }

    func testXPNeededGrowsEachLevel() {
        XCTAssertLessThan(PlayerProfile.xpNeeded(forLevel: 1), PlayerProfile.xpNeeded(forLevel: 2))
        XCTAssertLessThan(PlayerProfile.xpNeeded(forLevel: 5), PlayerProfile.xpNeeded(forLevel: 6))
    }

    // MARK: Rewards

    func testVictoryAwardsXPAndCoins() {
        var p = PlayerProfile()
        let r = ProgressionService.apply(outcome: outcome(won: true, method: .ko, stats: goodStats()),
                                         opponent: OpponentProfile.roster[0], to: &p,
                                         now: date(2026, 10, 7), calendar: utc)
        XCTAssertTrue(r.won)
        XCTAssertGreaterThan(r.xp, 200)
        XCTAssertGreaterThan(r.coins, 70)
        XCTAssertEqual(p.coins, r.coins)
        XCTAssertEqual(p.totalXP, r.xp)
        XCTAssertFalse(r.lines.isEmpty)
        XCTAssertEqual(r.lines.reduce(0) { $0 + $1.xp }, r.xp)
        XCTAssertEqual(p.fightsPlayed, 1)
        XCTAssertEqual(p.fightsWon, 1)
        XCTAssertEqual(p.knockouts, 1)
        XCTAssertEqual(p.lifetime.punchesThrown, 40)
    }

    func testDefeatStillGivesSomethingButLess() {
        var win = PlayerProfile()
        var loss = PlayerProfile()
        let w = ProgressionService.apply(outcome: outcome(won: true, stats: goodStats()), opponent: OpponentProfile.roster[0],
                                         to: &win, now: date(2026, 10, 7), calendar: utc)
        let l = ProgressionService.apply(outcome: outcome(won: false, stats: goodStats()), opponent: OpponentProfile.roster[0],
                                         to: &loss, now: date(2026, 10, 7), calendar: utc)
        XCTAssertGreaterThan(l.xp, 0)
        XCTAssertGreaterThan(l.coins, 0)
        XCTAssertLessThan(l.xp, w.xp)
        XCTAssertLessThan(l.coins, w.coins)
        XCTAssertFalse(l.won)
        XCTAssertEqual(loss.fightsWon, 0)
    }

    func testHarderOpponentsPayMore() {
        var a = PlayerProfile()
        var b = PlayerProfile()
        let r0 = ProgressionService.apply(outcome: outcome(won: true, opponent: 0), opponent: OpponentProfile.roster[0],
                                          to: &a, now: date(2026, 10, 7), calendar: utc)
        let r4 = ProgressionService.apply(outcome: outcome(won: true, opponent: 4), opponent: OpponentProfile.roster[4],
                                          to: &b, now: date(2026, 10, 7), calendar: utc)
        XCTAssertGreaterThan(r4.xp, r0.xp * 2)
    }

    func testBetterPerformanceEarnsBonuses() {
        var a = PlayerProfile()
        var b = PlayerProfile()
        let plain = ProgressionService.apply(outcome: outcome(won: true), opponent: OpponentProfile.roster[0],
                                             to: &a, now: date(2026, 10, 7), calendar: utc)
        let good = ProgressionService.apply(outcome: outcome(won: true, stats: goodStats()), opponent: OpponentProfile.roster[0],
                                            to: &b, now: date(2026, 10, 7), calendar: utc)
        XCTAssertGreaterThan(good.xp, plain.xp)
        XCTAssertGreaterThan(good.coins, plain.coins)
    }

    // MARK: Career

    func testBeatingTheCurrentOpponentUnlocksTheNext() {
        var p = PlayerProfile()
        XCTAssertEqual(p.rank, .boxer)
        XCTAssertEqual(p.unlockedOpponentCount, 1)
        XCTAssertTrue(p.isUnlocked(opponent: 0))
        XCTAssertFalse(p.isUnlocked(opponent: 1))
        let r = ProgressionService.apply(outcome: outcome(won: true), opponent: OpponentProfile.roster[0],
                                         to: &p, now: date(2026, 10, 7), calendar: utc)
        XCTAssertEqual(r.unlockedOpponent, 1)
        XCTAssertEqual(p.careerProgress, 1)
        XCTAssertEqual(p.rank, .rookie)
        XCTAssertTrue(p.isUnlocked(opponent: 1))
    }

    func testLosingDoesNotUnlockAnything() {
        var p = PlayerProfile()
        ProgressionService.apply(outcome: outcome(won: false), opponent: OpponentProfile.roster[0],
                                 to: &p, now: date(2026, 10, 7), calendar: utc)
        XCTAssertEqual(p.careerProgress, 0)
    }

    func testRematchingAnOldOpponentDoesNotAdvanceTheCareer() {
        var p = PlayerProfile()
        p.careerProgress = 2
        let r = ProgressionService.apply(outcome: outcome(won: true, opponent: 0), opponent: OpponentProfile.roster[0],
                                         to: &p, now: date(2026, 10, 7), calendar: utc)
        XCTAssertNil(r.unlockedOpponent)
        XCTAssertEqual(p.careerProgress, 2)
        XCTAssertEqual(p.opponentWins[0], 1)
    }

    func testBeatingTheChampionCompletesTheCareer() {
        var p = PlayerProfile()
        p.careerProgress = 4
        XCTAssertEqual(p.rank, .champion)
        let r = ProgressionService.apply(outcome: outcome(won: true, opponent: 4), opponent: OpponentProfile.roster[4],
                                         to: &p, now: date(2026, 10, 7), calendar: utc)
        XCTAssertTrue(r.careerCompleted)
        XCTAssertNil(r.unlockedOpponent)
        XCTAssertTrue(p.careerCleared)
        XCTAssertEqual(p.unlockedOpponentCount, 5)
        XCTAssertGreaterThanOrEqual(p.maxTier, 1, "Title Defence unlocks after the career is cleared")
    }

    func testRanksFollowTheSpec() {
        XCTAssertEqual(CareerRank.allCases.map { $0.title }, ["BOXER", "ROOKIE", "CONTENDER", "PRO", "CHAMPION"])
    }

    // MARK: Upgrades

    func testUpgradeCostMatchesTheSpecExample() {
        XCTAssertEqual(PlayerUpgrades.cost(fromLevel: 3), 100)
        XCTAssertLessThan(PlayerUpgrades.cost(fromLevel: 0), PlayerUpgrades.cost(fromLevel: 1))
    }

    func testPurchaseSpendsCoinsAndRaisesLevel() {
        var p = PlayerProfile()
        p.coins = 40
        XCTAssertTrue(ProgressionService.purchase(.power, profile: &p))
        XCTAssertEqual(p.upgrades.power, 1)
        XCTAssertEqual(p.coins, 0)
    }

    func testPurchaseFailsWhenTooPoor() {
        var p = PlayerProfile()
        p.coins = 39
        XCTAssertFalse(ProgressionService.purchase(.speed, profile: &p))
        XCTAssertEqual(p.upgrades.speed, 0)
        XCTAssertEqual(p.coins, 39)
    }

    func testUpgradesStopAtMaxLevel() {
        var p = PlayerProfile()
        p.coins = 1_000_000
        for _ in 0..<30 { ProgressionService.purchase(.defense, profile: &p) }
        XCTAssertEqual(p.upgrades.defense, PlayerUpgrades.maxLevel)
        XCTAssertNil(p.upgrades.cost(for: .defense))
        XCTAssertFalse(ProgressionService.purchase(.defense, profile: &p))
    }

    func testEachUpgradeHasAnEffect() {
        let base = PlayerUpgrades()
        let maxed = PlayerUpgrades(power: 10, speed: 10, defense: 10, stamina: 10)
        XCTAssertGreaterThan(maxed.damageMultiplier, base.damageMultiplier)
        XCTAssertGreaterThan(maxed.comboWindowMultiplier, base.comboWindowMultiplier)
        XCTAssertGreaterThan(maxed.defenseReduction, base.defenseReduction)
        XCTAssertGreaterThan(maxed.staminaMax, base.staminaMax)
        XCTAssertLessThanOrEqual(maxed.defenseReduction, 0.45)
        XCTAssertEqual(UpgradeStat.allCases.count, 4)
    }

    // MARK: Daily challenges

    func testDailyChallengesAreThreeDistinctAndDeterministic() {
        let a = DailyChallengeState.generate(for: date(2026, 10, 7), calendar: utc)
        let b = DailyChallengeState.generate(for: date(2026, 10, 7), calendar: utc)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.challenges.count, 3)
        XCTAssertEqual(Set(a.challenges.map { $0.kind }).count, 3)
        XCTAssertEqual(a.dayKey, "2026-10-07")
        XCTAssertTrue(a.challenges.allSatisfy { $0.progress == 0 && !$0.claimed && $0.target > 0 })
    }

    func testDifferentDaysGiveDifferentChallengesEventually() {
        var sets = Set<[ChallengeKind]>()
        for day in 1...20 {
            sets.insert(DailyChallengeState.generate(for: date(2026, 10, day), calendar: utc).challenges.map { $0.kind })
        }
        XCTAssertGreaterThan(sets.count, 3)
    }

    func testChallengesRefreshOnANewDayOnly() {
        var s = DailyChallengeState()
        XCTAssertTrue(s.refreshIfNeeded(now: date(2026, 10, 7), calendar: utc))
        XCTAssertFalse(s.refreshIfNeeded(now: date(2026, 10, 7), calendar: utc))
        s.challenges[0].progress = 3
        XCTAssertFalse(s.refreshIfNeeded(now: date(2026, 10, 7), calendar: utc))
        XCTAssertEqual(s.challenges[0].progress, 3)
        XCTAssertTrue(s.refreshIfNeeded(now: date(2026, 10, 8), calendar: utc))
        XCTAssertEqual(s.challenges[0].progress, 0)
    }

    func testChallengeProgressAndClaim() {
        var p = PlayerProfile()
        p.daily = DailyChallengeState(dayKey: "2026-10-07", challenges: [
            DailyChallenge(id: "a", kind: .jabs, target: 20, progress: 0, claimed: false),
            DailyChallenge(id: "b", kind: .perfectPunches, target: 3, progress: 0, claimed: false),
            DailyChallenge(id: "c", kind: .counters, target: 2, progress: 0, claimed: false)
        ])
        var stats = FightStats()
        stats.thrownByType[PunchType.jab.rawValue] = 25
        stats.perfectPunches = 1
        stats.counters = 2
        let r = ProgressionService.apply(outcome: outcome(won: true, stats: stats), opponent: OpponentProfile.roster[0],
                                         to: &p, now: date(2026, 10, 7), calendar: utc)
        XCTAssertEqual(Set(r.completedChallenges), ["a", "c"])
        XCTAssertEqual(p.daily.claimableCount, 2)

        let coinsBefore = p.coins
        let xpBefore = p.totalXP
        let claim = ProgressionService.claimChallenge(id: "a", profile: &p)
        XCTAssertEqual(claim?.xp, 100)
        XCTAssertEqual(claim?.coins, 50)
        XCTAssertEqual(p.coins, coinsBefore + 50)
        XCTAssertEqual(p.totalXP, xpBefore + 100)
        XCTAssertNil(ProgressionService.claimChallenge(id: "a", profile: &p), "cannot claim twice")
        XCTAssertNil(ProgressionService.claimChallenge(id: "b", profile: &p), "not finished yet")
        XCTAssertNil(ProgressionService.claimChallenge(id: "zzz", profile: &p))
    }

    func testMaxComboChallengeTakesTheBestNotTheSum() {
        var s = DailyChallengeState(dayKey: "d", challenges: [
            DailyChallenge(id: "m", kind: .maxCombo, target: 10, progress: 0, claimed: false)
        ])
        var stats = FightStats()
        stats.maxCombo = 4
        s.record(stats: stats, won: false)
        s.record(stats: stats, won: false)
        XCTAssertEqual(s.challenges[0].progress, 4)
    }

    func testEveryChallengeKindHasATitleAndTargets() {
        for kind in ChallengeKind.allCases {
            XCTAssertFalse(kind.targets.isEmpty)
            XCTAssertFalse(kind.title(target: kind.targets[0]).isEmpty)
        }
        XCTAssertEqual(ChallengeKind.jabs.title(target: 20), "Perform 20 Jabs")
        XCTAssertEqual(ChallengeKind.counters.title(target: 3), "Perform 3 Counters")
        XCTAssertEqual(ChallengeKind.perfectPunches.title(target: 5), "Land 5 Perfect Punches")
    }

    // MARK: Stats

    func testStatsMergeAndAccuracy() {
        var a = FightStats(punchesThrown: 10, punchesLanded: 5, perfectPunches: 1, counters: 1, maxCombo: 3, damageDealt: 20)
        let b = FightStats(punchesThrown: 10, punchesLanded: 9, perfectPunches: 2, counters: 0, maxCombo: 7, damageDealt: 30)
        a.merge(b)
        XCTAssertEqual(a.punchesThrown, 20)
        XCTAssertEqual(a.punchesLanded, 14)
        XCTAssertEqual(a.maxCombo, 7)
        XCTAssertEqual(a.damageDealt, 50)
        XCTAssertEqual(a.accuracy, 0.7, accuracy: 1e-9)
        XCTAssertEqual(FightStats().accuracy, 0)
    }

    // MARK: Persistence

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("wristbox-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profile.json")
    }

    func testProfileSurvivesSaveAndLoad() throws {
        let store = FileProfileStore(url: tempURL())
        XCTAssertNil(store.load())
        var p = PlayerProfile()
        p.level = 7
        p.coins = 321
        p.upgrades = PlayerUpgrades(power: 3, speed: 1, defense: 2, stamina: 4)
        p.careerProgress = 3
        p.hasOnboarded = true
        p.settings.developerMode = true
        p.settings.gestureConfig.jabMin = 2.1
        p.calibration.hasNeutral = true
        p.calibration.gyroBias = Vec3(0.01, 0.02, 0.03)
        p.daily = DailyChallengeState.generate(for: date(2026, 10, 7), calendar: utc)
        try store.save(p)
        XCTAssertEqual(store.load(), p)
    }

    func testCorruptFileIsMovedAsideNotCrashed() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("this is not json".utf8).write(to: url)
        let store = FileProfileStore(url: url)
        XCTAssertNil(store.load())
        let contents = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        XCTAssertTrue(contents.contains { $0.hasPrefix("profile.corrupt-") })
    }

    func testOlderOrPartialProfilesStillLoad() throws {
        let json = #"{"level": 5, "coins": 12, "settings": {"soundEnabled": false}, "upgrades": {"power": 2}}"#
        let p = try JSONDecoder().decode(PlayerProfile.self, from: Data(json.utf8))
        XCTAssertEqual(p.level, 5)
        XCTAssertEqual(p.coins, 12)
        XCTAssertFalse(p.settings.soundEnabled)
        XCTAssertTrue(p.settings.hapticsEnabled)
        XCTAssertEqual(p.upgrades.power, 2)
        XCTAssertEqual(p.opponentWins.count, OpponentProfile.roster.count)
    }

    func testGarbageFieldsFallBackToDefaults() throws {
        let json = #"{"level": "five", "coins": -50, "careerProgress": 99, "settings": 3}"#
        let p = try JSONDecoder().decode(PlayerProfile.self, from: Data(json.utf8))
        XCTAssertEqual(p.level, 1)
        XCTAssertEqual(p.coins, 0)
        XCTAssertEqual(p.careerProgress, OpponentProfile.roster.count)
        XCTAssertEqual(p.settings, AppSettings())
    }

    func testInMemoryStoreCountsSaves() throws {
        let store = InMemoryProfileStore()
        XCTAssertNil(store.load())
        try store.save(PlayerProfile())
        try store.save(PlayerProfile())
        XCTAssertEqual(store.saveCount, 2)
        XCTAssertNotNil(store.load())
    }

    func testCalibrationIsStoredWithTheProfile() throws {
        var p = PlayerProfile()
        var cal = Calibration.default
        cal.hasNeutral = true
        cal.hasForward = true
        cal.forward = Vec3(0, 1, 0)
        p.calibration = cal
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(PlayerProfile.self, from: data)
        XCTAssertEqual(back.calibration, cal)
        XCTAssertTrue(back.calibration.isCalibrated)
        p.calibration = .default
        XCTAssertFalse(p.calibration.isCalibrated, "resetCalibration returns to factory defaults")
    }
}
