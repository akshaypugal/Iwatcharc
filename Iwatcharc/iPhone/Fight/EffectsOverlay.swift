import SwiftUI
import WristBoxCore

/// Banners, floating damage numbers, impact starbursts and the KO flash.
struct EffectsOverlay: View {
    @ObservedObject var vm: FightViewModel
    let now: Date
    let size: CGSize

    var body: some View {
        ZStack {
            // Impact starbursts on the opponent.
            ForEach(vm.bursts) { b in
                let k = min(1, max(0, now.timeIntervalSince(b.created) / b.duration))
                StarShape(points: 10, innerRatio: 0.42)
                    .fill(b.color.opacity(0.9 * (1 - k)))
                    .frame(width: (b.big ? 190 : 120) * CGFloat(0.5 + easeOut(k)),
                           height: (b.big ? 190 : 120) * CGFloat(0.5 + easeOut(k)))
                    .rotationEffect(.degrees(Double(b.id.hashValue % 40) + k * 40))
                    .position(x: size.width / 2 + b.x * size.width, y: size.height * b.y)
                    .blendMode(.plusLighter)
            }

            // Damage numbers rise and fade.
            ForEach(vm.numbers) { n in
                let k = min(1, max(0, now.timeIntervalSince(n.created) / n.duration))
                Text(n.text)
                    .font(.heavy(n.size))
                    .foregroundColor(n.color)
                    .shadow(color: .black.opacity(0.8), radius: 3, y: 2)
                    .scaleEffect(1 + 0.25 * CGFloat(sin(min(k * 3, 1) * .pi)))
                    .opacity(1 - k * k)
                    .position(x: size.width / 2 + n.x * size.width,
                              y: size.height * n.y - CGFloat(easeOut(k)) * 70)
            }

            // Banners.
            VStack(spacing: 6) {
                ForEach(vm.banners) { b in
                    let k = b.progress(at: now)
                    let pop = k < 0.15 ? easeOut(k / 0.15) : 1
                    let fade = k > 0.75 ? 1 - (k - 0.75) / 0.25 : 1
                    VStack(spacing: 2) {
                        Text(b.text)
                            .font(.heavy(b.size))
                            .foregroundColor(b.color)
                            .shadow(color: b.color.opacity(0.7), radius: 12)
                            .shadow(color: .black.opacity(0.8), radius: 3, y: 3)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        if let sub = b.subtitle {
                            Text(sub).font(.heavy(max(14, b.size * 0.4))).foregroundColor(.white)
                                .shadow(color: .black.opacity(0.8), radius: 2, y: 2)
                        }
                    }
                    .scaleEffect(CGFloat(0.6 + 0.4 * pop + 0.04 * sin(k * 8)))
                    .opacity(fade)
                }
            }
            .position(x: size.width / 2, y: size.height * 0.30)

            // KO darkening.
            if let ko = vm.koAt, now.timeIntervalSince(ko) < 2.6 {
                let k = now.timeIntervalSince(ko)
                Color.black.opacity(min(0.55, k * 0.9)).allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
    }
}
