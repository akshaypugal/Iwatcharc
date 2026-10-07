import SwiftUI
import WristBoxCore

/// Developer screen for tuning the physical controls: live sensors, the last
/// detected gesture, latency, an event log and the recogniser thresholds.
struct DebugView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var controller: WristController

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private func f(_ v: Double) -> String { String(format: "%+.2f", v) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                ScreenHeader(title: "DEBUG", subtitle: "Tune the controller") { router.pop() }

                connectionCard
                sensorCard
                gestureCard
                latencyCard

                if controller.simulatorEnabled {
                    SimControllerView()
                }

                logCard
                thresholdCard
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            controller.setMode(.fight)           // stream gestures so they show up here
            controller.setDebugStreaming(true)   // and raw sensor values
        }
        .onDisappear {
            controller.setDebugStreaming(false)
            controller.setMode(.off)
        }
    }

    // MARK: Cards

    private var connectionCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("CONNECTION").font(.heavy(12)).foregroundColor(Theme.textDim)
                    Spacer()
                    ConnectionBadge()
                }
                Text(controller.linkState.headline).font(.heavy(18)).foregroundColor(.white)
                row("State", controller.linkState.rawValue)
                row("Watch mode", controller.watchMode.rawValue)
                row("Packets lost", "\(controller.packetsLost)")
                row("Calibrated", env.profile.calibration.isCalibrated ? "yes" : "no")
            }
        }
    }

    private var sensorCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("SENSORS (Watch, device frame)").font(.heavy(12)).foregroundColor(Theme.textDim)
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Accelerometer").font(.heavy(13)).foregroundColor(Theme.gold)
                        Text("X: \(f(controller.rawAccel.x))").font(.mono(14)).foregroundColor(.white)
                        Text("Y: \(f(controller.rawAccel.y))").font(.mono(14)).foregroundColor(.white)
                        Text("Z: \(f(controller.rawAccel.z))").font(.mono(14)).foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gyroscope").font(.heavy(13)).foregroundColor(Theme.gold)
                        Text("X: \(f(controller.rawGyro.x))").font(.mono(14)).foregroundColor(.white)
                        Text("Y: \(f(controller.rawGyro.y))").font(.mono(14)).foregroundColor(.white)
                        Text("Z: \(f(controller.rawGyro.z))").font(.mono(14)).foregroundColor(.white)
                    }
                }
                if !controller.linkState.isConnected {
                    Text("Connect the Watch to see live values.").font(.rounded(12)).foregroundColor(Theme.orange)
                }
            }
        }
    }

    private var gestureCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("DETECTED GESTURE").font(.heavy(12)).foregroundColor(Theme.textDim)
                Text(controller.lastGesture).font(.heavy(30)).foregroundStyle(Theme.fire)
                Text("Confidence: \(Int(controller.lastConfidence * 100))%").font(.mono(14)).foregroundColor(.white)
                Text("Last decision: \(controller.lastDecision)").font(.mono(12)).foregroundColor(Theme.textDim)
            }
        }
    }

    private var latencyCard: some View {
        let l = controller.latency
        return Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("LATENCY").font(.heavy(12)).foregroundColor(Theme.textDim)
                Text("Motion → Game").font(.rounded(13)).foregroundColor(Theme.textDim)
                Text(l.count > 0 ? "\(Int(l.last.rounded())) ms" : "-- ms").font(.heavy(30)).foregroundColor(Theme.green)
                if l.count > 0 {
                    Text("avg \(Int(l.average.rounded())) · min \(Int(l.minimum.rounded())) · max \(Int(l.maximum.rounded())) · p95 \(Int(l.p95.rounded())) ms  (\(l.count) samples)")
                        .font(.mono(11)).foregroundColor(Theme.textDim)
                } else {
                    Text("Throw a punch with the Watch to measure.").font(.rounded(12)).foregroundColor(Theme.textDim)
                }
            }
        }
    }

    private var logCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("EVENT LOG").font(.heavy(12)).foregroundColor(Theme.textDim)
                    Spacer()
                    Button("CLEAR") { controller.clearLog() }
                        .font(.heavy(11)).foregroundColor(Theme.blue)
                }
                if controller.eventLog.isEmpty {
                    Text("No events yet.").font(.rounded(12)).foregroundColor(Theme.textDim)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(controller.eventLog) { entry in
                            Text("\(Self.timeFormat.string(from: entry.time))  \(entry.text)")
                                .font(.mono(12)).foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(height: 170)
            }
        }
    }

    private var thresholdCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("THRESHOLDS (sent to the Watch live)").font(.heavy(12)).foregroundColor(Theme.textDim)
                    Spacer()
                    Button("RESET") {
                        env.updateSettings { $0.gestureConfig = GestureConfig() }
                    }
                    .font(.heavy(11)).foregroundColor(Theme.orange)
                }
                Group {
                    slider("Jab min (g)", \.jabMin, 0.8...4, 0.1)
                    slider("Cross min (g)", \.crossMin, 1.5...7, 0.1)
                    slider("Power min (g)", \.powerMin, 3...12, 0.1)
                    slider("Hook min (g)", \.hookMin, 1...6, 0.1)
                    slider("Hook yaw min (rad/s)", \.hookYawMin, 1...12, 0.25)
                }
                Group {
                    slider("Uppercut min (g)", \.uppercutMin, 0.8...6, 0.1)
                    slider("Dodge min (g)", \.dodgeMin, 0.4...3, 0.05)
                    slider("Jab cooldown (s)", \.jabCooldown, 0.05...0.5, 0.01)
                    slider("Responsiveness (0.2 smooth … 0.95 fast)", \.smoothing, 0.2...0.95, 0.05)
                    slider("Block hold (s)", \.blockHoldTime, 0.1...0.8, 0.02)
                    slider("Block angle (°)", \.blockAngleDegrees, 10...60, 1)
                }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.rounded(13)).foregroundColor(Theme.textDim)
            Spacer()
            Text(value).font(.mono(13)).foregroundColor(.white)
        }
    }

    private func slider(_ title: String, _ keyPath: WritableKeyPath<GestureConfig, Double>,
                        _ range: ClosedRange<Double>, _ step: Double) -> some View {
        let binding = Binding<Double>(
            get: { env.profile.settings.gestureConfig[keyPath: keyPath] },
            set: { v in env.updateSettings { $0.gestureConfig[keyPath: keyPath] = v } })
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.rounded(12)).foregroundColor(.white)
                Spacer()
                Text(String(format: "%.2f", binding.wrappedValue)).font(.mono(12)).foregroundColor(Theme.gold)
            }
            Slider(value: binding, in: range, step: step).tint(Theme.red)
        }
    }
}
