import SwiftUI
import WristBoxCore

@main
struct WristBoxApp: App {
    @StateObject private var env = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(env)
                .environmentObject(env.controller)
                .environmentObject(env.router)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { phase in
                    env.scenePhaseChanged(phase)
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var router: AppRouter

    var body: some View {
        ZStack {
            ScreenBackground()
            if env.profile.hasOnboarded {
                NavigationStack(path: $router.path) {
                    HomeView()
                        .navigationDestination(for: Route.self) { route in
                            destination(for: route)
                        }
                }
            } else {
                OnboardingView()
            }
        }
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .career:
            CareerView()
        case .fight(let opponent, let tier):
            FightView(env: env, opponent: opponent, tier: tier)
        case .result:
            ResultView()
        case .upgrades:
            UpgradeView()
        case .challenges:
            ChallengesView()
        case .stats:
            StatsView()
        case .settings:
            SettingsView()
        case .debug:
            DebugView()
        }
    }
}
