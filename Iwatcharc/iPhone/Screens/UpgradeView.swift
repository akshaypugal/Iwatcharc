import SwiftUI
import WristBoxCore

struct UpgradeView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var router: AppRouter
    @State private var flash: UpgradeStat?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                HStack {
                    ScreenHeader(title: "UPGRADES", subtitle: "Spend coins to get stronger") { router.pop() }
                }
                HStack {
                    Spacer()
                    CoinLabel(coins: env.profile.coins)
                }
                ForEach(UpgradeStat.allCases) { stat in
                    row(stat)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func effectText(_ stat: UpgradeStat) -> String {
        let u = env.profile.upgrades
        switch stat {
        case .power: return "Damage x\(String(format: "%.2f", u.damageMultiplier))"
        case .speed: return "Combo window x\(String(format: "%.2f", u.comboWindowMultiplier)) · counters x\(String(format: "%.2f", u.counterWindowMultiplier))"
        case .defense: return "-\(Int((u.defenseReduction * 100).rounded()))% damage taken · blocks +\(Int((u.blockBonus * 100).rounded()))%"
        case .stamina: return "\(Int(u.staminaMax)) stamina · recovery x\(String(format: "%.2f", u.staminaRegenMultiplier))"
        }
    }

    private func row(_ stat: UpgradeStat) -> some View {
        let level = env.profile.upgrades.level(stat)
        let cost = env.profile.upgrades.cost(for: stat)
        let canBuy = cost.map { env.profile.coins >= $0 } ?? false
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(stat.icon).font(.system(size: 30))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stat.title).font(.heavy(20)).foregroundColor(.white)
                        Text(stat.blurb).font(.rounded(12)).foregroundColor(Theme.textDim)
                    }
                    Spacer()
                    Text("LEVEL \(level)").font(.heavy(14)).foregroundColor(Theme.gold)
                }
                LevelMeter(level: level, maxLevel: PlayerUpgrades.maxLevel)
                Text(effectText(stat)).font(.rounded(12)).foregroundColor(Theme.textDim)
                if let cost {
                    Button {
                        if env.buy(stat) {
                            flash = stat
                            env.haptics.play(.perfectPunch)
                            env.sound.play(.perfect)
                        }
                    } label: {
                        HStack {
                            Text("UPGRADE")
                            Spacer()
                            Text("\(cost) 🪙")
                        }
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(BigButtonStyle(colors: canBuy ? [Theme.green, Color(hex: "1E8F5C")] : [Color(white: 0.32), Color(white: 0.2)], height: 50))
                    .disabled(!canBuy)
                } else {
                    Text("MAX LEVEL").font(.heavy(14)).foregroundColor(Theme.gold)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(Theme.gold.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.gold, lineWidth: flash == stat ? 3 : 0)
        )
        .animation(.easeOut(duration: 0.3), value: flash)
    }
}
