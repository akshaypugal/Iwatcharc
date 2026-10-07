import SwiftUI
import WristBoxCore

/// The fight screen: arena, opponent, HUD, first-person gloves and effects.
struct FightView: View {
    @EnvironmentObject var controller: WristController
    @StateObject private var vm: FightViewModel

    init(env: AppEnvironment, opponent: Int, tier: Int) {
        _vm = StateObject(wrappedValue: FightViewModel(env: env, opponentID: opponent, tier: tier))
    }

    var body: some View {
        ZStack {
            TimelineView(.animation) { timeline in
                arena(now: timeline.date)
            }

            VStack(spacing: 0) {
                FightHUD(vm: vm)
                Spacer(minLength: 0)
                FightBottomBar(vm: vm)
                if controller.simulatorEnabled {
                    SimControllerView()
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 6)

            overlays
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .onAppear { vm.begin() }
        .onDisappear { vm.end() }
    }

    // MARK: Arena

    private func arena(now: Date) -> some View {
        GeometryReader { geo in
            let shake = shakeOffset(now: now)
            ZStack {
                ArenaBackdrop()

                FighterView(profile: vm.opponent,
                            state: vm.snapshot.opponentState,
                            attack: vm.snapshot.attack,
                            perfectWindow: vm.snapshot.perfectWindowOpen,
                            hitAt: vm.opponentHitAt,
                            now: now)
                    .scaleEffect(min(1.15, geo.size.height / 760))
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.40)

                if let attack = vm.snapshot.attack, attack.progress < 0.97, !attack.isFeint || attack.progress < 0.55 {
                    DodgeCue(kind: attack.kind, progress: attack.progress)
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.62)
                }

                PlayerGlovesView(punch: vm.punchFX,
                                 dodge: vm.dodgeFX,
                                 blocking: vm.snapshot.playerBlocking,
                                 now: now)
                    .frame(width: geo.size.width, height: geo.size.height * 0.34)
                    .position(x: geo.size.width / 2, y: geo.size.height - geo.size.height * 0.15)

                EffectsOverlay(vm: vm, now: now, size: geo.size)

                if let playerHit = vm.playerHitAt, now.timeIntervalSince(playerHit) < 0.5 {
                    RadialGradient(colors: [.clear, Theme.red.opacity(0.6 * (1 - now.timeIntervalSince(playerHit) / 0.5))],
                                   center: .center, startRadius: 120, endRadius: 520)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
                if let f = vm.flash, now.timeIntervalSince(f.start) < 0.25 {
                    f.color.opacity(0.35 * (1 - now.timeIntervalSince(f.start) / 0.25))
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
            .offset(shake)
        }
        .ignoresSafeArea()
    }

    private func shakeOffset(now: Date) -> CGSize {
        guard let s = vm.shake else { return .zero }
        let k = now.timeIntervalSince(s.start)
        guard k >= 0, k < 0.4 else { return .zero }
        let decay = CGFloat(1 - k / 0.4)
        return CGSize(width: CGFloat(sin(k * 70)) * s.amplitude * decay,
                      height: CGFloat(cos(k * 55)) * s.amplitude * decay * 0.7)
    }

    // MARK: Overlays

    @ViewBuilder
    private var overlays: some View {
        if vm.controllerLost, vm.snapshot.phase != .fightOver {
            Color.black.opacity(0.82).ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "applewatch.slash").font(.system(size: 54)).foregroundColor(Theme.red)
                Text("WATCH DISCONNECTED").font(.heavy(26)).foregroundColor(.white)
                Text(controller.linkState.detail)
                    .font(.rounded(15)).foregroundColor(Theme.textDim)
                    .multilineTextAlignment(.center).padding(.horizontal, 30)
                Text("The fight is paused and resumes automatically when your Watch reconnects.")
                    .font(.rounded(13)).foregroundColor(Theme.textDim)
                    .multilineTextAlignment(.center).padding(.horizontal, 30)
                Button("USE SIMULATED CONTROLLER") { vm.useSimulatedController() }
                    .buttonStyle(BigButtonStyle(colors: [Theme.blue, Color(hex: "1D4FB5")], height: 54))
                    .padding(.horizontal, 30)
                Button("QUIT FIGHT") { vm.quit() }
                    .buttonStyle(SmallButtonStyle(tint: Color.white.opacity(0.2)))
            }
        } else if vm.userPaused {
            Color.black.opacity(0.75).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("PAUSED").font(.heavy(44)).foregroundColor(.white)
                Button("RESUME") { vm.userPaused = false }
                    .buttonStyle(BigButtonStyle())
                    .padding(.horizontal, 60)
                Button("QUIT FIGHT") { vm.quit() }
                    .buttonStyle(SmallButtonStyle(tint: Color.white.opacity(0.2)))
            }
        }
    }
}

// MARK: - HUD

struct FightHUD: View {
    @ObservedObject var vm: FightViewModel
    @EnvironmentObject var controller: WristController
    @EnvironmentObject var env: AppEnvironment

    private var timeText: String {
        let t = max(0, Int(vm.snapshot.timeRemaining.rounded(.up)))
        return String(format: "%02d:%02d", t / 60, t % 60)
    }

    var body: some View {
        let s = vm.snapshot
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PLAYER").font(.heavy(12)).foregroundColor(.white)
                    BarView(fraction: s.playerHealth / s.playerMaxHealth,
                            colors: [Theme.green, Color(hex: "1E8F5C")], height: 18)
                }
                VStack(spacing: 2) {
                    Text(timeText).font(.heavy(30)).foregroundColor(.white).monospacedDigit()
                    Text("ROUND \(s.round)").font(.heavy(12)).foregroundColor(Theme.gold)
                    HStack(spacing: 4) {
                        ForEach(0..<2, id: \.self) { i in
                            Circle().fill(i < s.playerRoundWins ? Theme.green : Color.white.opacity(0.2)).frame(width: 7, height: 7)
                        }
                        Text("·").foregroundColor(Theme.textDim)
                        ForEach(0..<2, id: \.self) { i in
                            Circle().fill(i < s.opponentRoundWins ? Theme.red : Color.white.opacity(0.2)).frame(width: 7, height: 7)
                        }
                    }
                }
                .frame(width: 92)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(vm.opponent.nickname.uppercased()).font(.heavy(12)).foregroundColor(.white).lineLimit(1)
                    BarView(fraction: s.opponentHealth / s.opponentMaxHealth,
                            colors: [Theme.red, Theme.redDark], height: 18, reversed: true)
                }
            }
            HStack {
                Button { vm.userPaused = true } label: {
                    Image(systemName: "pause.fill").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                        .frame(width: 30, height: 26).background(Color.white.opacity(0.14)).clipShape(Capsule())
                }
                ConnectionBadge()
                Spacer()
                if env.profile.settings.showLatency {
                    Text(latencyText).font(.mono(11)).foregroundColor(Theme.green)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.black.opacity(0.5)).clipShape(Capsule())
                }
            }
        }
    }

    private var latencyText: String {
        let l = controller.latency
        return l.count > 0 ? "Motion → Game \(Int(l.last.rounded())) ms" : "Motion → Game --"
    }
}

// MARK: - Bottom bar (combo, stamina, special)

struct FightBottomBar: View {
    @ObservedObject var vm: FightViewModel

    var body: some View {
        let s = vm.snapshot
        VStack(spacing: 8) {
            if s.combo >= 2 {
                VStack(spacing: 0) {
                    Text("🔥 COMBO x\(s.combo)")
                        .font(.heavy(26))
                        .foregroundStyle(Theme.fire)
                        .shadow(color: Theme.orange.opacity(0.8), radius: 8)
                    if let name = s.comboName {
                        Text(name).font(.heavy(12)).foregroundColor(Theme.gold)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
            HStack(spacing: 12) {
                LabeledBar(title: "STAMINA",
                           valueText: "\(Int((s.stamina / s.staminaMax * 100).rounded()))%",
                           fraction: s.stamina / s.staminaMax,
                           colors: s.stamina / s.staminaMax < 0.25 ? [Theme.orange, Theme.red] : [Theme.blue, Color(hex: "7AB0FF")])
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(s.specialReady ? "SPECIAL READY!" : "SPECIAL").font(.heavy(11))
                            .foregroundColor(s.specialReady ? Theme.gold : Theme.textDim)
                        Spacer()
                        Text("\(Int(s.special.rounded()))%").font(.heavy(11)).foregroundColor(.white)
                    }
                    BarView(fraction: s.special / 100, colors: [Theme.gold, Theme.orange], height: 12)
                        .shadow(color: s.specialReady ? Theme.gold : .clear, radius: 8)
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: s.combo)
        .padding(.bottom, 2)
    }
}

// MARK: - Arena backdrop

struct ArenaBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Color(hex: "0A0A14"), Color(hex: "1D1236"), Color(hex: "2A1030")],
                               startPoint: .top, endPoint: .bottom)
                // crowd glow
                ForEach(0..<14, id: \.self) { i in
                    Circle()
                        .fill(Color.white.opacity(0.05 + 0.03 * Double(i % 3)))
                        .frame(width: 26, height: 26)
                        .position(x: CGFloat(i) / 13 * geo.size.width, y: geo.size.height * (0.12 + 0.03 * CGFloat(i % 4)))
                }
                // spotlight
                RadialGradient(colors: [Color.white.opacity(0.22), .clear],
                               center: .init(x: 0.5, y: 0.35), startRadius: 10, endRadius: geo.size.width * 0.9)
                // ropes
                ForEach(0..<3, id: \.self) { i in
                    Rectangle()
                        .fill(i == 1 ? Color.white.opacity(0.7) : Theme.red.opacity(0.8))
                        .frame(height: 5)
                        .position(x: geo.size.width / 2, y: geo.size.height * (0.50 + 0.045 * CGFloat(i)))
                        .shadow(color: .black.opacity(0.5), radius: 3, y: 3)
                }
                // canvas floor
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height * 0.68))
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height * 0.68))
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    p.addLine(to: CGPoint(x: 0, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [Color(hex: "3B2A5A"), Color(hex: "1A1030")], startPoint: .top, endPoint: .bottom))
            }
        }
    }
}

// MARK: - Dodge cue

/// Tells the player how to avoid the incoming punch.
struct DodgeCue: View {
    let kind: AttackKind
    let progress: Double

    private var text: String {
        switch kind {
        case .leftHook: return "DODGE RIGHT  →"
        case .rightHook: return "←  DODGE LEFT"
        case .uppercut: return "DODGE or BLOCK!"
        default: return "DODGE or BLOCK!"
        }
    }

    var body: some View {
        let urgency = easeOut(progress)
        Text(text)
            .font(.heavy(20))
            .foregroundColor(Color(red: 1, green: 1 - 0.7 * urgency, blue: 0.3 * (1 - urgency)))
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Color.black.opacity(0.55))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.red.opacity(0.4 + 0.6 * urgency), lineWidth: 2))
            .scaleEffect(1 + 0.12 * urgency)
    }
}
