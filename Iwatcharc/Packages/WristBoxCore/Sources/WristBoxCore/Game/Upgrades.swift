import Foundation

public enum UpgradeStat: String, Codable, CaseIterable, Identifiable, Sendable {
    case power, speed, defense, stamina

    public var id: String { rawValue }

    public var title: String { rawValue.uppercased() }

    public var icon: String {
        switch self {
        case .power: return "💥"
        case .speed: return "⚡"
        case .defense: return "🛡"
        case .stamina: return "🫁"
        }
    }

    public var blurb: String {
        switch self {
        case .power: return "+5% punch damage per level"
        case .speed: return "Longer combo and counter windows"
        case .defense: return "Take less damage, block better"
        case .stamina: return "Bigger stamina bar, faster recovery"
        }
    }
}

/// The four MVP upgrades. Deliberately simple: no skill trees.
public struct PlayerUpgrades: Codable, Equatable, Sendable {
    public static let maxLevel = 10

    public var power: Int
    public var speed: Int
    public var defense: Int
    public var stamina: Int

    public init(power: Int = 0, speed: Int = 0, defense: Int = 0, stamina: Int = 0) {
        self.power = power
        self.speed = speed
        self.defense = defense
        self.stamina = stamina
    }

    private enum CodingKeys: String, CodingKey { case power, speed, defense, stamina }

    /// Tolerant decoding: missing or invalid levels become 0, out-of-range ones are clamped.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func level(_ key: CodingKeys) -> Int {
            min(max((try? c.decode(Int.self, forKey: key)) ?? 0, 0), Self.maxLevel)
        }
        power = level(.power)
        speed = level(.speed)
        defense = level(.defense)
        stamina = level(.stamina)
    }

    public func level(_ stat: UpgradeStat) -> Int {
        switch stat {
        case .power: return power
        case .speed: return speed
        case .defense: return defense
        case .stamina: return stamina
        }
    }

    public mutating func setLevel(_ stat: UpgradeStat, _ value: Int) {
        let v = min(max(value, 0), Self.maxLevel)
        switch stat {
        case .power: power = v
        case .speed: speed = v
        case .defense: defense = v
        case .stamina: stamina = v
        }
    }

    /// Coins needed to go from `current` to `current + 1`. Level 3 -> 4 costs 100.
    public static func cost(fromLevel current: Int) -> Int { 40 + 20 * current }

    public func cost(for stat: UpgradeStat) -> Int? {
        let l = level(stat)
        return l >= Self.maxLevel ? nil : Self.cost(fromLevel: l)
    }

    // MARK: Effects

    public var damageMultiplier: Double { 1 + 0.05 * Double(power) }
    public var comboWindowMultiplier: Double { 1 + 0.06 * Double(speed) }
    public var counterWindowMultiplier: Double { 1 + 0.05 * Double(speed) }
    public var staminaCostMultiplier: Double { 1 - 0.02 * Double(speed) }
    /// Fraction of incoming damage removed.
    public var defenseReduction: Double { min(0.45, 0.035 * Double(defense)) }
    /// Extra fraction of damage removed while blocking.
    public var blockBonus: Double { 0.015 * Double(defense) }
    public var staminaMax: Double { 100 + 8 * Double(stamina) }
    public var staminaRegenMultiplier: Double { 1 + 0.06 * Double(stamina) }
}
