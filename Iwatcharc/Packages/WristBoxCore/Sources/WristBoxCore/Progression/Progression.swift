import Foundation

/// Everything that is saved between launches.
public struct PlayerProfile: Codable, Equatable, Sendable {
    public var level: Int
    /// XP earned inside the current level.
    public var xp: Int
    public var totalXP: Int
    public var coins: Int
    public var upgrades: PlayerUpgrades
    /// Opponents beaten in career order (0...5).
    public var careerProgress: Int
    /// Wins per opponent id.
    public var opponentWins: [Int]
    public var fightsPlayed: Int
    public var fightsWon: Int
    public var knockouts: Int
    /// Career totals.
    public var lifetime: FightStats
    public var calibration: Calibration
    public var settings: AppSettings
    public var daily: DailyChallengeState
    public var hasOnboarded: Bool

    public init() {
        level = 1
        xp = 0
        totalXP = 0
        coins = 0
        upgrades = PlayerUpgrades()
        careerProgress = 0
        opponentWins = Array(repeating: 0, count: OpponentProfile.roster.count)
        fightsPlayed = 0
        fightsWon = 0
        knockouts = 0
        lifetime = FightStats()
        calibration = .default
        settings = AppSettings()
        daily = DailyChallengeState()
        hasOnboarded = false
    }

    private enum CodingKeys: String, CodingKey {
        case level, xp, totalXP, coins, upgrades, careerProgress, opponentWins
        case fightsPlayed, fightsWon, knockouts, lifetime, calibration, settings, daily, hasOnboarded
    }

    /// Tolerant decoding: unknown / missing / corrupt fields fall back to defaults.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        level = max(1, (try? c.decode(Int.self, forKey: .level)) ?? 1)
        xp = max(0, (try? c.decode(Int.self, forKey: .xp)) ?? 0)
        totalXP = max(0, (try? c.decode(Int.self, forKey: .totalXP)) ?? 0)
        coins = max(0, (try? c.decode(Int.self, forKey: .coins)) ?? 0)
        upgrades = (try? c.decode(PlayerUpgrades.self, forKey: .upgrades)) ?? PlayerUpgrades()
        careerProgress = min(max(0, (try? c.decode(Int.self, forKey: .careerProgress)) ?? 0), OpponentProfile.roster.count)
        var wins = (try? c.decode([Int].self, forKey: .opponentWins)) ?? []
        while wins.count < OpponentProfile.roster.count { wins.append(0) }
        opponentWins = wins
        fightsPlayed = (try? c.decode(Int.self, forKey: .fightsPlayed)) ?? 0
        fightsWon = (try? c.decode(Int.self, forKey: .fightsWon)) ?? 0
        knockouts = (try? c.decode(Int.self, forKey: .knockouts)) ?? 0
        lifetime = (try? c.decode(FightStats.self, forKey: .lifetime)) ?? FightStats()
        calibration = (try? c.decode(Calibration.self, forKey: .calibration)) ?? .default
        settings = (try? c.decode(AppSettings.self, forKey: .settings)) ?? AppSettings()
        daily = (try? c.decode(DailyChallengeState.self, forKey: .daily)) ?? DailyChallengeState()
        hasOnboarded = (try? c.decode(Bool.self, forKey: .hasOnboarded)) ?? false
    }

    // MARK: Level

    public static func xpNeeded(forLevel level: Int) -> Int { 120 + 60 * (level - 1) }

    public var xpToNextLevel: Int { Self.xpNeeded(forLevel: level) }

    public var xpFraction: Double { clamp(Double(xp) / Double(xpToNextLevel)) }

    /// Adds XP and returns how many levels were gained.
    @discardableResult
    public mutating func addXP(_ amount: Int) -> Int {
        guard amount > 0 else { return 0 }
        totalXP += amount
        xp += amount
        var gained = 0
        while xp >= xpToNextLevel {
            xp -= xpToNextLevel
            level += 1
            gained += 1
        }
        return gained
    }

    // MARK: Career

    public var careerCleared: Bool { careerProgress >= OpponentProfile.roster.count }

    /// Number of opponents the player may fight.
    public var unlockedOpponentCount: Int {
        careerCleared ? OpponentProfile.roster.count : careerProgress + 1
    }

    public func isUnlocked(opponent id: Int) -> Bool { id < unlockedOpponentCount }

    /// Current career rank: BOXER -> ROOKIE -> CONTENDER -> PRO -> CHAMPION.
    public var rank: CareerRank {
        let i = min(careerProgress, OpponentProfile.roster.count - 1)
        return OpponentProfile.roster[i].rank
    }

    /// Title Defence tier unlocked after beating the champion (rematches get harder).
    public var maxTier: Int { careerCleared ? 1 + min(opponentWins.min() ?? 0, 2) : 0 }
}

public struct RewardLine: Equatable, Sendable {
    public var title: String
    public var xp: Int
    public var coins: Int
}

public struct RewardSummary: Equatable, Sendable {
    public var won: Bool
    public var method: FightMethod
    public var xp: Int
    public var coins: Int
    public var lines: [RewardLine]
    public var levelsGained: Int
    public var newLevel: Int
    /// Opponent id unlocked by this win, if any.
    public var unlockedOpponent: Int?
    public var careerCompleted: Bool
    public var completedChallenges: [String]
    public var stats: FightStats
    public var playerRoundsWon: Int
    public var opponentRoundsWon: Int
}

public enum Rewards {
    /// XP and coin breakdown for a finished fight.
    public static func lines(for outcome: FightOutcome, opponent: OpponentProfile) -> [RewardLine] {
        let s = outcome.stats
        let won = outcome.playerWon
        let scale = opponent.rewardScale
        let baseXP = Double(120 + 45 * opponent.id)
        let baseCoins = Double(40 + 20 * opponent.id)
        let extra = won ? 1.0 : 0.5

        func line(_ title: String, xp: Double, coins: Double, factor: Double = 1) -> RewardLine {
            RewardLine(title: title, xp: Int((xp * factor).rounded()), coins: Int((coins * factor).rounded()))
        }

        var out: [RewardLine] = []
        if won {
            out.append(line("Victory", xp: baseXP, coins: baseCoins, factor: scale))
            if outcome.method == .ko {
                out.append(line("Knockout", xp: 60, coins: 30, factor: scale))
            }
        } else {
            out.append(line("Fight bonus", xp: baseXP * 0.25, coins: baseCoins * 0.25, factor: scale))
        }
        if s.maxCombo >= 3 {
            let c = Double(min(s.maxCombo, 12))
            out.append(line("Best combo x\(s.maxCombo)", xp: c * 6, coins: c * 3, factor: extra))
        }
        if s.counters > 0 {
            let c = Double(s.counters)
            out.append(line("Counters x\(s.counters)", xp: c * 12, coins: c * 6, factor: extra))
        }
        if s.perfectPunches > 0 {
            let c = Double(s.perfectPunches)
            out.append(line("Perfect punches x\(s.perfectPunches)", xp: c * 5, coins: c * 2, factor: extra))
        }
        if s.punchesThrown >= 10, s.accuracy >= 0.7 {
            out.append(line("Accuracy bonus", xp: 40, coins: 15, factor: extra))
        }
        return out
    }
}

public enum ProgressionService {
    /// Applies a finished fight to the profile: XP, coins, level, career
    /// unlocks, lifetime stats and daily challenges.
    @discardableResult
    public static func apply(outcome: FightOutcome,
                             opponent: OpponentProfile,
                             tier: Int = 0,
                             to profile: inout PlayerProfile,
                             now: Date = Date(),
                             calendar: Calendar = .current) -> RewardSummary {
        profile.daily.refreshIfNeeded(now: now, calendar: calendar)

        let lines = Rewards.lines(for: outcome, opponent: opponent)
        let xp = lines.reduce(0) { $0 + $1.xp }
        let coins = lines.reduce(0) { $0 + $1.coins }

        profile.fightsPlayed += 1
        profile.lifetime.merge(outcome.stats)
        var unlocked: Int?
        var completedCareer = false

        if outcome.playerWon {
            profile.fightsWon += 1
            if outcome.method == .ko { profile.knockouts += 1 }
            if opponent.id < profile.opponentWins.count { profile.opponentWins[opponent.id] += 1 }
            if tier == 0, opponent.id == profile.careerProgress {
                profile.careerProgress += 1
                if profile.careerProgress < OpponentProfile.roster.count {
                    unlocked = profile.careerProgress
                } else {
                    completedCareer = true
                }
            }
        }

        let completed = profile.daily.record(stats: outcome.stats, won: outcome.playerWon)
        let levels = profile.addXP(xp)
        profile.coins += coins

        return RewardSummary(won: outcome.playerWon,
                             method: outcome.method,
                             xp: xp,
                             coins: coins,
                             lines: lines,
                             levelsGained: levels,
                             newLevel: profile.level,
                             unlockedOpponent: unlocked,
                             careerCompleted: completedCareer,
                             completedChallenges: completed,
                             stats: outcome.stats,
                             playerRoundsWon: outcome.playerRoundsWon,
                             opponentRoundsWon: outcome.opponentRoundsWon)
    }

    /// Buys the next level of an upgrade. Returns false if maxed out or too poor.
    @discardableResult
    public static func purchase(_ stat: UpgradeStat, profile: inout PlayerProfile) -> Bool {
        guard let cost = profile.upgrades.cost(for: stat), profile.coins >= cost else { return false }
        profile.coins -= cost
        profile.upgrades.setLevel(stat, profile.upgrades.level(stat) + 1)
        return true
    }

    /// Claims a finished daily challenge (+100 XP, +50 coins).
    @discardableResult
    public static func claimChallenge(id: String, profile: inout PlayerProfile) -> (xp: Int, coins: Int, levelsGained: Int)? {
        guard let reward = profile.daily.claim(id: id) else { return nil }
        let levels = profile.addXP(reward.xp)
        profile.coins += reward.coins
        return (reward.xp, reward.coins, levels)
    }
}
