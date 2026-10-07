import SwiftUI
import WristBoxCore

/// Calibration and the first-punch test, used by onboarding and by Settings.
///
///   1. Keep your wrist still      -> acceleration baseline, orientation, gyro baseline
///   2. Raise your guard and hold  -> block pose
///   3. Throw a punch              -> forward direction
///   4. Throw another punch        -> "Perfect! You're ready." (real detection test)
struct CalibrationFlowView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var controller: WristController

    var onFinished: () -> Void
    var onSkip: (() -> Void)?

    private enum Stage { case intro, calibrating, test, done }

    @State private var stage = Stage.intro
    @State private var testResult: GestureEvent?
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 10)
            switch stage {
            case .intro: intro
            case .calibrating: calibrating
            case .test: test
            case .done: done
            }
            Spacer(minLength: 10)
        }
        .padding(.horizontal, 24)
        .onChange(of: controller.calibrationProgress?.step) { step in
            if step == .done, stage == .calibrating {
                beginTest()
            }
        }
        .onDisappear {
            if stage != .intro {
                controller.onGesture = nil
                controller.setMode(.off)
            }
        }
    }

    // MARK: Stages

    private var intro: some View {
        VStack(spacing: 18) {
            Text("⌚️").font(.system(size: 64))
            Text("Put your watch on your dominant wrist.")
                .font(.heavy(24)).foregroundColor(.white).multilineTextAlignment(.center)
            Text("Open WristBox on your Apple Watch and keep the screen awake. Then we calibrate in three quick steps.")
                .font(.rounded(15)).foregroundColor(Theme.textDim).multilineTextAlignment(.center)
            ConnectionBadge()

            Button("LET'S CALIBRATE") { start() }
                .buttonStyle(BigButtonStyle())
                .disabled(!controller.linkState.isConnected)
                .opacity(controller.linkState.isConnected ? 1 : 0.5)

            if !controller.linkState.isConnected {
                Text(controller.linkState.detail).font(.rounded(13)).foregroundColor(Theme.orange)
                    .multilineTextAlignment(.center)
            }
            if let skip = onSkip {
                Button("Skip - use the developer controller instead") {
                    env.updateSettings { $0.simulatedController = true }
                    skip()
                }
                .font(.rounded(14)).foregroundColor(Theme.textDim)
            }
        }
    }

    @ViewBuilder
    private var calibrating: some View {
        let p = controller.calibrationProgress
        switch p?.step {
        case .neutral?:
            stepView(emoji: "🧘", title: "Keep your wrist still", detail: p?.message ?? "Hands relaxed at your side.", progress: p)
        case .guardPose?:
            stepView(emoji: "🛡", title: "Raise your guard", detail: p?.message ?? "Hold your fists up like you're defending. Stay still.", progress: p)
        case .punch?:
            VStack(spacing: 16) {
                Text("🥊").font(.system(size: 80)).scaleEffect(pulse ? 1.25 : 0.9)
                    .onAppear { withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) { pulse = true } }
                Text("Throw a punch!").font(.heavy(34)).foregroundColor(.white)
                Text(p?.message ?? "Face your opponent and punch straight ahead.")
                    .font(.rounded(15)).foregroundColor(Theme.textDim).multilineTextAlignment(.center)
            }
        case .failed?:
            VStack(spacing: 16) {
                Text("⚠️").font(.system(size: 56))
                Text("Let's try again").font(.heavy(26)).foregroundColor(.white)
                Text(p?.message ?? "Something went wrong.").font(.rounded(15)).foregroundColor(Theme.orange)
                    .multilineTextAlignment(.center)
                Button("RETRY") { start() }.buttonStyle(BigButtonStyle()).padding(.horizontal, 30)
            }
        default:
            VStack(spacing: 14) {
                ProgressView().tint(.white)
                Text("Waiting for your Watch...").font(.rounded(16)).foregroundColor(Theme.textDim)
            }
        }
    }

    private func stepView(emoji: String, title: String, detail: String, progress: CalibrationProgress?) -> some View {
        VStack(spacing: 16) {
            Text(emoji).font(.system(size: 64))
            Text(title).font(.heavy(30)).foregroundColor(.white).multilineTextAlignment(.center)
            Text(detail).font(.rounded(15)).foregroundColor(Theme.textDim).multilineTextAlignment(.center)
            ZStack {
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: CGFloat(progress?.progress ?? 0))
                    .stroke(Theme.fire, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(max(0, progress?.secondsLeft ?? 0))").font(.heavy(64)).foregroundColor(.white)
            }
            .frame(width: 150, height: 150)
        }
    }

    private var test: some View {
        VStack(spacing: 18) {
            if let r = testResult {
                Text("🎉").font(.system(size: 64))
                Text("Perfect!").font(.heavy(44)).foregroundStyle(Theme.fire)
                Text("You're ready.").font(.heavy(24)).foregroundColor(.white)
                if let punch = r.punchResult {
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(punch.type.displayName).font(.heavy(18)).foregroundColor(Theme.gold)
                            HStack {
                                Text("Power \(Int(punch.power * 100))%")
                                Spacer()
                                Text("Accuracy \(Int(punch.accuracy * 100))%")
                                Spacer()
                                Text("Speed \(Int(punch.speed * 100))%")
                            }
                            .font(.heavy(12)).foregroundColor(.white)
                        }
                    }
                } else {
                    Text(r.code).font(.heavy(18)).foregroundColor(Theme.gold)
                }
                Button("START BOXING") { finish() }.buttonStyle(BigButtonStyle())
            } else {
                Text("🥊").font(.system(size: 64)).scaleEffect(pulse ? 1.2 : 0.95)
                    .onAppear { withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { pulse = true } }
                Text("Now throw a jab").font(.heavy(32)).foregroundColor(.white)
                Text("Let's make sure it's detected. Punch straight ahead.")
                    .font(.rounded(15)).foregroundColor(Theme.textDim).multilineTextAlignment(.center)
                Text("Last: \(controller.lastGesture)").font(.mono(13)).foregroundColor(Theme.textDim)
                Button("Skip test") { finish() }.font(.rounded(14)).foregroundColor(Theme.textDim)
            }
        }
    }

    private var done: some View {
        VStack(spacing: 16) {
            Text("✅").font(.system(size: 64))
            Text("Calibrated").font(.heavy(30)).foregroundColor(.white)
            Button("DONE") { finish() }.buttonStyle(BigButtonStyle())
        }
    }

    // MARK: Actions

    private func start() {
        stage = .calibrating
        controller.startCalibration()
    }

    private func beginTest() {
        testResult = nil
        pulse = false
        stage = .test
        controller.onGesture = { event in
            // Any punch proves the whole chain works.
            if event.punchResult != nil, testResult == nil {
                testResult = event
                env.haptics.play(.perfectPunch)
                controller.sendHaptic(.perfectPunch)
            }
        }
        controller.setMode(.fight)
    }

    private func finish() {
        controller.onGesture = nil
        controller.setMode(.off)
        controller.clearCalibrationStatus()
        onFinished()
    }
}

struct OnboardingView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var started = false

    var body: some View {
        ZStack {
            ScreenBackground()
            if started {
                CalibrationFlowView(onFinished: complete, onSkip: complete)
            } else {
                VStack(spacing: 20) {
                    Spacer()
                    Text("WELCOME TO").font(.heavy(18)).foregroundColor(Theme.textDim)
                    Text("WRISTBOX").font(.heavy(56)).foregroundStyle(Theme.fire)
                    Text("Your Apple Watch is your controller.")
                        .font(.rounded(18)).foregroundColor(.white).multilineTextAlignment(.center)
                    Text("🥊").font(.system(size: 90))
                    Spacer()
                    Button("GET STARTED") { started = true }
                        .buttonStyle(BigButtonStyle())
                        .padding(.horizontal, 30)
                    Button("Skip for now") { complete() }
                        .font(.rounded(14)).foregroundColor(Theme.textDim)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private func complete() {
        var p = env.profile
        p.hasOnboarded = true
        env.profile = p
    }
}
