import Foundation

/// Statistics of one fight (and, merged, of a whole career).
public struct FightStats: Codable, Equatable, Sendable {
    public var punchesThrown: Int
    public var punchesLanded: Int
    public var perfectPunches: Int
    public var counters: Int
    public var maxCombo: Int
    public var damageDealt: Double

    // Extras used by results, challenges and the stats screen.
    public var damageTaken: Double
    /// Number of combos of 3 or more hits.
    public var combos: Int
    public var dodges: Int
    public var blocks: Int
    public var knockdowns: Int
    /// Punches that connected, keyed by `PunchType.rawValue`.
    public var landedByType: [String: Int]
    /// Punches thrown, keyed by `PunchType.rawValue`.
    public var thrownByType: [String: Int]

    public init(punchesThrown: Int = 0,
                punchesLanded: Int = 0,
                perfectPunches: Int = 0,
                counters: Int = 0,
                maxCombo: Int = 0,
                damageDealt: Double = 0,
                damageTaken: Double = 0,
                combos: Int = 0,
                dodges: Int = 0,
                blocks: Int = 0,
                knockdowns: Int = 0,
                landedByType: [String: Int] = [:],
                thrownByType: [String: Int] = [:]) {
        self.punchesThrown = punchesThrown
        self.punchesLanded = punchesLanded
        self.perfectPunches = perfectPunches
        self.counters = counters
        self.maxCombo = maxCombo
        self.damageDealt = damageDealt
        self.damageTaken = damageTaken
        self.combos = combos
        self.dodges = dodges
        self.blocks = blocks
        self.knockdowns = knockdowns
        self.landedByType = landedByType
        self.thrownByType = thrownByType
    }

    /// Landed / thrown, 0...1.
    public var accuracy: Double {
        punchesThrown == 0 ? 0 : Double(punchesLanded) / Double(punchesThrown)
    }

    public func landed(_ type: PunchType) -> Int { landedByType[type.rawValue] ?? 0 }
    public func thrown(_ type: PunchType) -> Int { thrownByType[type.rawValue] ?? 0 }

    /// Hooks of either side.
    public var hooksLanded: Int { landed(.leftHook) + landed(.rightHook) }

    mutating func recordThrown(_ type: PunchType) {
        punchesThrown += 1
        thrownByType[type.rawValue, default: 0] += 1
    }

    mutating func recordLanded(_ type: PunchType) {
        punchesLanded += 1
        landedByType[type.rawValue, default: 0] += 1
    }

    /// Adds another fight's numbers (max combo takes the maximum).
    public mutating func merge(_ o: FightStats) {
        punchesThrown += o.punchesThrown
        punchesLanded += o.punchesLanded
        perfectPunches += o.perfectPunches
        counters += o.counters
        maxCombo = max(maxCombo, o.maxCombo)
        damageDealt += o.damageDealt
        damageTaken += o.damageTaken
        combos += o.combos
        dodges += o.dodges
        blocks += o.blocks
        knockdowns += o.knockdowns
        for (k, v) in o.landedByType { landedByType[k, default: 0] += v }
        for (k, v) in o.thrownByType { thrownByType[k, default: 0] += v }
    }
}
