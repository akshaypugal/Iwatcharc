import Foundation
import Combine
import WristBoxCore

/// The game's single source of input: the Apple Watch (or, in Developer
/// Controller Mode, on-screen buttons that produce exactly the same events).
///
///     Watch motion -> gesture recognition (on the Watch) -> WatchConnectivity
///                                                              |
///     Simulator buttons ---------------------------------------+--> WristController --> onGesture --> boxing game
///
/// The game only ever sees `GestureEvent`s.
final class WristController: ObservableObject {
    struct LogEntry: Identifiable {
        let id = UUID()
        let time: Date
        let text: String
    }

    // MARK: Published state (for UI and the Debug screen)
    @Published private(set) var linkState: LinkState = .inactive
    @Published private(set) var lastGesture = "-"
    @Published private(set) var lastConfidence = 0.0
    @Published private(set) var latency = LatencyStats()
    @Published private(set) var eventLog: [LogEntry] = []
    @Published private(set) var rawAccel = Vec3.zero
    @Published private(set) var rawGyro = Vec3.zero
    @Published private(set) var lastDecision = "-"
    @Published private(set) var calibrationProgress: CalibrationProgress?
    @Published private(set) var watchMode: MotionMode = .off
    @Published private(set) var packetsLost = 0
    @Published private(set) var debugStreaming = false
    /// Developer Controller Mode: on-screen buttons replace the Watch.
    @Published var simulatorEnabled = false

    // MARK: Hooks
    /// The single consumer of gestures (the active fight, or the onboarding test).
    var onGesture: ((GestureEvent) -> Void)?
    /// The Watch went away.
    var onLinkLost: (() -> Void)?
    /// A new calibration arrived from the Watch (or was reset).
    var onCalibration: ((Calibration) -> Void)?
    /// Supplies calibration / thresholds to push to the Watch.
    var syncProvider: (() -> SyncContext)?

    // MARK: Internals
    private let link = PhoneLink()
    private var monitor = ConnectionMonitor()
    private var clock = ClockSync()
    private var latencyTracker = LatencyTracker()
    private var sim = SimulatedController(seed: UInt64.random(in: 1...UInt64.max))
    private var timer: Timer?
    private var tickCount = 0
    private var lastSeq = -1
    private var pingID = 0
    private var wantedMode: MotionMode = .off
    private var wantDebug = false

    init() {
        link.onMessage = { [weak self] dict in
            let received = Date().timeIntervalSince1970
            DispatchQueue.main.async { self?.handle(dict, receivedAt: received) }
        }
        link.onStatusChange = { [weak self] in
            DispatchQueue.main.async { self?.refreshLink() }
        }
    }

    // MARK: Lifecycle

    /// Activates WatchConnectivity and starts the 1 Hz housekeeping timer.
    func start() {
        link.activate()
        refreshLink()
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// App returned to the foreground: re-activate and re-evaluate the link.
    func appBecameActive() {
        link.activate()
        refreshLink()
        syncToWatch()
    }

    private func tick() {
        tickCount += 1
        refreshLink()
        if linkState.isConnected, !clock.isSynced || tickCount % 5 == 0 { sendPing() }
    }

    private func sendPing() {
        pingID += 1
        link.send(.ping(id: pingID, sentTime: Date().timeIntervalSince1970))
    }

    private func refreshLink() {
        let s = link.status
        let now = Date().timeIntervalSince1970
        monitor.update(supported: s.supported, paired: s.paired, appInstalled: s.installed,
                       activated: s.activated, reachable: s.reachable, now: now)
        let state = monitor.state(now: now)
        guard state != linkState else { return }
        let was = linkState
        linkState = state
        if was.isConnected, !state.isConnected {
            log("Watch disconnected")
            onLinkLost?()
        } else if !was.isConnected, state.isConnected {
            log("Watch connected")
            lastSeq = -1
            syncToWatch()
            sendPing()
        }
    }

    /// Pushes calibration, thresholds, mode and debug streaming to the Watch.
    func syncToWatch() {
        if let ctx = syncProvider?() {
            link.publishContext(ctx)
            guard linkState.isConnected else { return }
            link.send(.command(.setCalibration(ctx.calibration)))
            link.send(.command(.setConfig(ctx.config)))
            link.send(.command(.setLocalHaptics(ctx.localHaptics)))
        }
        guard linkState.isConnected else { return }
        if wantedMode != .off { link.send(.command(.setMode(wantedMode))) }
        link.send(.command(.setDebugStream(wantDebug)))
    }

    // MARK: Commands to the Watch

    var isWatchConnected: Bool { linkState.isConnected }

    /// True when gestures can arrive (real Watch or simulated buttons).
    var hasController: Bool { linkState.isConnected || simulatorEnabled }

    func setMode(_ mode: MotionMode) {
        wantedMode = mode
        link.send(.command(.setMode(mode)))
        // Watch app asleep? Ask the system to launch it (it starts a boxing workout so it stays alive).
        if mode != .off, !linkState.isConnected {
            let s = link.status
            if s.paired, s.installed { WatchLauncher.launch() }
        }
    }

    func setDebugStreaming(_ on: Bool) {
        wantDebug = on
        debugStreaming = on
        link.send(.command(.setDebugStream(on)))
    }

    func pushConfig(_ config: GestureConfig) {
        link.send(.command(.setConfig(config)))
        if let ctx = syncProvider?() { link.publishContext(ctx) }
    }

    func sendHaptic(_ cue: HapticCue) {
        guard linkState.isConnected else { return }
        link.send(.haptic(cue))
    }

    func sendState(_ summary: GameStateSummary) {
        guard linkState.isConnected else { return }
        var s = summary
        s.sentTime = Date().timeIntervalSince1970
        link.send(.state(s))
    }

    // MARK: Calibration

    /// Starts the three-step calibration on the Watch: neutral pose (acceleration,
    /// orientation and gyro baselines), guard pose, then a reference punch.
    func startCalibration() {
        guard linkState.isConnected else {
            calibrationProgress = CalibrationProgress(step: .failed, message: "Watch not connected. Open WristBox on your Watch and keep it awake.")
            return
        }
        calibrationProgress = CalibrationProgress(step: .neutral, progress: 0, secondsLeft: 3, message: "Keep your wrist still")
        link.send(.command(.startCalibration))
    }

    func cancelCalibration() {
        link.send(.command(.cancelCalibration))
        calibrationProgress = nil
    }

    func clearCalibrationStatus() { calibrationProgress = nil }

    /// Back to factory calibration.
    func resetCalibration() {
        onCalibration?(.default)
        link.send(.command(.setCalibration(.default)))
        calibrationProgress = nil
    }

    // MARK: Simulated controller

    func simulate(_ input: SimulatedInput) {
        ingest(sim.event(for: input), source: "SIM")
    }

    func simulateBlock(pressed: Bool) {
        ingest(pressed ? sim.event(for: .block) : sim.releaseBlock(), source: "SIM")
    }

    // MARK: Incoming

    private func handle(_ dict: [String: Any], receivedAt: Double) {
        guard let message = WireMessage(dictionary: dict) else { return }
        monitor.heard(at: receivedAt)
        switch message {
        case .gesture(let event, let seq, let sensorTime, _):
            if lastSeq >= 0, seq > lastSeq + 1 { packetsLost += seq - lastSeq - 1 }
            lastSeq = seq
            ingest(event, source: "WATCH")
            if clock.isSynced {
                let applied = Date().timeIntervalSince1970
                latencyTracker.record(milliseconds: (applied - clock.toPhoneTime(sensorTime)) * 1000)
                latency = latencyTracker.stats
            }

        case .heartbeat(_, _, let mode):
            watchMode = mode

        case .pong(_, let pingSent, let watchTime):
            clock.addSample(pingSent: pingSent, watchTime: watchTime, pongReceived: receivedAt)

        case .calibrationProgress(let p):
            calibrationProgress = p

        case .calibrationResult(let c):
            if let p = calibrationProgress, p.step != .done, p.step != .idle, p.step != .failed {
                calibrationProgress = CalibrationProgress(step: .done, progress: 1, message: "Calibrated")
            }
            onCalibration?(c)

        case .rawBatch(let batch):
            if let last = batch.last {
                rawAccel = last.accel
                rawGyro = last.gyro
            }

        case .decision(_, let label, _, let confidence):
            lastDecision = "\(label)  \(Int(confidence * 100))%"

        default:
            break
        }
        refreshLink()
    }

    private func ingest(_ event: GestureEvent, source: String) {
        lastGesture = event.code
        lastConfidence = event.confidence
        log("\(event.code)  \(Int(event.confidence * 100))%  [\(source)]")
        onGesture?(event)
    }

    private func log(_ text: String) {
        eventLog.insert(LogEntry(time: Date(), text: text), at: 0)
        if eventLog.count > 120 { eventLog.removeLast(eventLog.count - 120) }
    }

    func clearLog() {
        eventLog.removeAll()
        packetsLost = 0
        latencyTracker.reset()
        latency = LatencyStats()
    }
}
