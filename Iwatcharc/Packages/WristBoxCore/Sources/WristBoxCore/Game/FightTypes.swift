import Foundation

public enum Fighter: String, Equatable, Sendable {
    case player, opponent

    public var other: Fighter { self == .player ? .opponent : .player }
}

public enum FightPhase: Equatable, Sendable {
    case notStarted
    case countdown(remaining: Double)
    case fighting
    case knockdown(Fighter, remaining: Double)
    case roundEnd(remaining: Double)
    case fightOver
}

public enum RoundMethod: String, Equatable, Sendable {
    case ko, timer
}

public struct RoundSummary: Equatable, Sendable {
    public var round: Int
    /// nil = draw.
    public var winner: Fighter?
    public var method: RoundMethod
    public var playerHealthPercent: Double
    public var opponentHealthPercent: Double

    public init(round: Int, winner: Fighter?, method: RoundMethod, playerHealthPercent: Double, opponentHealthPercent: Double) {
        self.round = round
        self.winner = winner
        self.method = method
        self.playerHealthPercent = playerHealthPercent
        self.opponentHealthPercent = opponentHealthPercent
    }
}

public enum FightMethod: String, Equatable, Sendable {
    case ko, decision
}

public struct FightOutcome: Equatable, Sendable {
    public var winner: Fighter
    public var method: FightMethod
    public var playerRoundsWon: Int
    public var opponentRoundsWon: Int
    public var rounds: [RoundSummary]
    public var stats: FightStats
    public var duration: Double
    public var opponentID: Int

    public var playerWon: Bool { winner == .player }

    public init(winner: Fighter, method: FightMethod, playerRoundsWon: Int, opponentRoundsWon: Int,
                rounds: [RoundSummary], stats: FightStats, duration: Double, opponentID: Int) {
        self.winner = winner
        self.method = method
        self.playerRoundsWon = playerRoundsWon
        self.opponentRoundsWon = opponentRoundsWon
        self.rounds = rounds
        self.stats = stats
        self.duration = duration
        self.opponentID = opponentID
    }
}

public enum PunchOutcome: Equatable, Sendable {
    /// Connected for full effect.
    case hit
    /// Opponent's guard absorbed most of it.
    case blocked
    /// Opponent slipped it.
    case dodged
    /// Too sloppy (direction accuracy) to connect.
    case missed
}

/// Everything the UI, sound and haptics need to react to. The engine is the
/// only producer; the app just drains them every frame.
public enum FightEvent: Equatable, Sendable {
    case countdown(Int)
    case roundStarted(Int)
    case roundEnded(RoundSummary)
    case playerPunch(PunchEvent)
    case combo(count: Int, name: String?)
    case comboBroken(count: Int)
    case perfectPunch
    case counter(perfect: Bool)
    case interrupted
    case opponentTelegraph(AttackKind, duration: Double, feint: Bool)
    case feintCancelled(AttackKind)
    case opponentAttack(AttackKind, result: AttackResult, damage: Double)
    case playerDodge(Side, success: Bool, perfect: Bool)
    case playerBlock(Bool)
    case opponentStateChanged(OpponentState)
    case staminaLow
    case specialReady
    case specialStarted
    case specialHit(index: Int, total: Int, damage: Double)
    case specialEnded
    case knockdown(Fighter, number: Int)
    case knockdownCount(Int)
    case getUp(Fighter)
    case ko(winner: Fighter)
    case fightEnded(FightOutcome)
}

/// Detail of one player punch.
public struct PunchEvent: Equatable, Sendable {
    public var type: PunchType
    public var outcome: PunchOutcome
    public var damage: Double
    public var power: Double
    public var accuracy: Double
    public var perfect: Bool
    public var counter: Bool
    public var critical: Bool
    public var combo: Int
}

public struct FightConfig: Sendable {
    public var rounds = 3
    public var roundDuration = 60.0
    public var firstCountdown = 3.0
    public var betweenRoundCountdown = 2.0
    public var roundBreak = 3.0
    public var koBreak = 3.5
    public var knockdownCount = 3.0
    /// Knockdowns in one round that end it as a KO.
    public var knockdownsForKO = 2
    /// Health restored after getting up (fraction of max).
    public var getUpHealth = 0.30
    /// Health restored between rounds (fraction of max).
    public var roundRecovery = 0.30

    public var playerMaxHealth = 100.0
    public var baseStamina = 100.0

    public var comboWindow = 1.25
    /// A dodge counts for an attack if it happened up to this long before impact.
    public var dodgeWindow = 0.50
    public var perfectDodgeWindow = 0.18
    /// After a successful dodge, a punch within this window is a COUNTER.
    public var counterWindow = 1.10
    /// Accuracy below this and the punch whiffs.
    public var missAccuracy = 0.25
    public var blockReduction = 0.65
    /// Damage the guard still lets through against a blocking opponent.
    public var opponentBlockReduction = 0.78

    // Stamina
    public var staminaRegenPerSecond = 16.0
    public var staminaRegenDelay = 0.45
    public var blockRegenBonus = 1.6
    public var lowStamina = 0.25

    // Special
    public var specialDuration = 2.4
    public var specialHits = 6
    public var specialBaseDamage = 36.0

    /// Global tuning knob for damage the opponent deals.
    public var damageScale = 1.0
    /// Global tuning knob for damage the player deals to the opponent.
    public var offenseScale = 0.18

    public init() {}
}

/// Read-only view of the fight for rendering.
public struct FightSnapshot: Equatable, Sendable {
    public var phase: FightPhase
    public var round: Int
    public var totalRounds: Int
    public var timeRemaining: Double
    public var playerHealth: Double
    public var playerMaxHealth: Double
    public var opponentHealth: Double
    public var opponentMaxHealth: Double
    public var stamina: Double
    public var staminaMax: Double
    public var special: Double
    public var specialReady: Bool
    public var specialActive: Bool
    public var combo: Int
    public var comboName: String?
    public var playerBlocking: Bool
    public var opponentState: OpponentState
    public var attack: ActiveAttack?
    public var perfectWindowOpen: Bool
    public var counterWindowOpen: Bool
    public var playerRoundWins: Int
    public var opponentRoundWins: Int
}
