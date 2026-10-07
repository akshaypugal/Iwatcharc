import WatchKit
import WristBoxCore

/// Haptic patterns for the Watch. The iPhone decides *what* happened and sends
/// a `HapticCue`; the Watch decides how it feels on the wrist.
enum WatchHaptics {
    /// Instant feedback the moment a punch is detected (no round trip).
    static func tick() {
        WKInterfaceDevice.current().play(.click)
    }

    static func play(_ cue: HapticCue) {
        for (type, delay) in pattern(for: cue) {
            if delay <= 0 {
                WKInterfaceDevice.current().play(type)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    WKInterfaceDevice.current().play(type)
                }
            }
        }
    }

    private static func pattern(for cue: HapticCue) -> [(WKHapticType, Double)] {
        switch cue {
        case .punchLanded:
            return [(.click, 0)]
        case .perfectPunch:
            return [(.success, 0), (.click, 0.20)]
        case .opponentHit:
            return [(.failure, 0)]
        case .blocked:
            return [(.click, 0), (.click, 0.09)]
        case .dodged:
            return [(.directionUp, 0)]
        case .counter:
            return [(.success, 0), (.directionUp, 0.22), (.click, 0.42)]
        case .combo:
            return [(.click, 0), (.click, 0.09), (.click, 0.18)]
        case .ko:
            return [(.stop, 0), (.failure, 0.35), (.success, 0.75)]
        case .knockdown:
            return [(.directionDown, 0), (.failure, 0.28)]
        case .roundStart:
            return [(.start, 0)]
        case .roundEnd:
            return [(.stop, 0)]
        case .specialReady:
            return [(.notification, 0), (.notification, 0.28)]
        case .special:
            return [(.success, 0), (.click, 0.16), (.click, 0.32), (.click, 0.48), (.success, 0.7)]
        case .victory:
            return [(.success, 0), (.success, 0.45)]
        case .defeat:
            return [(.failure, 0)]
        }
    }
}
