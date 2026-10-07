import SwiftUI
import WristBoxCore

struct StatsView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var router: AppRouter

    var body: some View {
        let p = env.profile
        let s = p.lifetime
        let winRate = p.fightsPlayed == 0 ? 0 : Int((Double(p.fightsWon) / Double(p.fightsPlayed) * 100).rounded())

        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                ScreenHeader(title: "STATS", subtitle: "\(p.rank.title) · level \(p.level)") { router.pop() }

                Card { LevelBadge(profile: p) }

                HStack(spacing: 10) {
                    StatTile(value: "\(p.fightsPlayed)", label: "Fights")
                    StatTile(value: "\(p.fightsWon)", label: "Wins", color: Theme.green)
                    StatTile(value: "\(winRate)%", label: "Win rate", color: Theme.gold)
                }
                HStack(spacing: 10) {
                    StatTile(value: "\(p.knockouts)", label: "Knockouts", color: Theme.red)
                    StatTile(value: "x\(s.maxCombo)", label: "Best combo", color: Theme.orange)
                    StatTile(value: "\(Int((s.accuracy * 100).rounded()))%", label: "Accuracy")
                }
                HStack(spacing: 10) {
                    StatTile(value: "\(s.punchesThrown)", label: "Punches")
                    StatTile(value: "\(s.counters)", label: "Counters", color: Theme.blue)
                    StatTile(value: "\(s.perfectPunches)", label: "Perfect", color: Theme.gold)
                }
                HStack(spacing: 10) {
                    StatTile(value: "\(s.dodges)", label: "Dodges")
                    StatTile(value: "\(s.blocks)", label: "Blocks")
                    StatTile(value: "\(Int(s.damageDealt))", label: "Damage dealt")
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("PUNCHES LANDED").font(.heavy(13)).foregroundColor(Theme.textDim)
                        let maxLanded = max(1, PunchType.allCases.map { s.landed($0) }.max() ?? 1)
                        ForEach(PunchType.allCases, id: \.self) { type in
                            HStack(spacing: 10) {
                                Text(type.displayName).font(.heavy(11)).foregroundColor(.white).frame(width: 96, alignment: .leading)
                                BarView(fraction: Double(s.landed(type)) / Double(maxLanded), colors: [Theme.red, Theme.redDark], height: 10)
                                Text("\(s.landed(type))").font(.heavy(11)).foregroundColor(Theme.textDim).frame(width: 40, alignment: .trailing)
                            }
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("CAREER").font(.heavy(13)).foregroundColor(Theme.textDim)
                        ForEach(OpponentProfile.roster) { opp in
                            HStack {
                                Text(opp.rank.title).font(.heavy(11)).foregroundColor(Theme.gold).frame(width: 90, alignment: .leading)
                                Text(opp.nickname).font(.rounded(14)).foregroundColor(.white)
                                Spacer()
                                if p.isUnlocked(opponent: opp.id) {
                                    Text("\(p.opponentWins.indices.contains(opp.id) ? p.opponentWins[opp.id] : 0) wins")
                                        .font(.heavy(12)).foregroundColor(Theme.green)
                                } else {
                                    Image(systemName: "lock.fill").foregroundColor(Theme.textDim)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
