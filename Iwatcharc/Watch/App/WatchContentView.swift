import SwiftUI
import WristBoxCore

/// The Watch UI is deliberately tiny:
///
///     WRISTBOX             ROUND 1
///     ● CONNECTED            42s
///     READY                🥊 FIGHT
struct WatchContentView: View {
    @ObservedObject private var model = WatchModel.shared

    var body: some View {
        Group {
            if let c = model.calibration, c.step != .idle {
                CalibrationWatchView(progress: c)
            } else if model.mode == .fight, model.summary.phase != .idle {
                FightWatchView(model: model)
            } else if model.mode == .practice {
                PracticeWatchView(model: model)
            } else {
                IdleWatchView(model: model)
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.mode)
    }
}

private let fire = LinearGradient(colors: [Color(red: 1, green: 0.78, blue: 0.34), Color.orange, Color.red],
                                  startPoint: .top, endPoint: .bottom)

struct ConnectionDot: View {
    let connected: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(connected ? Color.green : Color.red).frame(width: 8, height: 8)
            Text(connected ? "CONNECTED" : "NOT CONNECTED")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundColor(connected ? .green : .red)
        }
    }
}

// MARK: - Idle

struct IdleWatchView: View {
    @ObservedObject var model: WatchModel

    var body: some View {
        VStack(spacing: 6) {
            Text("WRISTBOX")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(fire)
            ConnectionDot(connected: model.connected)
            Text("READY")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            if !model.motionAvailable {
                Text("No motion sensors").font(.system(size: 11)).foregroundColor(.orange)
            } else if !model.connected {
                Text("Open WristBox on your iPhone").font(.system(size: 11)).foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            Button("PRACTICE") { model.setMode(.practice) }
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .tint(.red)
                .disabled(!model.motionAvailable)
        }
    }
}

// MARK: - Fight

struct FightWatchView: View {
    @ObservedObject var model: WatchModel

    var body: some View {
        let s = model.summary
        VStack(spacing: 4) {
            switch s.phase {
            case .countdown:
                Text("ROUND \(s.round)").font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundColor(.yellow)
                Text("GET READY").font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundColor(.white)
            case .fighting:
                Text("ROUND \(s.round)").font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundColor(.yellow)
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    let left = max(0, s.remaining - Date().timeIntervalSince(model.summaryReceivedAt))
                    Text("\(Int(left.rounded(.up)))s")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                }
                Text("🥊 FIGHT").font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(fire)
            case .knockdown:
                Text("KNOCKDOWN").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundColor(.red)
            case .roundEnd:
                Text("ROUND OVER").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundColor(.yellow)
            case .fightOver:
                Text("FIGHT OVER").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundColor(.white)
            case .idle:
                EmptyView()
            }
            if s.combo >= 2 {
                Text("COMBO x\(s.combo)")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(.orange)
            }
            if s.specialReady {
                Text("⚡ SPECIAL READY")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(.yellow)
            }
            ConnectionDot(connected: model.connected)
        }
    }
}

// MARK: - Practice

/// Shows what the Watch recognises, without needing the iPhone: handy for
/// feeling out the gestures before a fight.
struct PracticeWatchView: View {
    @ObservedObject var model: WatchModel

    var body: some View {
        VStack(spacing: 4) {
            Text("PRACTICE").font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundColor(.yellow)
            Text(model.lastGesture.replacingOccurrences(of: "_", with: " "))
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(fire)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("\(Int(model.lastConfidence * 100))% · \(model.gestureCount) detected")
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(.gray)
            ProgressView(value: min(1, model.liveMagnitude / 6))
                .tint(.orange)
            Button("STOP") { model.setMode(.off) }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .tint(.red)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Calibration

struct CalibrationWatchView: View {
    let progress: CalibrationProgress

    private var title: String {
        switch progress.step {
        case .neutral: return "KEEP STILL"
        case .guardPose: return "GUARD UP"
        case .punch: return "PUNCH!"
        case .done: return "CALIBRATED"
        case .failed: return "TRY AGAIN"
        case .idle: return ""
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(fire)
            if progress.step == .neutral || progress.step == .guardPose {
                Text("\(progress.secondsLeft)")
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            } else if progress.step == .punch {
                Text("🥊").font(.system(size: 44))
            } else if progress.step == .done {
                Text("✅").font(.system(size: 44))
            }
            Text(progress.message)
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 4)
    }
}
