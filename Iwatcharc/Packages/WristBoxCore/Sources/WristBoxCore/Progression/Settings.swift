import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var soundEnabled: Bool
    public var hapticsEnabled: Bool
    /// The Watch plays an instant tick as soon as it detects a punch.
    public var localWatchHaptics: Bool
    /// Shows the Debug screen and latency overlay entry points.
    public var developerMode: Bool
    /// Developer Controller Mode: on-screen buttons stand in for the Watch.
    public var simulatedController: Bool
    public var showLatency: Bool
    public var gestureConfig: GestureConfig

    public init(soundEnabled: Bool = true,
                hapticsEnabled: Bool = true,
                localWatchHaptics: Bool = true,
                developerMode: Bool = false,
                simulatedController: Bool = false,
                showLatency: Bool = false,
                gestureConfig: GestureConfig = .default) {
        self.soundEnabled = soundEnabled
        self.hapticsEnabled = hapticsEnabled
        self.localWatchHaptics = localWatchHaptics
        self.developerMode = developerMode
        self.simulatedController = simulatedController
        self.showLatency = showLatency
        self.gestureConfig = gestureConfig
    }

    private enum CodingKeys: String, CodingKey {
        case soundEnabled, hapticsEnabled, localWatchHaptics, developerMode
        case simulatedController, showLatency, gestureConfig
    }

    /// Tolerant decoding: missing or unreadable keys fall back to defaults so an
    /// app update never wipes the player's settings.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        soundEnabled = (try? c.decode(Bool.self, forKey: .soundEnabled)) ?? true
        hapticsEnabled = (try? c.decode(Bool.self, forKey: .hapticsEnabled)) ?? true
        localWatchHaptics = (try? c.decode(Bool.self, forKey: .localWatchHaptics)) ?? true
        developerMode = (try? c.decode(Bool.self, forKey: .developerMode)) ?? false
        simulatedController = (try? c.decode(Bool.self, forKey: .simulatedController)) ?? false
        showLatency = (try? c.decode(Bool.self, forKey: .showLatency)) ?? false
        gestureConfig = (try? c.decode(GestureConfig.self, forKey: .gestureConfig)) ?? .default
    }
}
