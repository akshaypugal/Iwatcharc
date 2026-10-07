import SwiftUI
import Combine
import WristBoxCore

/// Runs one fight on screen: drives the engine every frame, feeds it gestures
/// from the controller, and turns engine events into effects, sound and haptics
/// (on the phone *and* on the Watch).
final class FightViewModel: ObservableObject {
    let opponent: OpponentProfile
    let tier: Int
    let engine: FightEngine

    // Rendering state
    @Published private(set) var snapshot: FightSnapshot
    @Published private(set) var banners: [Banner] = []
    @Published private(set) var numbers: [FloatingNumber] = []
    @Published private(set) var bursts: [ImpactBurst] = []
    @Published private(set) var punchFX: PunchFX?
    @Published private(set) var dodgeFX: DodgeFX?
    @Published private(set) var opponentHitAt: Date?
    @Published private(set) var playerHitAt: Date?
    @Published private(set) var flash: (color: Color, start: Date)?
    @Published private(set) var shake: (amplitude: CGFloat, start: Date)?
    @Published private(set) var koAt: Date?
    @Published private(set) var lastPunch: PunchEvent?
    @Published private(set) var controllerLost = false
    @Published var userPaused = false {
        didSet { engine.isPaused = userPaused || controllerLost }
    }

    private unowned let env: AppEnvironment
    private let driver = DisplayLinkDriver()
    private var cancellables = Set<AnyCancellable>()
    private var lastWatchKey = ""
    private var finishing = false
    private var started = false

    init(env: AppEnvironment, opponentID: Int, tier: Int) {
        self.env = env
        self.tier = tier
        let profile = env.opponent(id: opponentID, tier: tier)
        opponent = profile
        let fightEngine = FightEngine(opponent: profile, upgrades: env.profile.upgrades,
                                      seed: UInt64.random(in: 1...UInt64.max))
        engine = fightEngine
        snapshot = fightEngine.snapshot
    }

    // MARK: Lifecycle

    func begin() {
        guard !started else { return }
        started = true
        let controller = env.controller

        controller.onGesture = { [weak self] event in
            guard let self else { return }
            self.engine.handle(event)
            self.processEvents()
        }
        controller.onLinkLost = { [weak self] in
            self?.engine.controllerDisconnected()
        }
        controller.setMode(.fight)

        Publishers.CombineLatest(controller.$linkState, controller.$simulatorEnabled)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state, simulated in
                self?.setControllerAvailable(state.isConnected || simulated)
            }
            .store(in: &cancellables)

        driver.onFrame = { [weak self] dt in self?.frame(dt) }
        driver.start()
        engine.start()
        processEvents()
    }

    func end() {
        driver.stop()
        cancellables.removeAll()
        let controller = env.controller
        controller.onGesture = nil
        controller.onLinkLost = nil
        controller.setMode(.off)
        controller.sendState(GameStateSummary(phase: .idle))
    }

    func quit() {
        end()
        env.router.pop()
    }

    private func setControllerAvailable(_ available: Bool) {
        controllerLost = !available
        engine.isPaused = userPaused || controllerLost
        if controllerLost { engine.controllerDisconnected() }
    }

    func useSimulatedController() {
        env.updateSettings { $0.simulatedController = true }
    }

    // MARK: Frame loop

    private func frame(_ dt: Double) {
        engine.update(dt)
        processEvents()
        snapshot = engine.snapshot
        pruneEffects()
        pushWatchState()
    }

    private func pushWatchState() {
        let s = engine.watchSummary
        let key = "\(s.phase.rawValue)-\(s.round)-\(Int(s.remaining.rounded(.down)))-\(s.combo)-\(s.specialReady)"
        guard key != lastWatchKey else { return }
        lastWatchKey = key
        env.controller.sendState(s)
    }

    private func pruneEffects() {
        let now = Date()
        if banners.contains(where: { $0.progress(at: now) >= 1 }) {
            banners.removeAll { $0.progress(at: now) >= 1 }
        }
        if numbers.contains(where: { now.timeIntervalSince($0.created) > $0.duration }) {
            numbers.removeAll { now.timeIntervalSince($0.created) > $0.duration }
        }
        if bursts.contains(where: { now.timeIntervalSince($0.created) > $0.duration }) {
            bursts.removeAll { now.timeIntervalSince($0.created) > $0.duration }
        }
    }

    // MARK: Engine events

    private func processEvents() {
        for event in engine.drainEvents() {
            react(to: event)
            if let cue = event.hapticCue {
                env.haptics.play(cue)
                env.controller.sendHaptic(cue)
            }
        }
        snapshot = engine.snapshot
    }

    private func banner(_ text: String, subtitle: String? = nil, color: Color = .white, size: CGFloat = 40, duration: Double = 1.0) {
        banners.append(Banner(text: text, subtitle: subtitle, color: color, size: size, created: Date(), duration: duration))
        if banners.count > 4 { banners.removeFirst(banners.count - 4) }
    }

    private func number(_ text: String, color: Color, x: CGFloat, y: CGFloat, size: CGFloat = 30) {
        numbers.append(FloatingNumber(text: text, color: color, x: x, y: y, size: size, created: Date()))
    }

    private func burst(big: Bool, color: Color = Theme.gold, y: CGFloat = 0.34) {
        let x = CGFloat.random(in: -0.12...0.12)
        bursts.append(ImpactBurst(x: x, y: y + CGFloat.random(in: -0.03...0.03), color: color, big: big, created: Date()))
    }

    private func shakeScreen(_ amplitude: CGFloat) {
        shake = (amplitude, Date())
    }

    private func flashScreen(_ color: Color) {
        flash = (color, Date())
    }

    private func react(to event: FightEvent) {
        let sound = env.sound
        switch event {
        case .countdown(let n):
            banner("\(n)", color: .white, size: 120, duration: 0.9)
            sound.play(.tick)

        case .roundStarted(let r):
            banner("ROUND \(r)", subtitle: "FIGHT!", color: Theme.gold, size: 54, duration: 1.3)
            sound.play(.bell)

        case .roundEnded(let summary):
            sound.play(.bell)
            let text: String
            switch summary.winner {
            case .player?: text = "ROUND WON"
            case .opponent?: text = "ROUND LOST"
            case nil: text = "DRAW"
            }
            banner(text, color: summary.winner == .player ? Theme.green : Theme.red, size: 44, duration: 2.0)

        case .playerPunch(let p):
            punchFX = PunchFX(type: p.type, start: Date())
            lastPunch = p
            switch p.outcome {
            case .hit:
                opponentHitAt = Date()
                let heavy = p.critical || p.type == .power || p.type == .uppercut || p.damage > 6
                burst(big: heavy, color: p.perfect ? Theme.gold : (p.counter ? Theme.blue : .white))
                number("-\(max(1, Int(p.damage.rounded())))", color: p.critical ? Theme.orange : .white,
                       x: CGFloat.random(in: -0.15...0.15), y: 0.3, size: p.critical ? 44 : 32)
                if p.critical { banner("CRITICAL!", color: Theme.orange, size: 34, duration: 0.8) }
                shakeScreen(min(14, 3 + CGFloat(p.damage) * 1.2))
                sound.play(heavy ? .heavyPunch : .punch)
            case .blocked:
                burst(big: false, color: Theme.blue)
                number("BLOCKED", color: Theme.blue, x: 0, y: 0.3, size: 22)
                sound.play(.block)
            case .dodged:
                number("MISS", color: Theme.textDim, x: 0.1, y: 0.3, size: 24)
                sound.play(.whoosh)
            case .missed:
                number("SLOPPY", color: Theme.textDim, x: -0.1, y: 0.3, size: 22)
                sound.play(.whoosh)
            }

        case .combo(let count, let name):
            if count >= 3 { sound.play(.combo) }
            if count >= 3 || name != nil {
                banner("🔥 \(count) HIT COMBO", subtitle: name, color: Theme.orange, size: 34, duration: 0.9)
            }

        case .comboBroken:
            break

        case .perfectPunch:
            banner("PERFECT!", color: Theme.gold, size: 52, duration: 0.9)
            flashScreen(Theme.gold)
            sound.play(.perfect)

        case .counter(let perfect):
            banner(perfect ? "⚡ PERFECT COUNTER" : "⚡ COUNTER!", color: perfect ? Theme.gold : Theme.blue, size: 44, duration: 1.2)
            flashScreen(Theme.blue)
            sound.play(.counter)

        case .interrupted:
            banner("INTERRUPTED!", color: Theme.orange, size: 30, duration: 0.8)

        case .opponentTelegraph(_, _, let feint):
            if !feint { sound.play(.whoosh) }

        case .feintCancelled:
            break

        case .opponentAttack(_, let result, let damage):
            switch result {
            case .hit:
                playerHitAt = Date()
                flashScreen(Theme.red)
                shakeScreen(min(18, 8 + CGFloat(damage)))
                number("-\(max(1, Int(damage.rounded())))", color: Theme.red, x: 0, y: 0.78, size: 38)
                sound.play(.hurt)
            case .blocked:
                shakeScreen(5)
                number("BLOCKED", color: Theme.blue, x: 0, y: 0.78, size: 24)
                sound.play(.block)
            case .dodged:
                banner("DODGED!", color: Theme.green, size: 34, duration: 0.7)
                sound.play(.whoosh)
            case .ignored:
                break
            }

        case .playerDodge(let side, let success, _):
            if !success { dodgeFX = DodgeFX(side: side, start: Date()) }

        case .playerBlock, .opponentStateChanged:
            break

        case .staminaLow:
            banner("LOW STAMINA", subtitle: "Rest to recover", color: Theme.orange, size: 26, duration: 1.0)

        case .specialReady:
            banner("SPECIAL READY!", subtitle: "Throw a POWER punch or shake", color: Theme.gold, size: 32, duration: 1.6)
            sound.play(.perfect)

        case .specialStarted:
            banner("POWER COMBO!", color: Theme.orange, size: 52, duration: 1.4)
            flashScreen(Theme.orange)
            sound.play(.special)

        case .specialHit(let index, let total, let damage):
            opponentHitAt = Date()
            punchFX = PunchFX(type: index % 2 == 0 ? .cross : .jab, start: Date())
            burst(big: index == total, color: Theme.orange)
            number("-\(max(1, Int(damage.rounded())))", color: Theme.orange, x: CGFloat.random(in: -0.2...0.2), y: 0.3, size: 34 + CGFloat(index) * 2)
            shakeScreen(8 + CGFloat(index) * 2)
            sound.play(.heavyPunch)

        case .specialEnded:
            break

        case .knockdown(let who, _):
            banner("KNOCKDOWN!", color: who == .opponent ? Theme.gold : Theme.red, size: 46, duration: 1.4)
            shakeScreen(16)
            sound.play(.ko)

        case .knockdownCount(let n):
            banner("\(n)", color: .white, size: 100, duration: 0.9)
            sound.play(.tick)

        case .getUp:
            break

        case .ko(let winner):
            koAt = Date()
            banner("K.O.!", subtitle: winner == .player ? "YOU WIN THE ROUND" : "YOU'RE OUT", color: Theme.red, size: 84, duration: 2.6)
            shakeScreen(22)
            sound.play(.ko)

        case .fightEnded(let outcome):
            sound.play(outcome.playerWon ? .victory : .defeat)
            scheduleFinish(outcome)
        }
    }

    // MARK: Finishing

    private func scheduleFinish(_ outcome: FightOutcome) {
        guard !finishing else { return }
        finishing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self else { return }
            self.end()
            self.env.finishFight(outcome, opponent: self.opponent, tier: self.tier)
            self.env.router.replaceTop(with: .result)
        }
    }
}
