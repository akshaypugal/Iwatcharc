import UIKit
import WristBoxCore

/// Haptics on the iPhone. The Watch plays its own patterns (see WatchHaptics);
/// this keeps the phone in your pocket or on a stand feeling alive too.
final class HapticsService {
    var enabled = true

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()

    func prepare() {
        light.prepare()
        medium.prepare()
        heavy.prepare()
        notification.prepare()
    }

    func play(_ cue: HapticCue) {
        guard enabled else { return }
        switch cue {
        case .punchLanded:
            medium.impactOccurred()
        case .perfectPunch:
            heavy.impactOccurred()
        case .counter, .special:
            notification.notificationOccurred(.success)
        case .opponentHit:
            heavy.impactOccurred()
        case .blocked, .dodged:
            light.impactOccurred()
        case .combo:
            medium.impactOccurred(intensity: 0.8)
        case .ko, .knockdown:
            notification.notificationOccurred(.warning)
        case .roundStart, .roundEnd:
            medium.impactOccurred()
        case .specialReady:
            notification.notificationOccurred(.success)
        case .victory:
            notification.notificationOccurred(.success)
        case .defeat:
            notification.notificationOccurred(.error)
        }
    }
}
