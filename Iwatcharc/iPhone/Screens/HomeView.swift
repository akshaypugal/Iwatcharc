import SwiftUI
import WristBoxCore

struct HomeView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var controller: WristController

    private var nextOpponent: OpponentProfile {
        env.opponent(id: min(env.profile.careerProgress, OpponentProfile.roster.count - 1), tier: 0)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                header

                Card { LevelBadge(profile: env.profile) }

                connectionCard

                Button {
                    router.push(.career)
                } label: {
                    HStack(spacing: 12) {
                        Text("🥊").font(.system(size: 34))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CAREER").font(.heavy(26))
                            Text(env.profile.careerCleared ? "Defend your title" : "Next: \(nextOpponent.name) · \(nextOpponent.styleTitle)")
                                .font(.rounded(13)).opacity(0.85)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 18, weight: .bold))
                    }
                    .padding(.horizontal, 18)
                }
                .buttonStyle(BigButtonStyle(height: 84))

                MenuRow(icon: "⚡", title: "DAILY CHALLENGE",
                        subtitle: "\(env.profile.daily.challenges.filter { $0.isComplete }.count)/\(env.profile.daily.challenges.count) complete",
                        badge: env.profile.daily.claimableCount > 0 ? "\(env.profile.daily.claimableCount)" : nil) {
                    router.push(.challenges)
                }
                MenuRow(icon: "💪", title: "UPGRADES", subtitle: "Power · Speed · Defense · Stamina", badge: nil) {
                    router.push(.upgrades)
                }
                MenuRow(icon: "🏆", title: "STATS", subtitle: "\(env.profile.fightsWon) wins · \(env.profile.knockouts) KOs", badge: nil) {
                    router.push(.stats)
                }
                MenuRow(icon: "⚙️", title: "SETTINGS", subtitle: "Calibration, sound, haptics", badge: nil) {
                    router.push(.settings)
                }
                if env.profile.settings.developerMode {
                    MenuRow(icon: "🛠", title: "DEBUG", subtitle: "Sensors, gestures, latency", badge: nil) {
                        router.push(.debug)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("WRISTBOX")
                    .font(.heavy(40))
                    .foregroundStyle(Theme.fire)
                Text("Your wrist. Your fight.")
                    .font(.rounded(15))
                    .foregroundColor(Theme.textDim)
            }
            Spacer()
            CoinLabel(coins: env.profile.coins)
        }
    }

    private var connectionCard: some View {
        Card(padding: 12) {
            HStack {
                ConnectionBadge()
                Spacer()
                if !controller.linkState.isConnected, !controller.simulatorEnabled {
                    Text("Open WristBox on your Watch")
                        .font(.rounded(12)).foregroundColor(Theme.textDim)
                } else if controller.linkState.isConnected, !env.profile.calibration.isCalibrated {
                    Button("CALIBRATE") { router.push(.settings) }
                        .buttonStyle(SmallButtonStyle(tint: Theme.orange))
                }
            }
        }
    }
}

struct MenuRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let badge: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(icon).font(.system(size: 26)).frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.heavy(18)).foregroundColor(.white)
                    Text(subtitle).font(.rounded(12)).foregroundColor(Theme.textDim)
                }
                Spacer()
                if let badge {
                    Text(badge).font(.heavy(13)).foregroundColor(.black)
                        .frame(minWidth: 24, minHeight: 24)
                        .background(Theme.gold).clipShape(Circle())
                }
                Image(systemName: "chevron.right").foregroundColor(Theme.textDim)
            }
            .padding(14)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
