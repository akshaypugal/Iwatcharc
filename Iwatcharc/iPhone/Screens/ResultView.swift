import SwiftUI
import WristBoxCore

struct ResultView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var router: AppRouter
    @State private var appeared = false

    var body: some View {
        Group {
            if let result = env.lastResult {
                content(result)
            } else {
                VStack(spacing: 16) {
                    Text("No fight to show").font(.heavy(22)).foregroundColor(.white)
                    Button("HOME") { router.popToRoot() }.buttonStyle(BigButtonStyle()).padding(.horizontal, 60)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { appeared = true }
        }
    }

    private func content(_ r: FightResultSummary) -> some View {
        let reward = r.reward
        let stats = reward.stats
        return ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                VStack(spacing: 4) {
                    Text(reward.won ? "VICTORY!" : "DEFEAT")
                        .font(.heavy(54))
                        .foregroundStyle(reward.won ? AnyShapeStyle(Theme.fire) : AnyShapeStyle(Theme.red))
                        .shadow(color: (reward.won ? Theme.orange : Theme.red).opacity(0.6), radius: 16)
                        .scaleEffect(appeared ? 1 : 0.4)
                    Text(subtitle(r)).font(.heavy(14)).foregroundColor(Theme.textDim)
                }
                .padding(.top, 20)

                HStack(spacing: 12) {
                    rewardTile(value: "+\(reward.xp)", label: "XP", color: Theme.blue)
                    rewardTile(value: "+\(reward.coins)", label: "COINS", color: Theme.gold)
                }

                if reward.levelsGained > 0 {
                    banner("⬆️ LEVEL UP! You are now level \(reward.newLevel)", color: Theme.green)
                }
                if let id = reward.unlockedOpponent {
                    banner("🔓 UNLOCKED: \(OpponentProfile.roster[id].name) (\(OpponentProfile.roster[id].rank.title))", color: Theme.orange)
                }
                if reward.careerCompleted {
                    banner("🏆 CAREER COMPLETE - You are the CHAMPION!", color: Theme.gold)
                }
                if !reward.completedChallenges.isEmpty {
                    banner("⚡ Daily challenge complete - claim your reward!", color: Theme.blue)
                }

                Card {
                    VStack(spacing: 8) {
                        ForEach(Array(reward.lines.enumerated()), id: \.offset) { _, line in
                            HStack {
                                Text(line.title).font(.rounded(14)).foregroundColor(.white)
                                Spacer()
                                Text("+\(line.xp) XP").font(.heavy(13)).foregroundColor(Theme.blue)
                                Text("+\(line.coins) 🪙").font(.heavy(13)).foregroundColor(Theme.gold)
                                    .frame(width: 70, alignment: .trailing)
                            }
                        }
                    }
                }

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        StatTile(value: "\(Int((stats.accuracy * 100).rounded()))%", label: "Accuracy")
                        StatTile(value: "\(stats.punchesThrown)", label: "Punches")
                    }
                    HStack(spacing: 10) {
                        StatTile(value: "\(stats.combos)", label: "Combos")
                        StatTile(value: "x\(stats.maxCombo)", label: "Best combo", color: Theme.orange)
                    }
                    HStack(spacing: 10) {
                        StatTile(value: "\(stats.counters)", label: "Counters", color: Theme.blue)
                        StatTile(value: "\(stats.perfectPunches)", label: "Perfect", color: Theme.gold)
                    }
                }

                VStack(spacing: 10) {
                    Button("REMATCH") {
                        env.lastResult = nil
                        router.replaceTop(with: .fight(opponent: r.opponent.id, tier: r.tier))
                    }
                    .buttonStyle(BigButtonStyle())

                    if let next = reward.unlockedOpponent {
                        Button("NEXT: \(OpponentProfile.roster[next].nickname.uppercased())") {
                            env.lastResult = nil
                            router.replaceTop(with: .fight(opponent: next, tier: 0))
                        }
                        .buttonStyle(BigButtonStyle(colors: [Theme.orange, Color(hex: "C45A12")], height: 56))
                    }

                    HStack(spacing: 10) {
                        Button("UPGRADES") { router.replaceTop(with: .upgrades) }
                            .buttonStyle(BigButtonStyle(colors: [Theme.blue, Color(hex: "1D4FB5")], height: 52))
                        Button("HOME") { router.popToRoot() }
                            .buttonStyle(BigButtonStyle(colors: [Color(white: 0.3), Color(white: 0.18)], height: 52))
                    }
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
    }

    private func subtitle(_ r: FightResultSummary) -> String {
        let method = r.outcome.method == .ko ? "BY KNOCKOUT" : "BY DECISION"
        let rounds = "\(r.outcome.playerRoundsWon)–\(r.outcome.opponentRoundsWon) in rounds"
        return "vs \(r.opponent.name) · \(method) · \(rounds)"
    }

    private func rewardTile(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.heavy(36)).foregroundColor(color)
            Text(label).font(.heavy(12)).foregroundColor(Theme.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(color.opacity(0.4), lineWidth: 1))
        .scaleEffect(appeared ? 1 : 0.7)
    }

    private func banner(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.heavy(14))
            .foregroundColor(color)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(color.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
