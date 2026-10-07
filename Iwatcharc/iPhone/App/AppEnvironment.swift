import SwiftUI
import WristBoxCore

enum Route: Hashable {
    case career
    case fight(opponent: Int, tier: Int)
    case result
    case upgrades
    case challenges
    case stats
    case settings
    case debug
}

final class AppRouter: ObservableObject {
    @Published var path = NavigationPath()

    func push(_ route: Route) { path.append(route) }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func popToRoot() { path = NavigationPath() }

    /// Replace the top screen (used to swap the fight for its result).
    func replaceTop(with route: Route) {
        if !path.isEmpty { path.removeLast() }
        path.append(route)
    }
}

/// Everything a finished fight leaves behind for the Result screen.
struct FightResultSummary {
    let outcome: FightOutcome
    let opponent: OpponentProfile
    let tier: Int
    let reward: RewardSummary
}

/// App-wide state: the saved profile, input controller, audio and haptics.
final class AppEnvironment: ObservableObject {
    @Published var profile: PlayerProfile {
        didSet { persist() }
    }
    @Published var lastResult: FightResultSummary?

    let store: ProfileStore
    let controller = WristController()
    let router = AppRouter()
    let haptics = HapticsService()
    let sound = SoundService()

    init(store: ProfileStore = FileProfileStore(url: FileProfileStore.defaultURL())) {
        self.store = store
        var loaded = store.load() ?? PlayerProfile()
        #if targetEnvironment(simulator)
        // No Watch in the Simulator: start in Developer Controller Mode.
        if !loaded.hasOnboarded {
            loaded.settings.simulatedController = true
            loaded.settings.developerMode = true
        }
        #endif
        loaded.daily.refreshIfNeeded(now: Date())
        profile = loaded

        controller.simulatorEnabled = loaded.settings.simulatedController
        controller.syncProvider = { [weak self] in
            guard let self else { return SyncContext(calibration: .default, config: .default, localHaptics: true) }
            return SyncContext(calibration: self.profile.calibration,
                               config: self.profile.settings.gestureConfig,
                               localHaptics: self.profile.settings.localWatchHaptics)
        }
        controller.onCalibration = { [weak self] calibration in
            self?.profile.calibration = calibration
        }
        applySettings()
        controller.start()
        haptics.prepare()
    }

    // MARK: Persistence

    private func persist() {
        try? store.save(profile)
    }

    /// Pushes the saved settings into the services that act on them.
    func applySettings() {
        sound.enabled = profile.settings.soundEnabled
        haptics.enabled = profile.settings.hapticsEnabled
        controller.simulatorEnabled = profile.settings.simulatedController
    }

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        var s = profile.settings
        change(&s)
        profile.settings = s
        applySettings()
        controller.syncToWatch()
    }

    // MARK: Scene

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            controller.appBecameActive()
            profile.daily.refreshIfNeeded(now: Date())
        case .background:
            try? store.save(profile)
        default:
            break
        }
    }

    // MARK: Gameplay hooks

    func opponent(id: Int, tier: Int) -> OpponentProfile {
        OpponentProfile.roster[min(max(id, 0), OpponentProfile.roster.count - 1)].scaled(tier: tier)
    }

    /// Applies a finished fight to the profile and prepares the Result screen.
    func finishFight(_ outcome: FightOutcome, opponent: OpponentProfile, tier: Int) {
        var p = profile
        let reward = ProgressionService.apply(outcome: outcome, opponent: opponent, tier: tier, to: &p)
        profile = p
        lastResult = FightResultSummary(outcome: outcome, opponent: opponent, tier: tier, reward: reward)
    }

    func buy(_ stat: UpgradeStat) -> Bool {
        var p = profile
        let ok = ProgressionService.purchase(stat, profile: &p)
        if ok { profile = p }
        return ok
    }

    func claim(challenge id: String) {
        var p = profile
        if ProgressionService.claimChallenge(id: id, profile: &p) != nil { profile = p }
    }

    func resetProgress() {
        var fresh = PlayerProfile()
        fresh.settings = profile.settings
        fresh.calibration = profile.calibration
        fresh.hasOnboarded = true
        fresh.daily.refreshIfNeeded(now: Date())
        profile = fresh
    }
}
