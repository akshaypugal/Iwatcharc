import Foundation

public enum OpponentState: String, Equatable, Sendable {
    case idle
    case watch
    case attack
    case block
    case dodge
    case stunned
    case vulnerable
    case knockedDown
}

/// Where an opponent attack comes from, as drawn on screen.
public enum AttackOrigin: String, Equatable, Sendable {
    case left, center, right
}

public enum AttackKind: String, CaseIterable, Equatable, Sendable {
    case jab, cross, leftHook, rightHook, uppercut

    public var title: String {
        switch self {
        case .jab: return "JAB"
        case .cross: return "CROSS"
        case .leftHook: return "LEFT HOOK"
        case .rightHook: return "RIGHT HOOK"
        case .uppercut: return "UPPERCUT"
        }
    }

    /// Damage to the player before opponent scaling and defence.
    public var baseDamage: Double {
        switch self {
        case .jab: return 5
        case .cross: return 8
        case .leftHook, .rightHook: return 9
        case .uppercut: return 11
        }
    }

    /// Wind-up time (the player's reaction window) before opponent speed scaling.
    public var baseTelegraph: Double {
        switch self {
        case .jab: return 0.55
        case .cross: return 0.70
        case .leftHook, .rightHook: return 0.80
        case .uppercut: return 0.90
        }
    }

    public var origin: AttackOrigin {
        switch self {
        case .leftHook: return .left
        case .rightHook: return .right
        default: return .center
        }
    }

    /// Dodge directions that avoid this attack. Straight punches can be dodged
    /// either way; a hook must be dodged away from the side it comes from.
    public var dodgeSides: [Side] {
        switch self {
        case .leftHook: return [.right]
        case .rightHook: return [.left]
        default: return [.left, .right]
        }
    }
}

/// One step of an attack pattern script.
public enum PatternStep: Equatable, Sendable {
    /// Watch the player.
    case wait(Double)
    /// Raise the guard for a while.
    case guardUp(Double)
    case attack(AttackKind)
    /// A fast attack (used for counters).
    case quickAttack(AttackKind)
    /// Start winding up, then cancel. Baits dodges.
    case feint(AttackKind)
}

public struct AttackPattern: Equatable, Sendable {
    public var name: String
    public var steps: [PatternStep]
    public var weight: Double

    public init(_ name: String, weight: Double = 1, _ steps: [PatternStep]) {
        self.name = name
        self.weight = weight
        self.steps = steps
    }
}

/// Career rank. Each rank introduces a stronger opponent.
public enum CareerRank: Int, CaseIterable, Sendable {
    case boxer, rookie, contender, pro, champion

    public var title: String {
        switch self {
        case .boxer: return "BOXER"
        case .rookie: return "ROOKIE"
        case .contender: return "CONTENDER"
        case .pro: return "PRO"
        case .champion: return "CHAMPION"
        }
    }
}

/// An opponent is defined by *behaviour*, not just health: reaction time,
/// attack frequency, defence, counters and combo scripts all differ.
public struct OpponentProfile: Identifiable, Sendable {
    public var id: Int
    public var name: String
    public var nickname: String
    public var styleTitle: String
    public var tagline: String
    public var rank: CareerRank

    public var health: Double
    /// Seconds before the opponent reacts to a punch with a block/dodge.
    public var reactionTime: Double
    /// Multiplier on attack wind-up times (lower = faster attacks).
    public var telegraphScale: Double
    public var restMin: Double
    public var restMax: Double
    public var blockChance: Double
    public var dodgeChance: Double
    public var counterChance: Double
    public var damageScale: Double
    /// Damage that can be absorbed before being stunned.
    public var poise: Double
    /// Chance of dropping the guard (an opening) after finishing a pattern.
    public var openingChance: Double
    /// Seconds the opponent stays open after whiffing an attack.
    public var whiffOpening: Double
    public var blockDuration: Double
    public var patterns: [AttackPattern]
    /// Reward multiplier for beating this opponent.
    public var rewardScale: Double

    // Colours for the vector art (hex RGB).
    public var skinHex: String
    public var hairHex: String
    public var trunksHex: String
    public var gloveHex: String

    public init(id: Int, name: String, nickname: String, styleTitle: String, tagline: String, rank: CareerRank,
                health: Double, reactionTime: Double, telegraphScale: Double,
                restMin: Double, restMax: Double,
                blockChance: Double, dodgeChance: Double, counterChance: Double,
                damageScale: Double, poise: Double, openingChance: Double,
                whiffOpening: Double, blockDuration: Double,
                patterns: [AttackPattern], rewardScale: Double,
                skinHex: String, hairHex: String, trunksHex: String, gloveHex: String) {
        self.id = id
        self.name = name
        self.nickname = nickname
        self.styleTitle = styleTitle
        self.tagline = tagline
        self.rank = rank
        self.health = health
        self.reactionTime = reactionTime
        self.telegraphScale = telegraphScale
        self.restMin = restMin
        self.restMax = restMax
        self.blockChance = blockChance
        self.dodgeChance = dodgeChance
        self.counterChance = counterChance
        self.damageScale = damageScale
        self.poise = poise
        self.openingChance = openingChance
        self.whiffOpening = whiffOpening
        self.blockDuration = blockDuration
        self.patterns = patterns
        self.rewardScale = rewardScale
        self.skinHex = skinHex
        self.hairHex = hairHex
        self.trunksHex = trunksHex
        self.gloveHex = gloveHex
    }

    /// A tougher rematch (Title Defence): faster, harder hitting, better defence.
    public func scaled(tier: Int) -> OpponentProfile {
        guard tier > 0 else { return self }
        let t = Double(tier)
        var p = self
        p.reactionTime = max(0.15, reactionTime * pow(0.85, t))
        p.telegraphScale = max(0.55, telegraphScale * pow(0.92, t))
        p.restMin = max(0.3, restMin * pow(0.85, t))
        p.restMax = max(p.restMin + 0.1, restMax * pow(0.85, t))
        p.damageScale = damageScale * (1 + 0.15 * t)
        p.blockChance = min(0.85, blockChance + 0.08 * t)
        p.dodgeChance = min(0.6, dodgeChance + 0.06 * t)
        p.counterChance = min(0.7, counterChance + 0.08 * t)
        p.health = health * (1 + 0.1 * t)
        p.rewardScale = rewardScale * (1 + 0.5 * t)
        return p
    }

    // MARK: Roster

    public static let roster: [OpponentProfile] = [
        OpponentProfile(
            id: 0, name: "Sam Miller", nickname: "Softhands", styleTitle: "BEGINNER",
            tagline: "Slow, telegraphed and easy to read. Learn the basics.",
            rank: .boxer,
            health: 90, reactionTime: 0.70, telegraphScale: 1.40, restMin: 1.8, restMax: 2.8,
            blockChance: 0.08, dodgeChance: 0.04, counterChance: 0.0,
            damageScale: 0.75, poise: 24, openingChance: 0.7, whiffOpening: 1.2, blockDuration: 0.5,
            patterns: [
                AttackPattern("Lone jab", weight: 2, [.attack(.jab)]),
                AttackPattern("Jab, cross", weight: 1, [.attack(.jab), .wait(0.6), .attack(.cross)]),
                AttackPattern("Big cross", weight: 1, [.wait(0.6), .attack(.cross)])
            ],
            rewardScale: 1.0,
            skinHex: "F1C27D", hairHex: "5A3A22", trunksHex: "3D7DD8", gloveHex: "3D7DD8"),

        OpponentProfile(
            id: 1, name: "Rico Vega", nickname: "Alley Cat", styleTitle: "STREET FIGHTER",
            tagline: "Faster hands and loose hooks. Keep moving.",
            rank: .rookie,
            health: 100, reactionTime: 0.50, telegraphScale: 1.10, restMin: 1.2, restMax: 2.0,
            blockChance: 0.20, dodgeChance: 0.15, counterChance: 0.08,
            damageScale: 0.95, poise: 33, openingChance: 0.55, whiffOpening: 1.0, blockDuration: 0.6,
            patterns: [
                AttackPattern("Double jab", [.attack(.jab), .attack(.jab)]),
                AttackPattern("One-two", [.attack(.jab), .attack(.cross)]),
                AttackPattern("Wild hooks", [.attack(.leftHook), .wait(0.2), .attack(.rightHook)]),
                AttackPattern("Jab, cross, hook", [.attack(.jab), .attack(.cross), .attack(.leftHook)])
            ],
            rewardScale: 1.15,
            skinHex: "C68642", hairHex: "1B1B1B", trunksHex: "E8A317", gloveHex: "D9480F"),

        OpponentProfile(
            id: 2, name: "Marcus Hayes", nickname: "The Wall", styleTitle: "COUNTER BOXER",
            tagline: "Hides behind his guard and punishes every mistake.",
            rank: .contender,
            health: 110, reactionTime: 0.36, telegraphScale: 1.0, restMin: 1.4, restMax: 2.3,
            blockChance: 0.60, dodgeChance: 0.12, counterChance: 0.35,
            damageScale: 1.0, poise: 48, openingChance: 0.4, whiffOpening: 0.9, blockDuration: 1.0,
            patterns: [
                AttackPattern("Guard, cross", weight: 2, [.guardUp(0.8), .attack(.cross)]),
                AttackPattern("Jab, guard, cross", [.attack(.jab), .guardUp(0.7), .attack(.cross)]),
                AttackPattern("Patient combo", [.guardUp(0.6), .attack(.jab), .attack(.jab), .attack(.cross)])
            ],
            rewardScale: 1.3,
            skinHex: "8D5524", hairHex: "111111", trunksHex: "2F9E44", gloveHex: "1F6F31"),

        OpponentProfile(
            id: 3, name: "Viktor Kozlov", nickname: "Bulldozer", styleTitle: "AGGRESSIVE BOXER",
            tagline: "Constant pressure and long combinations. Don't get cornered.",
            rank: .pro,
            health: 120, reactionTime: 0.42, telegraphScale: 0.92, restMin: 0.5, restMax: 1.0,
            blockChance: 0.12, dodgeChance: 0.08, counterChance: 0.10,
            damageScale: 1.1, poise: 60, openingChance: 0.25, whiffOpening: 0.8, blockDuration: 0.5,
            patterns: [
                AttackPattern("Four-piece", [.attack(.jab), .attack(.cross), .attack(.leftHook), .attack(.rightHook)]),
                AttackPattern("Hook, uppercut", [.attack(.leftHook), .attack(.uppercut)]),
                AttackPattern("Jab jab cross upper", [.attack(.jab), .attack(.jab), .attack(.cross), .attack(.uppercut)]),
                AttackPattern("Cross, hook, cross", [.attack(.cross), .attack(.rightHook), .attack(.cross)])
            ],
            rewardScale: 1.5,
            skinHex: "F1C27D", hairHex: "C9B037", trunksHex: "C92A2A", gloveHex: "8B1A1A"),

        OpponentProfile(
            id: 4, name: "Leon Dubois", nickname: "The King", styleTitle: "CHAMPION",
            tagline: "Fast hands, feints, counters and a tight guard. The final test.",
            rank: .champion,
            health: 140, reactionTime: 0.24, telegraphScale: 0.80, restMin: 0.8, restMax: 1.5,
            blockChance: 0.45, dodgeChance: 0.30, counterChance: 0.40,
            damageScale: 1.15, poise: 72, openingChance: 0.2, whiffOpening: 0.55, blockDuration: 0.8,
            patterns: [
                AttackPattern("Feint, jab, cross, hook", [.feint(.jab), .attack(.jab), .attack(.cross), .attack(.leftHook)]),
                AttackPattern("Jab, guard, cross, upper", [.attack(.jab), .guardUp(0.4), .attack(.cross), .attack(.uppercut)]),
                AttackPattern("Feint, cross, hook", [.feint(.cross), .attack(.cross), .attack(.rightHook)]),
                AttackPattern("Five-piece", [.attack(.jab), .attack(.jab), .attack(.cross), .attack(.rightHook), .attack(.uppercut)])
            ],
            rewardScale: 2.0,
            skinHex: "E0AC69", hairHex: "0B0B0B", trunksHex: "F2C94C", gloveHex: "111111")
    ]
}
