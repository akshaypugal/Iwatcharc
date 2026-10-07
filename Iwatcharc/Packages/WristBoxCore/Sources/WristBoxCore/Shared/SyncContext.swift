import Foundation

/// Settings the iPhone keeps in sync with the Watch through
/// `WCSession.updateApplicationContext`. The context is delivered even when the
/// Watch app is not running, and the last one is available after a restart, so
/// the Watch always boots with the latest calibration and thresholds.
public struct SyncContext: Equatable, Sendable {
    public var calibration: Calibration
    public var config: GestureConfig
    public var localHaptics: Bool

    public init(calibration: Calibration, config: GestureConfig, localHaptics: Bool) {
        self.calibration = calibration
        self.config = config
        self.localHaptics = localHaptics
    }

    public var dictionary: [String: Any] {
        [
            "k": "ctx",
            "cal": (try? JSONEncoder().encode(calibration)) ?? Data(),
            "cfg": (try? JSONEncoder().encode(config)) ?? Data(),
            "lh": localHaptics
        ]
    }

    /// Tolerant: whichever parts decode are used, the rest keep their defaults.
    public init?(dictionary d: [String: Any]) {
        guard d["k"] as? String == "ctx" else { return nil }
        var cal = Calibration.default
        var cfg = GestureConfig.default
        if let data = d["cal"] as? Data, let v = try? JSONDecoder().decode(Calibration.self, from: data) { cal = v }
        if let data = d["cfg"] as? Data, let v = try? JSONDecoder().decode(GestureConfig.self, from: data) { cfg = v }
        calibration = cal
        config = cfg
        localHaptics = d["lh"] as? Bool ?? true
    }
}
