import Foundation

public enum ChallengeKind: String, Codable, CaseIterable, Sendable {
    case jabs, crosses, hooks, uppercuts
    case perfectPunches, counters, combos
    case landedPunches, dodges, blocks, wins, maxCombo

    public func title(target: Int) -> String {
        switch self {
        case .jabs: return "Perform \(target) Jabs"
        case .crosses: return "Throw \(target) Crosses"
        case .hooks: return "Throw \(target) Hooks"
        case .uppercuts: return "Land \(target) Uppercuts"
        case .perfectPunches: return "Land \(target) Perfect Punches"
        case .counters: return "Perform \(target) Counters"
        case .combos: return "Land \(target) Combos of 3+"
        case .landedPunches: return "Land \(target) Punches"
        case .dodges: return "Dodge \(target) Attacks"
        case .blocks: return "Block \(target) Attacks"
        case .wins: return target == 1 ? "Win a Fight" : "Win \(target) Fights"
        case .maxCombo: return "Reach a \(target)-Hit Combo"
        }
    }

    public var icon: String {
        switch self {
        case .jabs, .crosses, .hooks, .uppercuts, .landedPunches: return "🥊"
        case .perfectPunches: return "🎯"
        case .counters: return "⚡"
        case .combos, .maxCombo: return "🔥"
        case .dodges: return "💨"
        case .blocks: return "🛡"
        case .wins: return "🏆"
        }
    }

    public var targets: [Int] {
        switch self {
        case .jabs: return [15, 20, 30]
        case .crosses: return [10, 15, 20]
        case .hooks: return [8, 12, 16]
        case .uppercuts: return [5, 8, 10]
        case .perfectPunches: return [3, 5, 8]
        case .counters: return [2, 3, 5]
        case .combos: return [2, 3, 5]
        case .landedPunches: return [30, 45, 60]
        case .dodges: return [4, 6, 10]
        case .blocks: return [4, 6, 8]
        case .wins: return [1, 2]
        case .maxCombo: return [4, 5, 6]
        }
    }

    /// How much one fight contributes.
    func contribution(from stats: FightStats, won: Bool) -> Int {
        switch self {
        case .jabs: return stats.thrown(.jab)
        case .crosses: return stats.thrown(.cross)
        case .hooks: return stats.thrown(.leftHook) + stats.thrown(.rightHook)
        case .uppercuts: return stats.landed(.uppercut)
        case .perfectPunches: return stats.perfectPunches
        case .counters: return stats.counters
        case .combos: return stats.combos
        case .landedPunches: return stats.punchesLanded
        case .dodges: return stats.dodges
        case .blocks: return stats.blocks
        case .wins: return won ? 1 : 0
        case .maxCombo: return stats.maxCombo
        }
    }
}

public struct DailyChallenge: Codable, Identifiable, Equatable, Sendable {
    public static let rewardXP = 100
    public static let rewardCoins = 50

    public var id: String
    public var kind: ChallengeKind
    public var target: Int
    public var progress: Int
    public var claimed: Bool

    public var isComplete: Bool { progress >= target }
    public var title: String { kind.title(target: target) }
    public var fraction: Double { target == 0 ? 1 : min(1, Double(progress) / Double(target)) }
}

/// Three challenges per day, chosen deterministically from the date so the
/// same day always shows the same set (and works offline).
public struct DailyChallengeState: Codable, Equatable, Sendable {
    public var dayKey: String
    public var challenges: [DailyChallenge]

    public init(dayKey: String = "", challenges: [DailyChallenge] = []) {
        self.dayKey = dayKey
        self.challenges = challenges
    }

    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func generate(for date: Date, calendar: Calendar = .current) -> DailyChallengeState {
        let key = dayKey(for: date, calendar: calendar)
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let year: Int = c.year ?? 0
        let month: Int = c.month ?? 0
        let day: Int = c.day ?? 0
        let seedValue: Int = year * 10_000 + month * 100 + day
        var rng = SeededRNG(seed: UInt64(seedValue))

        // One of the classic three always appears; the rest are random.
        let classic: [ChallengeKind] = [.jabs, .perfectPunches, .counters]
        let first = classic[Int(rng.next() % UInt64(classic.count))]
        var pool = ChallengeKind.allCases.filter { $0 != first }
        for i in stride(from: pool.count - 1, to: 0, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            pool.swapAt(i, j)
        }
        let kinds = [first] + Array(pool.prefix(2))
        let challenges = kinds.map { kind -> DailyChallenge in
            let targets = kind.targets
            let target = targets[Int(rng.next() % UInt64(targets.count))]
            return DailyChallenge(id: "\(key)-\(kind.rawValue)", kind: kind, target: target, progress: 0, claimed: false)
        }
        return DailyChallengeState(dayKey: key, challenges: challenges)
    }

    /// Replaces the challenges when the calendar day changed. Returns true if it did.
    @discardableResult
    public mutating func refreshIfNeeded(now: Date, calendar: Calendar = .current) -> Bool {
        let key = Self.dayKey(for: now, calendar: calendar)
        guard key != dayKey || challenges.isEmpty else { return false }
        self = Self.generate(for: now, calendar: calendar)
        return true
    }

    /// Adds a finished fight to every challenge. Returns ids that just became complete.
    @discardableResult
    public mutating func record(stats: FightStats, won: Bool) -> [String] {
        var completed: [String] = []
        for i in challenges.indices {
            let was = challenges[i].isComplete
            let add = challenges[i].kind.contribution(from: stats, won: won)
            if challenges[i].kind == .maxCombo {
                challenges[i].progress = max(challenges[i].progress, add)
            } else {
                challenges[i].progress += add
            }
            if !was, challenges[i].isComplete { completed.append(challenges[i].id) }
        }
        return completed
    }

    /// Marks a finished challenge as claimed. Returns the reward, or nil if not claimable.
    public mutating func claim(id: String) -> (xp: Int, coins: Int)? {
        guard let i = challenges.firstIndex(where: { $0.id == id }),
              challenges[i].isComplete, !challenges[i].claimed else { return nil }
        challenges[i].claimed = true
        return (DailyChallenge.rewardXP, DailyChallenge.rewardCoins)
    }

    public var claimableCount: Int {
        challenges.filter { $0.isComplete && !$0.claimed }.count
    }
}
