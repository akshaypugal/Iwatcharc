import Foundation

public extension FightEvent {
    /// The Watch haptic that should accompany this event, if any.
    /// One cue per moment: a perfect counter plays the counter cue, not three.
    var hapticCue: HapticCue? {
        switch self {
        case .playerPunch(let p):
            guard p.outcome == .hit, !p.perfect, !p.counter else { return nil }
            return .punchLanded
        case .perfectPunch:
            return .perfectPunch
        case .counter:
            return .counter
        case .combo(let count, _):
            return [3, 5, 8, 12].contains(count) ? .combo : nil
        case .opponentAttack(_, let result, _):
            switch result {
            case .hit: return .opponentHit
            case .blocked: return .blocked
            case .dodged: return .dodged
            case .ignored: return nil
            }
        case .specialReady:
            return .specialReady
        case .specialStarted:
            return .special
        case .knockdown:
            return .knockdown
        case .ko:
            return .ko
        case .roundStarted:
            return .roundStart
        case .roundEnded:
            return .roundEnd
        case .fightEnded(let outcome):
            return outcome.playerWon ? .victory : .defeat
        default:
            return nil
        }
    }
}
