import Foundation

/// How the opponent's guard handled a player punch.
public enum DefenseOutcome: Equatable, Sendable {
    case takesHit
    case blocked
    case dodged
}

/// How an opponent attack ended up (decided by the fight engine).
public enum AttackResult: Equatable, Sendable {
    case hit
    case blocked
    case dodged
    case ignored
}

public struct ActiveAttack: Equatable, Sendable {
    public var kind: AttackKind
    /// Total wind-up time.
    public var telegraph: Double
    public var elapsed: Double
    public var isFeint: Bool

    public var progress: Double { telegraph > 0 ? min(1, elapsed / telegraph) : 1 }
}

public enum AIEvent: Equatable, Sendable {
    case telegraphStarted(AttackKind, duration: Double, feint: Bool)
    case feintCancelled(AttackKind)
    /// The attack lands now. The engine must answer with `attackResolved`.
    case impact(AttackKind)
    case stateChanged(OpponentState)
}

/// Believable opponent: a scripted-pattern state machine with probabilistic
/// reactions. States: idle, watch, attack, block, dodge, stunned, vulnerable,
/// knockedDown.
///
/// The AI never touches player health; it only asks the engine to resolve
/// attacks and tells it how it defended punches.
public final class OpponentAI {
    public let profile: OpponentProfile

    private enum ReactionKind { case block, dodge }
    private struct Reaction { var kind: ReactionKind; var remaining: Double }
    private struct Pending { var kind: ReactionKind; var delay: Double }

    /// Seconds after an opening starts during which a punch counts as PERFECT.
    public static let perfectWindow = 0.30

    private var rng: SeededRNG
    private var mainState: OpponentState = .idle
    private var reaction: Reaction?
    private var pending: Pending?
    private var queue: [PatternStep] = []
    private var timer = 0.0
    private var recovering = false
    private var counterIntent = false
    private var poiseLeft: Double

    public private(set) var currentAttack: ActiveAttack?
    public private(set) var patternName: String?
    /// Time since the current opening began.
    public private(set) var openingElapsed = 0.0
    /// Seconds spent in the current visible state.
    public private(set) var stateElapsed = 0.0

    public init(profile: OpponentProfile, seed: UInt64 = 7) {
        self.profile = profile
        rng = SeededRNG(seed: seed)
        poiseLeft = profile.poise
        reset()
    }

    /// Visible state (a block/dodge reaction overlays the scripted state).
    public var state: OpponentState {
        if let r = reaction { return r.kind == .block ? .block : .dodge }
        return mainState
    }

    /// Opponent is dropping their guard right now - punches are extra effective.
    public var isExposed: Bool { mainState == .vulnerable || mainState == .stunned }

    /// Within the first moments of an opening: a punch now is PERFECT.
    public var perfectWindowOpen: Bool {
        mainState == .vulnerable && reaction == nil && openingElapsed <= Self.perfectWindow
    }

    /// Wind-up in progress (before the hit lands).
    public var isTelegraphing: Bool { mainState == .attack && currentAttack != nil && !recovering }

    public func reset() {
        mainState = .idle
        reaction = nil
        pending = nil
        queue = []
        currentAttack = nil
        patternName = nil
        recovering = false
        counterIntent = false
        poiseLeft = profile.poise
        openingElapsed = 0
        stateElapsed = 0
        timer = rng.range(0.9, 1.4)
    }

    // MARK: Update

    public func update(_ dt: Double) -> [AIEvent] {
        var out: [AIEvent] = []
        let before = state
        stateElapsed += dt

        if var p = pending {
            p.delay -= dt
            if p.delay <= 0 {
                pending = nil
                startReaction(p.kind)
            } else {
                pending = p
            }
        }

        if var r = reaction {
            r.remaining -= dt
            if r.remaining <= 0 {
                reaction = nil
                if counterIntent {
                    counterIntent = false
                    queue.insert(.quickAttack(randomCounterKind()), at: 0)
                    patternName = patternName ?? "Counter"
                    if mainState == .idle || mainState == .watch || mainState == .block { timer = 0 }
                }
            } else {
                reaction = r
            }
            // Scripted timers are paused while reacting.
        } else {
            tickMain(dt, &out)
        }

        if state != before {
            stateElapsed = 0
            out.append(.stateChanged(state))
        }
        return out
    }

    private func tickMain(_ dt: Double, _ out: inout [AIEvent]) {
        switch mainState {
        case .idle, .watch, .block:
            timer -= dt
            if timer <= 0 { advance(&out) }

        case .attack:
            guard var a = currentAttack else {
                mainState = .idle
                timer = 0.3
                return
            }
            if recovering {
                timer -= dt
                if timer <= 0 {
                    recovering = false
                    currentAttack = nil
                    advance(&out)
                }
                return
            }
            a.elapsed += dt
            if a.isFeint, a.elapsed >= a.telegraph * 0.55 {
                currentAttack = nil
                out.append(.feintCancelled(a.kind))
                advance(&out)
                return
            }
            if a.elapsed >= a.telegraph {
                a.elapsed = a.telegraph
                currentAttack = a
                recovering = true
                timer = 0.25
                out.append(.impact(a.kind))
            } else {
                currentAttack = a
            }

        case .stunned:
            timer -= dt
            if timer <= 0 {
                mainState = .vulnerable
                timer = 0.5
                openingElapsed = 0.2   // already past most of the perfect window
            }

        case .vulnerable:
            timer -= dt
            openingElapsed += dt
            if timer <= 0 {
                mainState = .idle
                timer = rng.range(0.4, 0.8)
            }

        case .dodge, .knockedDown:
            break
        }
    }

    // MARK: Pattern scripting

    private func advance(_ out: inout [AIEvent]) {
        if queue.isEmpty {
            if patternName != nil {
                finishPattern()
            } else {
                pickPattern()
                if queue.isEmpty { mainState = .idle; timer = 1; return }
                advance(&out)
            }
            return
        }
        let step = queue.removeFirst()
        switch step {
        case .wait(let t):
            mainState = .watch
            timer = t
        case .guardUp(let t):
            mainState = .block
            timer = t
        case .attack(let k):
            beginAttack(k, scale: 1, feint: false, &out)
        case .quickAttack(let k):
            beginAttack(k, scale: 0.6, feint: false, &out)
        case .feint(let k):
            beginAttack(k, scale: 1, feint: true, &out)
        }
    }

    private func beginAttack(_ kind: AttackKind, scale: Double, feint: Bool, _ out: inout [AIEvent]) {
        let t = kind.baseTelegraph * profile.telegraphScale * scale
        mainState = .attack
        recovering = false
        currentAttack = ActiveAttack(kind: kind, telegraph: t, elapsed: 0, isFeint: feint)
        out.append(.telegraphStarted(kind, duration: t, feint: feint))
    }

    private func pickPattern() {
        let total = profile.patterns.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return }
        var roll = rng.range(0, total)
        var chosen = profile.patterns[0]
        for p in profile.patterns {
            roll -= p.weight
            if roll <= 0 {
                chosen = p
                break
            }
        }
        patternName = chosen.name
        queue = chosen.steps
    }

    private func finishPattern() {
        patternName = nil
        if rng.chance(profile.openingChance) {
            mainState = .vulnerable
            timer = rng.range(0.8, 1.2)
            openingElapsed = 0
        } else {
            mainState = .idle
            timer = rng.range(profile.restMin, profile.restMax)
        }
    }

    private func randomCounterKind() -> AttackKind {
        let options: [AttackKind] = [.jab, .cross, .leftHook, .rightHook]
        return options[Int(rng.next() % UInt64(options.count))]
    }

    // MARK: Engine interface

    /// Called by the engine on every player punch, *before* damage is applied.
    public func incomingPlayerPunch() -> DefenseOutcome {
        switch state {
        case .block:
            if rng.chance(profile.counterChance) { counterIntent = true }
            return .blocked
        case .dodge:
            if rng.chance(profile.counterChance) { counterIntent = true }
            return .dodged
        case .knockedDown:
            return .takesHit
        default:
            scheduleReaction()
            return .takesHit
        }
    }

    private func scheduleReaction() {
        guard pending == nil, reaction == nil, mainState == .idle || mainState == .watch else { return }
        if rng.chance(profile.blockChance) {
            pending = Pending(kind: .block, delay: profile.reactionTime)
        } else if rng.chance(profile.dodgeChance) {
            pending = Pending(kind: .dodge, delay: profile.reactionTime)
        }
    }

    private func startReaction(_ kind: ReactionKind) {
        guard mainState == .idle || mainState == .watch else { return }
        reaction = Reaction(kind: kind, remaining: kind == .block ? profile.blockDuration : 0.45)
    }

    /// The engine tells the AI how its attack ended.
    public func attackResolved(_ result: AttackResult) {
        guard result == .dodged else { return }
        // Whiffed: wide open.
        mainState = .vulnerable
        timer = profile.whiffOpening
        openingElapsed = 0
        currentAttack = nil
        recovering = false
        queue.removeAll()
        patternName = nil
    }

    /// Absorb damage; returns true when the opponent is stunned by it.
    public func absorb(damage: Double) -> Bool {
        guard mainState != .stunned, mainState != .knockedDown else { return false }
        poiseLeft -= damage
        if poiseLeft <= 0 {
            poiseLeft = profile.poise
            stun(duration: 0.9)
            return true
        }
        return false
    }

    public func stun(duration: Double) {
        mainState = .stunned
        timer = duration
        reaction = nil
        pending = nil
        currentAttack = nil
        recovering = false
        queue.removeAll()
        patternName = nil
        counterIntent = false
    }

    /// A heavy hit during wind-up cancels the attack. Returns true if it did.
    @discardableResult
    public func interruptAttack() -> Bool {
        guard mainState == .attack, !recovering else { return false }
        mainState = .vulnerable
        timer = 0.6
        openingElapsed = 0
        currentAttack = nil
        queue.removeAll()
        patternName = nil
        return true
    }

    public func knockDown() {
        mainState = .knockedDown
        reaction = nil
        pending = nil
        currentAttack = nil
        recovering = false
        queue.removeAll()
        patternName = nil
        counterIntent = false
    }

    /// Back on their feet after a knockdown.
    public func getUp() {
        mainState = .vulnerable
        timer = 0.8
        openingElapsed = 0.2
        poiseLeft = profile.poise
    }
}
