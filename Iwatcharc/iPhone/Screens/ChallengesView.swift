import SwiftUI
import WristBoxCore

struct ChallengesView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var router: AppRouter

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                ScreenHeader(title: "DAILY CHALLENGE", subtitle: "New challenges every day · works offline") { router.pop() }

                ForEach(env.profile.daily.challenges) { c in
                    ChallengeCard(challenge: c) { env.claim(challenge: c.id) }
                }

                Text("Each challenge pays +\(DailyChallenge.rewardXP) XP and +\(DailyChallenge.rewardCoins) coins.")
                    .font(.rounded(12)).foregroundColor(Theme.textDim)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            var p = env.profile
            if p.daily.refreshIfNeeded(now: Date()) { env.profile = p }
        }
    }
}

struct ChallengeCard: View {
    let challenge: DailyChallenge
    let onClaim: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text(challenge.kind.icon).font(.system(size: 30))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(challenge.title).font(.heavy(17)).foregroundColor(.white)
                        Text("+\(DailyChallenge.rewardXP) XP  ·  +\(DailyChallenge.rewardCoins) 🪙")
                            .font(.rounded(12)).foregroundColor(Theme.gold)
                    }
                    Spacer()
                    if challenge.claimed {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 26)).foregroundColor(Theme.green)
                    }
                }
                HStack(spacing: 10) {
                    BarView(fraction: challenge.fraction,
                            colors: challenge.isComplete ? [Theme.green, Color(hex: "1E8F5C")] : [Theme.blue, Color(hex: "7AB0FF")],
                            height: 12)
                    Text("\(min(challenge.progress, challenge.target))/\(challenge.target)")
                        .font(.heavy(13)).foregroundColor(.white).frame(width: 56, alignment: .trailing)
                }
                if challenge.isComplete, !challenge.claimed {
                    Button("CLAIM REWARD", action: onClaim)
                        .buttonStyle(BigButtonStyle(colors: [Theme.gold, Theme.orange], height: 48))
                }
            }
        }
    }
}
