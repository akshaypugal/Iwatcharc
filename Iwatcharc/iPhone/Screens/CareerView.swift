import SwiftUI
import WristBoxCore

struct CareerView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var controller: WristController

    @State private var tier = 0
    @State private var showNoController = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                ScreenHeader(title: "CAREER", subtitle: "BOXER → ROOKIE → CONTENDER → PRO → CHAMPION") {
                    router.pop()
                }

                if env.profile.careerCleared {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("🏆 YOU ARE THE CHAMPION").font(.heavy(16)).foregroundColor(Theme.gold)
                            Text("Title Defence: every opponent returns faster, tougher and smarter, and pays more.")
                                .font(.rounded(13)).foregroundColor(Theme.textDim)
                            Picker("Difficulty", selection: $tier) {
                                Text("Normal").tag(0)
                                ForEach(1...env.profile.maxTier, id: \.self) { Text("Defence \($0)").tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                }

                ForEach(OpponentProfile.roster) { opp in
                    OpponentCard(opponent: opp.scaled(tier: tier),
                                 unlocked: env.profile.isUnlocked(opponent: opp.id),
                                 wins: env.profile.opponentWins.indices.contains(opp.id) ? env.profile.opponentWins[opp.id] : 0,
                                 isNext: opp.id == env.profile.careerProgress && tier == 0) {
                        startFight(opp.id)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("No controller connected", isPresented: $showNoController) {
            Button("Use Developer Controller") {
                env.updateSettings { $0.simulatedController = true }
                router.push(.fight(opponent: pendingOpponent, tier: tier))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your Apple Watch is not connected. Open WristBox on your Watch, or play with the on-screen developer controller.")
        }
    }

    @State private var pendingOpponent = 0

    private func startFight(_ id: Int) {
        pendingOpponent = id
        if controller.hasController {
            router.push(.fight(opponent: id, tier: tier))
        } else {
            showNoController = true
        }
    }
}

struct OpponentCard: View {
    let opponent: OpponentProfile
    let unlocked: Bool
    let wins: Int
    let isNext: Bool
    let onFight: () -> Void

    // Behaviour meters (not health!) so players can see what makes each boxer different.
    private var speed: Double { clamp((1.5 - opponent.telegraphScale) / 0.8) }
    private var defense: Double { clamp(opponent.blockChance + opponent.dodgeChance, 0, 1) / 0.75 }
    private var pressure: Double { clamp(1 - (opponent.restMax - 0.5) / 2.5) }
    private var counter: Double { clamp(opponent.counterChance / 0.4) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    avatar
                    VStack(alignment: .leading, spacing: 2) {
                        Text(opponent.rank.title).font(.heavy(11)).foregroundColor(Theme.gold)
                        Text("\(opponent.name) \"\(opponent.nickname)\"").font(.heavy(17)).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
                        Text(opponent.styleTitle).font(.rounded(12)).foregroundColor(Theme.red)
                    }
                    Spacer()
                    if wins > 0 {
                        Text("\(wins)W").font(.heavy(12)).foregroundColor(Theme.green)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Theme.green.opacity(0.15)).clipShape(Capsule())
                    }
                }
                Text(opponent.tagline).font(.rounded(13)).foregroundColor(Theme.textDim)

                HStack(spacing: 10) {
                    meter("SPEED", speed, Theme.orange)
                    meter("DEFENSE", defense, Theme.blue)
                    meter("PRESSURE", pressure, Theme.red)
                    meter("COUNTER", counter, Theme.gold)
                }

                if unlocked {
                    Button(action: onFight) {
                        Text(isNext ? "FIGHT" : "REMATCH")
                    }
                    .buttonStyle(BigButtonStyle(colors: isNext ? [Theme.red, Theme.redDark] : [Theme.blue, Color(hex: "1D4FB5")], height: 50))
                } else {
                    HStack {
                        Image(systemName: "lock.fill")
                        Text("Beat the previous boxer to unlock").font(.rounded(13))
                    }
                    .foregroundColor(Theme.textDim)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .opacity(unlocked ? 1 : 0.6)
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(Color(hex: opponent.trunksHex).opacity(0.35)).frame(width: 54, height: 54)
            Circle().fill(Color(hex: opponent.skinHex)).frame(width: 36, height: 36).offset(y: -2)
            Circle().trim(from: 0.5, to: 1.0).fill(Color(hex: opponent.hairHex)).frame(width: 37, height: 37).offset(y: -2)
            Circle().fill(Color(hex: opponent.gloveHex)).frame(width: 18, height: 18).offset(x: -20, y: 12)
            Circle().fill(Color(hex: opponent.gloveHex)).frame(width: 18, height: 18).offset(x: 20, y: 12)
        }
        .frame(width: 58, height: 58)
    }

    private func meter(_ title: String, _ value: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.heavy(8)).foregroundColor(Theme.textDim)
            BarView(fraction: value, colors: [color, color.opacity(0.6)], height: 7)
        }
    }
}
