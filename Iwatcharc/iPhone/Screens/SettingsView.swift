import SwiftUI
import WristBoxCore

struct SettingsView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var controller: WristController

    @State private var showCalibration = false
    @State private var confirmReset = false

    private func binding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(get: { env.profile.settings[keyPath: keyPath] },
                set: { value in env.updateSettings { $0[keyPath: keyPath] = value } })
    }

    private func toggle(_ title: String, _ detail: String, _ keyPath: WritableKeyPath<AppSettings, Bool>) -> some View {
        Toggle(isOn: binding(keyPath)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.rounded(16)).foregroundColor(.white)
                Text(detail).font(.rounded(12)).foregroundColor(Theme.textDim)
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: Theme.red))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                ScreenHeader(title: "SETTINGS") { router.pop() }

                section("CONTROLLER") {
                    HStack {
                        ConnectionBadge()
                        Spacer()
                    }
                    HStack {
                        Image(systemName: env.profile.calibration.isCalibrated ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(env.profile.calibration.isCalibrated ? Theme.green : Theme.orange)
                        Text(env.profile.calibration.isCalibrated ? "Calibrated" : "Not calibrated")
                            .font(.rounded(15)).foregroundColor(.white)
                        Spacer()
                    }
                    HStack(spacing: 10) {
                        Button("CALIBRATE") { showCalibration = true }
                            .buttonStyle(SmallButtonStyle(tint: Theme.blue))
                        Button("RESET CALIBRATION") { controller.resetCalibration() }
                            .buttonStyle(SmallButtonStyle(tint: Color.white.opacity(0.2)))
                    }
                    toggle("Developer controller", "On-screen buttons replace the Watch (Simulator friendly)", \.simulatedController)
                    toggle("Instant punch tick on Watch", "The Watch ticks the moment it detects a punch", \.localWatchHaptics)
                    toggle("Mirror hooks", "Swap left and right hook / dodge directions", \.mirrorHooks)
                }

                section("FEEDBACK") {
                    toggle("Sound effects", "Punches, bells and crowd feedback", \.soundEnabled)
                    toggle("Haptics", "Phone and Watch haptic feedback", \.hapticsEnabled)
                }

                section("DEVELOPER") {
                    toggle("Developer mode", "Shows the Debug screen on the home page", \.developerMode)
                    toggle("Latency overlay", "Shows Motion → Game latency during fights", \.showLatency)
                }

                section("DATA") {
                    Button("RESET PROGRESS") { confirmReset = true }
                        .buttonStyle(SmallButtonStyle(tint: Theme.red))
                    Text("Everything is stored on this iPhone. No account, no server, works offline.")
                        .font(.rounded(12)).foregroundColor(Theme.textDim)
                }

                Text("WristBox 1.0 · \"Your wrist. Your fight.\"")
                    .font(.rounded(12)).foregroundColor(Theme.textDim).padding(.top, 6)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showCalibration) {
            ZStack {
                ScreenBackground()
                CalibrationFlowView(onFinished: { showCalibration = false })
            }
            .environmentObject(env)
            .environmentObject(controller)
            .preferredColorScheme(.dark)
        }
        .alert("Reset all progress?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { env.resetProgress() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Level, XP, coins, upgrades and career progress will be erased. Settings and calibration are kept.")
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.heavy(12)).foregroundColor(Theme.textDim).padding(.leading, 4)
            Card {
                VStack(alignment: .leading, spacing: 14) { content() }
            }
        }
    }
}

extension AppSettings {
    /// `mirror` lives inside the gesture config; this exposes it as a plain Bool for the toggle.
    var mirrorHooks: Bool {
        get { gestureConfig.mirror }
        set { gestureConfig.mirror = newValue }
    }
}
