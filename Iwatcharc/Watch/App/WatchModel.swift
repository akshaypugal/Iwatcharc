import Foundation
import Combine
import HealthKit
import WristBoxCore

/// Watch-side coordinator: motion -> gestures -> iPhone, haptics, calibration,
/// connection state and the tiny UI state the Watch shows.
///
/// The Watch is not the game screen. It collects motion, recognises gestures,
/// plays haptics and shows connection / fight state.
final class WatchModel: ObservableObject {
    static let shared = WatchModel()

    // MARK: UI state
    @Published private(set) var connected = false
    @Published private(set) var mode: MotionMode = .off
    @Published private(set) var summary = GameStateSummary()
    @Published private(set) var summaryReceivedAt = Date()
    @Published private(set) var lastGesture = "-"
    @Published private(set) var lastConfidence = 0.0
    @Published private(set) var gestureCount = 0
    @Published private(set) var liveMagnitude = 0.0
    @Published private(set) var calibration: CalibrationProgress?
    @Published private(set) var motionAvailable = true

    // MARK: Pieces
    private let link = WatchLink()
    private let motion = MotionEngine()
    private let workout = WorkoutSessionManager()
    private let runner = CalibrationRunner()

    private let lock = NSLock()
    private var seq = 0
    private var localHaptics = true
    private var debugStream = false
    private var currentMode = MotionMode.off      // mirrors `mode`, readable from the motion queue
    private var lastRawSend = 0.0
    private var lastMeterUpdate = 0.0
    private var heartbeat: Timer?
    private var heartbeatSeq = 0

    private let defaults = UserDefaults.standard
    private enum Key {
        static let calibration = "wristbox.calibration"
        static let config = "wristbox.config"
        static let localHaptics = "wristbox.localHaptics"
    }

    private init() {
        motionAvailable = motion.isAvailable
        loadSaved()
        wireCallbacks()
        link.activate()
        if let ctx = link.lastContext { apply(context: ctx) }
        startHeartbeat()
    }

    // MARK: Setup

    private func loadSaved() {
        var cal = Calibration.default
        var cfg = GestureConfig.default
        if let d = defaults.data(forKey: Key.calibration), let v = try? JSONDecoder().decode(Calibration.self, from: d) { cal = v }
        if let d = defaults.data(forKey: Key.config), let v = try? JSONDecoder().decode(GestureConfig.self, from: d) { cfg = v }
        if defaults.object(forKey: Key.localHaptics) != nil { localHaptics = defaults.bool(forKey: Key.localHaptics) }
        motion.apply(config: cfg, calibration: cal)
    }

    private func wireCallbacks() {
        link.onMessage = { [weak self] dict in
            guard let message = WireMessage(dictionary: dict) else { return }
            DispatchQueue.main.async { self?.handle(message) }
        }
        link.onContext = { [weak self] ctx in
            DispatchQueue.main.async { self?.apply(context: ctx) }
        }
        link.onStatusChange = { [weak self] in
            DispatchQueue.main.async { self?.refreshConnection() }
        }

        motion.onEvents = { [weak self] events in self?.deliver(events) }
        motion.onSample = { [weak self] sample in self?.handle(sample: sample) }
        motion.onDecision = { [weak self] d in self?.report(decision: d) }
        motion.recognizer.onRecenter = { [weak self] calibration in
            guard let self else { return }
            self.persist(calibration: calibration)
            self.link.send(.calibrationResult(calibration))
        }

        runner.onProgress = { [weak self] p in
            guard let self else { return }
            self.link.send(.calibrationProgress(p))
            DispatchQueue.main.async { self.calibration = p }
        }
        runner.onFinished = { [weak self] cal in
            DispatchQueue.main.async { self?.calibrationFinished(cal) }
        }
    }

    private func startHeartbeat() {
        heartbeat?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.beat() }
        RunLoop.main.add(t, forMode: .common)
        heartbeat = t
    }

    private func beat() {
        refreshConnection()
        guard link.isReachable else { return }
        heartbeatSeq += 1
        link.send(.heartbeat(seq: heartbeatSeq, sentTime: Date().timeIntervalSince1970, mode: mode))
    }

    private func refreshConnection() {
        let now = link.isReachable
        if now != connected { connected = now }
    }

    /// App returned to the foreground.
    func becameActive() {
        link.activate()
        refreshConnection()
        // A published context can be older than a forward direction learned this session.
        if !motion.isRunning, let ctx = link.lastContext { apply(context: ctx) }
    }

    // MARK: Incoming from the iPhone

    private func handle(_ message: WireMessage) {
        switch message {
        case .command(let command):
            handle(command)

        case .state(let s):
            summary = s
            summaryReceivedAt = Date()

        case .haptic(let cue):
            WatchHaptics.play(cue)

        case .ping(let id, let sent):
            link.send(.pong(id: id, pingSentTime: sent, watchTime: Date().timeIntervalSince1970))

        default:
            break
        }
    }

    private func handle(_ command: WatchCommand) {
        switch command {
        case .setMode(let m):
            setMode(m)
        case .startCalibration:
            startCalibration()
        case .cancelCalibration:
            runner.cancel()
        case .setDebugStream(let on):
            lock.lock(); debugStream = on; lock.unlock()
        case .setConfig(let cfg):
            persist(config: cfg)
            motion.apply(config: cfg)
        case .setCalibration(let cal):
            persist(calibration: cal)
            motion.apply(calibration: cal)
        case .setLocalHaptics(let on):
            lock.lock(); localHaptics = on; lock.unlock()
            defaults.set(on, forKey: Key.localHaptics)
        }
    }

    private func apply(context: SyncContext) {
        persist(calibration: context.calibration)
        persist(config: context.config)
        lock.lock(); localHaptics = context.localHaptics; lock.unlock()
        motion.apply(config: context.config, calibration: context.calibration)
    }

    private func persist(calibration: Calibration) {
        if let d = try? JSONEncoder().encode(calibration) { defaults.set(d, forKey: Key.calibration) }
    }

    private func persist(config: GestureConfig) {
        if let d = try? JSONEncoder().encode(config) { defaults.set(d, forKey: Key.config) }
    }

    // MARK: Modes

    /// `.fight` streams gestures to the iPhone, `.practice` shows them here only.
    func setMode(_ newMode: MotionMode) {
        // The iPhone repeats its wanted mode whenever settings change; don't restart sensors for that.
        if newMode == mode, newMode == .off || motion.isRunning { return }
        mode = newMode
        lock.lock(); currentMode = newMode; seq = 0; lock.unlock()
        switch newMode {
        case .off:
            summary = GameStateSummary()
            if !runner.isRunning {
                motion.stop()
                workout.stop()
            }
        case .fight, .practice:
            motion.recognitionEnabled = !runner.isRunning
            // The world heading restarts with the sensors: the first punch re-locks "forward".
            motion.apply(requireForwardLock: true)
            motion.resetRecognizer()
            motion.start()
            workout.start()
            gestureCount = 0
        }
    }

    func workoutRequestedByPhone(_ configuration: HKWorkoutConfiguration) {
        workout.start(configuration: configuration)
    }

    // MARK: Calibration

    private func startCalibration() {
        guard motion.isAvailable else {
            link.send(.calibrationProgress(CalibrationProgress(step: .failed, message: "Motion sensors are not available on this Watch.")))
            return
        }
        motion.recognitionEnabled = false
        motion.start()
        workout.start()
        runner.start(at: Date().timeIntervalSince1970)
    }

    private func calibrationFinished(_ cal: Calibration?) {
        motion.recognitionEnabled = true
        if let cal {
            persist(calibration: cal)
            motion.apply(calibration: cal)
            link.send(.calibrationResult(cal))
        }
        if currentMode == .off {
            motion.stop()
            workout.stop()
        }
        // Keep the final progress (done / failed) visible for a moment.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if let c = self?.calibration, c.step == .done || c.step == .failed { self?.calibration = nil }
        }
    }

    // MARK: Motion callbacks (motion queue)

    private func handle(sample: MotionSample) {
        if runner.isRunning { runner.feed(sample) }

        lock.lock()
        let streaming = debugStream
        let m = currentMode
        lock.unlock()

        let now = sample.timestamp
        if streaming, m != .off, now - lastRawSend >= 0.1 {
            lastRawSend = now
            link.send(.rawBatch(RawBatch(samples: [sample])))
        }
        if m == .practice, now - lastMeterUpdate >= 0.1 {
            lastMeterUpdate = now
            let mag = sample.worldAccel.magnitude
            DispatchQueue.main.async { [weak self] in self?.liveMagnitude = mag }
        }
    }

    private func deliver(_ events: [GestureEvent]) {
        lock.lock()
        let m = currentMode
        let haptics = localHaptics
        lock.unlock()
        let sentTime = Date().timeIntervalSince1970

        for event in events {
            if m == .fight {
                lock.lock()
                seq += 1
                let s = seq
                lock.unlock()
                link.send(.gesture(event, seq: s, sensorTime: event.timestamp, sentTime: sentTime))
            }
            if haptics, event.punchResult != nil, m != .off {
                DispatchQueue.main.async { WatchHaptics.tick() }
            }
            let code = event.code
            let conf = event.confidence
            DispatchQueue.main.async { [weak self] in
                self?.lastGesture = code
                self?.lastConfidence = conf
                self?.gestureCount += 1
            }
        }
    }

    private func report(decision: DecisionRecord) {
        lock.lock()
        let streaming = debugStream
        lock.unlock()
        guard streaming else { return }
        link.send(.decision(time: decision.time, label: decision.label, peak: decision.peak, confidence: decision.confidence))
    }
}
