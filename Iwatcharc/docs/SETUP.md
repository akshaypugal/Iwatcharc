# Setup

## What you need

| Thing | Why |
|---|---|
| A Mac with **Xcode 15 or newer** | The iPhone/Watch apps can only be built with Xcode. |
| An **iPhone** (iOS 16+) paired with an **Apple Watch** (watchOS 9+) | Real play. Not needed for Simulator/Developer Controller mode. |
| A (free) **Apple ID** added to Xcode | Signing. A free account works for personal devices (apps expire after 7 days; just re-run). |
| Homebrew | Installs XcodeGen. |

Watch models: any Apple Watch that runs watchOS 9 has the accelerometer and gyroscope used here
(Series 4 and later). The Apple Watch SE and Series 6+ are the best candidates for low-latency play.

## 1. Get the code onto the Mac

You developed on another machine, so push the folder to git and clone it on the Mac:

```bash
git clone <your repo url> wristbox && cd wristbox
```

## 2. Generate the Xcode project

```bash
bash scripts/bootstrap.sh
```

This installs XcodeGen (if missing), runs the 173 core unit tests, generates `WristBox.xcodeproj`
and opens it. (The `.xcodeproj` is generated on purpose: `project.yml` is the single source of truth and
merges cleanly in git.)

Set a unique bundle id **before** building. Edit `Config/Local.xcconfig` (the script creates it from the
example):

```
APP_BUNDLE_ID = com.yourname.wristbox
DEVELOPMENT_TEAM = ABCDE12345      # optional; or choose the team in Xcode
```

then run `xcodegen generate` again. The Watch app automatically uses `<APP_BUNDLE_ID>.watchkitapp`.

## 3. Run it

### On your iPhone and Apple Watch

1. Connect the iPhone with a cable, trust the computer.
2. **Developer Mode** on the iPhone: *Settings → Privacy & Security → Developer Mode* → On (restarts).
3. **Developer Mode** on the Watch: iPhone *Watch app → Privacy & Security → Developer Mode* → On (restarts).
   (It only appears after the iPhone is in developer mode and Xcode has seen the Watch.)
4. In Xcode: *Window → Devices and Simulators*. The iPhone and, beneath it, the paired Watch should appear.
   Wait until the Watch finishes “Preparing…”.
5. Select the **WristBox** scheme, choose your iPhone as the destination, press **Run** (⌘R).
   For both targets, *Signing & Capabilities → Team* must be set (or `DEVELOPMENT_TEAM` in `Local.xcconfig`).
6. The Watch app is embedded and installs on the Watch through the iPhone. If it does not show up on the
   Watch: iPhone *Watch app → My Watch → WristBox → Show App on Apple Watch*.
7. Debugging the Watch code: switch the scheme to **WristBoxWatch**, destination “iPhone + Apple Watch”.

### First launch (onboarding)

1. **Open WristBox on the Watch** and keep the screen awake.
2. On the iPhone: *GET STARTED → LET'S CALIBRATE*.
3. Follow the three steps (the Watch shows the same prompts):
   * **Keep your wrist still** (3-2-1) — acceleration baseline, orientation, gyro baseline.
   * **Raise your guard** and hold — the block pose.
   * **Throw a punch** — the forward direction.
4. Throw one more punch: *Perfect! You're ready.*

Calibration is stored on the iPhone and pushed to the Watch. *Settings → Calibrate / Reset calibration* repeats it.

### In the Simulator (no Watch)

Pick any iPhone simulator and Run. The app starts in **Developer Controller Mode**: the fight screen shows the
button grid. With a hardware keyboard: `J` jab, `K` cross, `U` left hook, `I` right hook, `O` uppercut,
`A` dodge left, `D` dodge right, `S` toggle block, `P` power, `Space` special.
The same mode can be switched on with *Settings → Developer controller* on a real device.

## Safe to run from the command line (no Xcode UI)

```bash
# Core unit tests (macOS, Linux, or Docker)
cd Packages/WristBoxCore && swift test

# Whole project builds, like CI does
xcodegen generate
xcodebuild build -project WristBox.xcodeproj -scheme WristBox -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild build -project WristBox.xcodeproj -scheme WristBoxWatch -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild test  -project WristBox.xcodeproj -scheme WristBox -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO
```

## No Mac? Use CI to compile

`.github/workflows/ci.yml` runs on every push:

* **core-tests** (Ubuntu, `swift:5.10`): the 173 core tests.
* **apps** (macOS runner): XcodeGen, core tests, builds the iPhone app (with the embedded Watch app) and the
  Watch app for the simulators, and runs the iPhone unit tests.

A green run means the project compiles. CI cannot run the app on a physical Watch, so **real-world testing
and gesture tuning still need a Mac + iPhone + Watch** (see [TUNING.md](TUNING.md)).
To install on devices without a Mac you would need a signed `.ipa` built on a Mac or a macOS CI runner with
signing certificates; that is outside this MVP.

## Optional: HealthKit

The Watch app starts a *boxing workout session* while fighting. That is the supported way to keep the app
(and its motion sensors) running when your wrist moves or the screen dims. Nothing is written to Apple
Health (the workout is discarded). The first fight asks for Health permission on the Watch; allow it.

If your signing setup does not allow the HealthKit capability, remove the `entitlements:` blocks in
`project.yml` and the HealthKit usage strings; everything still works while the Watch app stays in the
foreground (tap the screen to keep it awake) — see [TROUBLESHOOTING.md](TROUBLESHOOTING.md#the-watch-stops-sending-punches-when-i-lower-my-arm).
