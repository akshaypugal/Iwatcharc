import Foundation

/// Named punch sequences that earn a bonus.
public enum ComboLibrary {
    public struct Entry: Equatable, Sendable {
        public var name: String
        public var pattern: [PunchType]
        public var bonus: Double
    }

    public static let entries: [Entry] = [
        Entry(name: "ONE-TWO", pattern: [.jab, .cross], bonus: 0.10),
        Entry(name: "DOUBLE JAB, CROSS", pattern: [.jab, .jab, .cross], bonus: 0.12),
        Entry(name: "ONE-TWO-HOOK", pattern: [.jab, .cross, .leftHook], bonus: 0.18),
        Entry(name: "ONE-TWO-HOOK", pattern: [.jab, .cross, .rightHook], bonus: 0.18),
        Entry(name: "THE FULL COMBO", pattern: [.jab, .cross, .leftHook, .rightHook], bonus: 0.25),
        Entry(name: "HOOK-UPPERCUT", pattern: [.leftHook, .uppercut], bonus: 0.15),
        Entry(name: "JAB-UPPERCUT", pattern: [.jab, .uppercut], bonus: 0.10)
    ]

    /// Longest named combo that the chain currently ends with.
    public static func match(_ chain: [PunchType]) -> Entry? {
        var best: Entry?
        for e in entries where chain.count >= e.pattern.count {
            if Array(chain.suffix(e.pattern.count)) == e.pattern {
                if best == nil || e.pattern.count > best!.pattern.count { best = e }
            }
        }
        return best
    }
}

/// The boxing game. Consumes high-level `GestureEvent`s, advances with
/// `update(_:)`, and reports what happened as `FightEvent`s.
///
/// Nothing in here knows about CoreMotion, WatchConnectivity or SwiftUI, and
/// time only moves when `update` is called, so fights are fully deterministic
/// and testable with simulated input.
public final class FightEngine {
    public let opponent: OpponentProfile
    public let upgrades: PlayerUpgrades
    public var config: FightConfig
    public let ai: OpponentAI

    // MARK: Observable state
    public private(set) var phase: FightPhase = .notStarted
    public private(set) var time = 0.0
    public private(set) var round = 1
    public private(set) var roundTimeLeft: Double
    public private(set) var playerHealth: Double
    public private(set) var opponentHealth: Double
    public let playerMaxHealth: Double
    public let opponentMaxHealth: Double
    public private(set) var stamina: Double
    public let staminaMax: Double
    public private(set) var special = 0.0
    public private(set) var combo = 0
    public private(set) var comboChain: [PunchType] = []
    public private(set) var comboName: String?
    public private(set) var playerBlocking = false
    public private(set) var stats = FightStats()
    public private(set) var roundResults: [RoundSummary] = []
    public private(set) var playerRoundWins = 0
    public private(set) var opponentRoundWins = 0
    public private(set) var outcome: FightOutcome?
    public var isPaused = false

    // MARK: Private state
    private struct SpecialSequence {
        var elapsed = 0.0
        var hitsDone = 0
    }

    private var rng: SeededRNG
    private var events: [FightEvent] = []
    private var fightTime = 0.0
    private var lastLandTime = -100.0
    private var lastStaminaSpend = -100.0
    private var lastDodge: (side: Side, time: Double)?
    private var counterUntil = -1.0
    private var counterPerfect = false
    private var specialSeq: SpecialSequence?
    private var knockdowns: [Fighter: Int] = [:]
    private var countdownTick = 0
    private var knockdownTick = 0
    private var staminaLowNotified = false
    private var lastOpponentState: OpponentState = .idle
    private var roundDamageDealt = 0.0
    private var roundDamageTaken = 0.0

    public init(opponent: OpponentProfile,
                upgrades: PlayerUpgrades = PlayerUpgrades(),
                config: FightConfig = FightConfig(),
                seed: UInt64 = 42) {
        self.opponent = opponent
        self.upgrades = upgrades
        self.config = config
        rng = SeededRNG(seed: seed)
        ai = OpponentAI(profile: opponent, seed: seed &+ 1)
        playerMaxHealth = config.playerMaxHealth
        opponentMaxHealth = opponent.health
        playerHealth = config.playerMaxHealth
        opponentHealth = opponent.health
        staminaMax = max(1, config.baseStamina * upgrades.staminaMax / 100)
        stamina = max(1, config.baseStamina * upgrades.staminaMax / 100)
        roundTimeLeft = config.roundDuration
        lastOpponentState = ai.state
    }

    // MARK: - Public API

    public var specialReady: Bool { special >= 100 }
    public var specialActive: Bool { specialSeq != nil }
    public var isOver: Bool { phase == .fightOver }
    public var winsNeeded: Int { config.rounds / 2 + 1 }

    /// Begin the fight with the pre-round countdown.
    public func start() {
        guard phase == .notStarted else { return }
        phase = .countdown(remaining: config.firstCountdown)
        countdownTick = Int(config.firstCountdown.rounded(.up))
        events.append(.countdown(countdownTick))
    }

    /// Returns and clears the events produced since the last call.
    public func drainEvents() -> [FightEvent] {
        let e = events
        events.removeAll(keepingCapacity: true)
        return e
    }

    /// The Watch (or the simulator) lost its link: drop held inputs.
    public func controllerDisconnected() {
        if playerBlocking {
            playerBlocking = false
            events.append(.playerBlock(false))
        }
        lastDodge = nil
    }

    /// Feed one high-level gesture into the game.
    public func handle(_ event: GestureEvent) {
        switch event {
        case .jab(let r), .cross(let r), .leftHook(let r), .rightHook(let r), .uppercut(let r):
            handlePunch(r)
        case .power(let r):
            if specialReady, phase == .fighting {
                activateSpecial()
            } else {
                handlePunch(r)
            }
        case .dodgeLeft:
            handleDodge(.left)
        case .dodgeRight:
            handleDodge(.right)
        case .blockStart:
            setBlocking(true)
        case .blockEnd:
            setBlocking(false)
        case .guardBreak:
            if specialReady, phase == .fighting { activateSpecial() }
        }
        syncOpponentState()
    }

    /// Advance the game clock.
    public func update(_ rawDt: Double) {
        guard !isPaused, rawDt > 0 else { return }
        let dt = min(rawDt, 0.1)
        time += dt
        switch phase {
        case .notStarted, .fightOver:
            break
        case .countdown(let remaining):
            let r = remaining - dt
            let tick = Int(max(r, 0).rounded(.up))
            if r > 0 {
                phase = .countdown(remaining: r)
                if tick != countdownTick, tick >= 1 {
                    countdownTick = tick
                    events.append(.countdown(tick))
                }
            } else {
                beginRound()
            }
        case .fighting:
            updateFighting(dt)
        case .knockdown(let who, let remaining):
            updateKnockdown(who, remaining - dt)
        case .roundEnd(let remaining):
            let r = remaining - dt
            if r > 0 {
                phase = .roundEnd(remaining: r)
            } else if isFightDecided {
                finishFight()
            } else {
                nextRound()
            }
        }
        syncOpponentState()
    }

    public var snapshot: FightSnapshot {
        FightSnapshot(phase: phase,
                      round: round,
                      totalRounds: config.rounds,
                      timeRemaining: roundTimeLeft,
                      playerHealth: playerHealth,
                      playerMaxHealth: playerMaxHealth,
                      opponentHealth: opponentHealth,
                      opponentMaxHealth: opponentMaxHealth,
                      stamina: stamina,
                      staminaMax: staminaMax,
                      special: special,
                      specialReady: specialReady,
                      specialActive: specialActive,
                      combo: combo,
                      comboName: comboName,
                      playerBlocking: playerBlocking,
                      opponentState: ai.state,
                      attack: ai.currentAttack,
                      perfectWindowOpen: ai.perfectWindowOpen,
                      counterWindowOpen: time <= counterUntil,
                      playerRoundWins: playerRoundWins,
                      opponentRoundWins: opponentRoundWins)
    }

    /// Compact state for the Watch UI.
    public var watchSummary: GameStateSummary {
        let p: WatchPhase
        switch phase {
        case .notStarted: p = .idle
        case .countdown: p = .countdown
        case .fighting: p = .fighting
        case .knockdown: p = .knockdown
        case .roundEnd: p = .roundEnd
        case .fightOver: p = .fightOver
        }
        return GameStateSummary(phase: p, round: round, totalRounds: config.rounds,
                                remaining: roundTimeLeft, combo: combo, specialReady: specialReady)
    }

    // MARK: - Round flow

    private func beginRound() {
        phase = .fighting
        roundTimeLeft = config.roundDuration
        ai.reset()
        lastOpponentState = ai.state
        events.append(.roundStarted(round))
    }

    private func updateFighting(_ dt: Double) {
        fightTime += dt
        roundTimeLeft = max(0, roundTimeLeft - dt)
        updateStamina(dt)
        updateComboTimeout()
        if specialSeq != nil { updateSpecial(dt) }
        guard phase == .fighting else { return }

        for e in ai.update(dt) {
            switch e {
            case .telegraphStarted(let kind, let duration, let feint):
                events.append(.opponentTelegraph(kind, duration: duration, feint: feint))
            case .feintCancelled(let kind):
                events.append(.feintCancelled(kind))
            case .impact(let kind):
                resolveOpponentAttack(kind)
            case .stateChanged:
                break   // reported by syncOpponentState()
            }
            if phase != .fighting { return }
        }

        if roundTimeLeft <= 0 { endRoundByTimer() }
    }

    private func updateKnockdown(_ who: Fighter, _ remaining: Double) {
        if remaining > 0 {
            phase = .knockdown(who, remaining: remaining)
            let tick = Int(remaining.rounded(.up))
            if tick != knockdownTick {
                knockdownTick = tick
                events.append(.knockdownCount(tick))
            }
            return
        }
        if who == .player {
            playerHealth = playerMaxHealth * config.getUpHealth
        } else {
            opponentHealth = opponentMaxHealth * config.getUpHealth
            ai.getUp()
        }
        phase = .fighting
        events.append(.getUp(who))
    }

    private func endRoundByTimer() {
        let p = playerHealth / playerMaxHealth
        let o = opponentHealth / opponentMaxHealth
        var winner: Fighter?
        if abs(p - o) > 0.01 {
            winner = p > o ? .player : .opponent
        } else if abs(roundDamageDealt - roundDamageTaken) > 0.5 {
            winner = roundDamageDealt > roundDamageTaken ? .player : .opponent
        }
        endRound(winner: winner, method: .timer)
    }

    private func endRound(winner: Fighter?, method: RoundMethod) {
        specialSeq = nil
        let summary = RoundSummary(round: round,
                                   winner: winner,
                                   method: method,
                                   playerHealthPercent: max(0, playerHealth / playerMaxHealth),
                                   opponentHealthPercent: max(0, opponentHealth / opponentMaxHealth))
        roundResults.append(summary)
        if winner == .player { playerRoundWins += 1 }
        if winner == .opponent { opponentRoundWins += 1 }
        breakCombo()
        events.append(.roundEnded(summary))
        if method == .ko, let w = winner { events.append(.ko(winner: w)) }
        phase = .roundEnd(remaining: method == .ko ? config.koBreak : config.roundBreak)
    }

    private var isFightDecided: Bool {
        playerRoundWins >= winsNeeded || opponentRoundWins >= winsNeeded || round >= config.rounds
    }

    private func finishFight() {
        let winner: Fighter
        if playerRoundWins != opponentRoundWins {
            winner = playerRoundWins > opponentRoundWins ? .player : .opponent
        } else {
            winner = stats.damageDealt >= stats.damageTaken ? .player : .opponent
        }
        let wonByKO = roundResults.last.map { $0.method == .ko && $0.winner == winner } ?? false
        let result = FightOutcome(winner: winner,
                                  method: wonByKO ? .ko : .decision,
                                  playerRoundsWon: playerRoundWins,
                                  opponentRoundsWon: opponentRoundWins,
                                  rounds: roundResults,
                                  stats: stats,
                                  duration: fightTime,
                                  opponentID: opponent.id)
        outcome = result
        phase = .fightOver
        events.append(.fightEnded(result))
    }

    private func nextRound() {
        round += 1
        playerHealth = min(playerMaxHealth, playerHealth + playerMaxHealth * config.roundRecovery)
        opponentHealth = min(opponentMaxHealth, opponentHealth + opponentMaxHealth * config.roundRecovery)
        stamina = staminaMax
        knockdowns.removeAll()
        roundDamageDealt = 0
        roundDamageTaken = 0
        counterUntil = -1
        lastDodge = nil
        ai.reset()
        lastOpponentState = ai.state
        phase = .countdown(remaining: config.betweenRoundCountdown)
        countdownTick = Int(config.betweenRoundCountdown.rounded(.up))
        events.append(.countdown(countdownTick))
    }

    // MARK: - Stamina

    private func staminaCost(_ type: PunchType) -> Double {
        let base: Double
        switch type {
        case .jab: base = 6
        case .cross: base = 9
        case .leftHook, .rightHook: base = 10
        case .uppercut: base = 11
        case .power: base = 16
        }
        return base * upgrades.staminaCostMultiplier
    }

    private var staminaFraction: Double { stamina / staminaMax }

    /// Weaker punches when winded.
    private var staminaPowerFactor: Double {
        let f = staminaFraction
        return f >= 0.4 ? 1 : 0.5 + 0.5 * (f / 0.4)
    }

    /// Gassed fighters also lose real damage, so shaking the wrist nonstop does not pay.
    private var staminaDamageFactor: Double {
        let f = staminaFraction
        return f >= 0.4 ? 1 : 0.3 + 0.7 * (f / 0.4)
    }

    private func spendStamina(_ amount: Double) {
        stamina = max(0, stamina - amount)
        lastStaminaSpend = time
    }

    private func updateStamina(_ dt: Double) {
        let low = staminaFraction < config.lowStamina
        let delay = config.staminaRegenDelay * (low ? 2 : 1)
        if time - lastStaminaSpend > delay {
            var rate = config.staminaRegenPerSecond * upgrades.staminaRegenMultiplier
            if playerBlocking { rate *= config.blockRegenBonus }
            if low { rate *= 0.7 }
            stamina = min(staminaMax, stamina + rate * dt)
        }
        if low, !staminaLowNotified {
            staminaLowNotified = true
            events.append(.staminaLow)
        } else if staminaFraction > 0.4 {
            staminaLowNotified = false
        }
    }

    // MARK: - Player input

    private func setBlocking(_ on: Bool) {
        guard playerBlocking != on else { return }
        playerBlocking = on
        events.append(.playerBlock(on))
    }

    private func handleDodge(_ side: Side) {
        guard phase == .fighting, specialSeq == nil else { return }
        spendStamina(6 * upgrades.staminaCostMultiplier)
        lastDodge = (side, time)
        events.append(.playerDodge(side, success: false, perfect: false))
    }

    private func baseDamage(_ type: PunchType) -> Double {
        switch type {
        case .jab: return 4
        case .cross: return 7
        case .leftHook, .rightHook: return 8.5
        case .uppercut: return 10
        case .power: return 14
        }
    }

    private var comboWindow: Double { config.comboWindow * upgrades.comboWindowMultiplier }

    private func handlePunch(_ r: PunchResult) {
        guard phase == .fighting, specialSeq == nil else { return }
        stats.recordThrown(r.type)
        let power = clamp(r.power * staminaPowerFactor)
        let winded = staminaDamageFactor
        spendStamina(staminaCost(r.type))

        func report(_ outcome: PunchOutcome, damage: Double = 0, perfect: Bool = false,
                    counter: Bool = false, critical: Bool = false) {
            events.append(.playerPunch(PunchEvent(type: r.type, outcome: outcome, damage: damage,
                                                  power: power, accuracy: r.accuracy,
                                                  perfect: perfect, counter: counter,
                                                  critical: critical, combo: combo)))
        }

        // Sloppy direction: the punch whiffs.
        if r.accuracy < config.missAccuracy {
            breakCombo()
            report(.missed)
            return
        }

        let accuracyFactor = 0.6 + 0.4 * r.accuracy
        let raw = baseDamage(r.type) * (0.55 + 0.9 * power) * accuracyFactor
            * upgrades.damageMultiplier * config.offenseScale * winded

        switch ai.incomingPlayerPunch() {
        case .dodged:
            breakCombo()
            report(.dodged)
            return

        case .blocked:
            let dmg = raw * (1 - config.opponentBlockReduction)
            applyDamageToOpponent(dmg)
            addSpecial(0.5)
            report(.blocked, damage: dmg)
            checkOpponentKnockdown()
            return

        case .takesHit:
            break
        }

        // A clean hit.
        let withinWindow = time - lastLandTime <= comboWindow
        if !withinWindow || combo == 0 {
            combo = 0
            comboChain = []
        }
        combo += 1
        comboChain.append(r.type)
        if comboChain.count > 8 { comboChain.removeFirst(comboChain.count - 8) }
        lastLandTime = time
        let named = ComboLibrary.match(comboChain)
        comboName = named?.name ?? comboName

        let perfect = ai.perfectWindowOpen
        let counter = time <= counterUntil
        let counterWasPerfect = counterPerfect
        let critical = r.accuracy >= 0.88 && power >= 0.8 && rng.chance(0.5)

        var dmg = raw
        dmg *= min(2.0, 1 + 0.07 * Double(combo - 1))
        if let n = named { dmg *= 1 + n.bonus }
        if perfect { dmg *= 1.4 }
        if counter { dmg *= 1.6 }
        if ai.isExposed { dmg *= 1.25 }
        if critical { dmg *= 1.5 }

        applyDamageToOpponent(dmg)
        stats.recordLanded(r.type)
        stats.maxCombo = max(stats.maxCombo, combo)
        if combo == 3 { stats.combos += 1 }

        var gain = (1.5 + 2.0 * power) * winded
        if perfect { gain += 8; stats.perfectPunches += 1 }
        if counter {
            gain += 10
            stats.counters += 1
            counterUntil = -1
        }
        if combo >= 3 { gain += 1.0 }

        // Heavy hits interrupt a wind-up.
        var interrupted = false
        if ai.isTelegraphing, critical || perfect || counter {
            interrupted = ai.interruptAttack()
        }
        _ = ai.absorb(damage: dmg)

        report(.hit, damage: dmg, perfect: perfect, counter: counter, critical: critical)
        if perfect { events.append(.perfectPunch) }
        if counter { events.append(.counter(perfect: counterWasPerfect)) }
        if interrupted { events.append(.interrupted) }
        if combo >= 2 { events.append(.combo(count: combo, name: named?.name)) }
        addSpecial(gain)
        checkOpponentKnockdown()
    }

    private func applyDamageToOpponent(_ dmg: Double) {
        opponentHealth = max(0, opponentHealth - dmg)
        stats.damageDealt += dmg
        roundDamageDealt += dmg
    }

    private func addSpecial(_ amount: Double) {
        guard specialSeq == nil else { return }
        let wasReady = specialReady
        special = min(100, special + amount)
        if !wasReady, specialReady { events.append(.specialReady) }
    }

    private func updateComboTimeout() {
        if combo > 0, time - lastLandTime > comboWindow { breakCombo() }
    }

    private func breakCombo() {
        if combo >= 2 { events.append(.comboBroken(count: combo)) }
        combo = 0
        comboChain = []
        comboName = nil
    }

    // MARK: - Opponent attacks

    private func resolveOpponentAttack(_ kind: AttackKind) {
        if specialSeq != nil {
            ai.attackResolved(.ignored)
            return
        }
        let base = kind.baseDamage * opponent.damageScale * config.damageScale
        let reduced = base * (1 - upgrades.defenseReduction)

        // Dodge: right direction, recent enough.
        if let d = lastDodge, kind.dodgeSides.contains(d.side) {
            let age = time - d.time
            if age >= -0.05, age <= config.dodgeWindow {
                let perfect = age <= config.perfectDodgeWindow
                lastDodge = nil
                stats.dodges += 1
                counterUntil = time + config.counterWindow * upgrades.counterWindowMultiplier
                counterPerfect = perfect
                addSpecial(perfect ? 10 : 4)
                events.append(.playerDodge(d.side, success: true, perfect: perfect))
                events.append(.opponentAttack(kind, result: .dodged, damage: 0))
                ai.attackResolved(.dodged)
                return
            }
        }

        // Block.
        if playerBlocking, stamina > 0 {
            let reduction = min(0.9, config.blockReduction + upgrades.blockBonus)
            let dmg = reduced * (1 - reduction)
            spendStamina(kind.baseDamage * 1.2)
            damagePlayer(dmg)
            stats.blocks += 1
            addSpecial(2)
            events.append(.opponentAttack(kind, result: .blocked, damage: dmg))
            ai.attackResolved(.blocked)
            checkPlayerKnockdown()
            return
        }

        // Hit.
        damagePlayer(reduced)
        breakCombo()
        addSpecial(2)
        events.append(.opponentAttack(kind, result: .hit, damage: reduced))
        ai.attackResolved(.hit)
        checkPlayerKnockdown()
    }

    private func damagePlayer(_ dmg: Double) {
        playerHealth = max(0, playerHealth - dmg)
        stats.damageTaken += dmg
        roundDamageTaken += dmg
    }

    // MARK: - Special

    private func activateSpecial() {
        guard phase == .fighting, specialReady, specialSeq == nil else { return }
        special = 0
        specialSeq = SpecialSequence()
        ai.stun(duration: config.specialDuration + 0.8)
        events.append(.specialStarted)
    }

    private func updateSpecial(_ dt: Double) {
        guard var seq = specialSeq else { return }
        seq.elapsed += dt
        let n = config.specialHits
        let interval = config.specialDuration / Double(n)
        let weightSum = Double(n * (n + 1)) / 2
        let total = config.specialBaseDamage * upgrades.damageMultiplier * config.damageScale
        while seq.hitsDone < n, seq.elapsed >= interval * Double(seq.hitsDone + 1) {
            seq.hitsDone += 1
            let dmg = total * Double(seq.hitsDone) / weightSum
            applyDamageToOpponent(dmg)
            combo += 1
            lastLandTime = time
            stats.maxCombo = max(stats.maxCombo, combo)
            if combo == 3 { stats.combos += 1 }
            events.append(.specialHit(index: seq.hitsDone, total: n, damage: dmg))
            if opponentHealth <= 0 {
                specialSeq = nil
                events.append(.specialEnded)
                checkOpponentKnockdown()
                return
            }
        }
        if seq.hitsDone >= n {
            specialSeq = nil
            events.append(.specialEnded)
        } else {
            specialSeq = seq
        }
    }

    // MARK: - Knockdowns

    private func checkOpponentKnockdown() {
        guard phase == .fighting, opponentHealth <= 0 else { return }
        startKnockdown(.opponent)
    }

    private func checkPlayerKnockdown() {
        guard phase == .fighting, playerHealth <= 0 else { return }
        startKnockdown(.player)
    }

    private func startKnockdown(_ who: Fighter) {
        let n = (knockdowns[who] ?? 0) + 1
        knockdowns[who] = n
        if who == .opponent { stats.knockdowns += 1 }
        specialSeq = nil
        breakCombo()
        events.append(.knockdown(who, number: n))
        if who == .opponent { ai.knockDown() }
        if n >= config.knockdownsForKO {
            endRound(winner: who.other, method: .ko)
            return
        }
        phase = .knockdown(who, remaining: config.knockdownCount)
        knockdownTick = Int(config.knockdownCount.rounded(.up))
        events.append(.knockdownCount(knockdownTick))
    }

    // MARK: - Opponent state reporting

    private func syncOpponentState() {
        let s = ai.state
        if s != lastOpponentState {
            lastOpponentState = s
            events.append(.opponentStateChanged(s))
        }
    }
}
