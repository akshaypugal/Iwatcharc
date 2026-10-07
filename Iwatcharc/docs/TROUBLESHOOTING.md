# Troubleshooting

Start with **Settings → Developer mode → Debug**: it shows the connection state, live sensor values, the last
detected gesture (including why a movement was *rejected*), latency and an event log.

## Build and signing

**`xcodegen: command not found`** — `brew install xcodegen`, or run `bash scripts/bootstrap.sh`.

**“Signing for WristBox requires a development team.”** — Select your team under *Signing & Capabilities* for **both**
the `WristBox` and `WristBoxWatch` targets, or set `DEVELOPMENT_TEAM` in `Config/Local.xcconfig` and re-run
`xcodegen generate`.

**“Failed to register bundle identifier.”** — The id is taken. Change `APP_BUNDLE_ID` in `Config/Local.xcconfig` to
something unique and regenerate.

**HealthKit capability / entitlement errors with a free account** — Remove the `entitlements:` blocks and the
`NSHealth…UsageDescription` keys from `project.yml`, regenerate, and delete `WorkoutSessionManager`/`WatchLauncher`
usage if the compiler complains. The game works without them as long as the Watch app stays in the foreground.

**The app expires after 7 days** — Free Apple IDs sign for 7 days. Re-run from Xcode.

**“The package product WristBoxCore requires minimum platform version …”** — Open `project.yml` and make sure the
deployment targets are iOS 16 / watchOS 9 (they are by default).

**Compile errors after the very first build** — The iPhone/Watch sources were written without a compiler. If you hit
one, it is almost certainly a one-line fix; the core package (`Packages/WristBoxCore`) is compiled and tested separately
with `swift test`, so errors can only be in `iPhone/` or `Watch/`.

## Connecting the Watch

**Xcode does not show the Watch.** Unlock the Watch, keep it on your wrist near the iPhone, enable Developer Mode on
both (iPhone *Privacy & Security → Developer Mode*; Watch via the iPhone Watch app), and wait for “Preparing…” to
finish (can take minutes the first time). Matching iOS/watchOS/Xcode versions help.

**The Watch app is not on the Watch.** iPhone *Watch app → My Watch → scroll to WristBox → Show App on Apple Watch*.

**“WATCH DISCONNECTED” in the app.**
1. Is the Watch app **open**? WatchConnectivity messages only flow while both apps are reachable. Open WristBox on the
   Watch; starting a fight also tries to launch it for you (through a HealthKit workout request).
2. Bluetooth/Wi-Fi on, Airplane Mode off, Watch not in Theater/Low Power mode.
3. *Debug → Connection*: `appNotInstalled` means the Watch app is not installed; `notPaired` means no Watch is paired.
4. Fully quit both apps and reopen the Watch app first, then the iPhone app.
The fight pauses automatically when the Watch disconnects and resumes when it is back.

**Latency is high or jumpy** (*Debug → Latency*, or *Settings → Latency overlay*).
* `sendMessage` is as fast as WatchConnectivity gets (typically 20–60 ms). Keep both apps in the foreground.
* The Watch runs recognition itself and sends tiny messages; a high p95 usually means Bluetooth interference or the
  Watch is in Low Power Mode.
* The overlay needs a clock offset; it appears after the first ping/pong (a couple of seconds after connecting).
* The recogniser fires when a punch's peak has passed (≈70–120 ms after the punch starts). That is inherent; raising
  *Responsiveness* slightly can shave a few ms (see TUNING.md).

## Motion and gestures

**The Watch stops sending punches when I lower my arm.** watchOS suspends apps when the wrist drops. WristBox keeps
running through a boxing *workout session*; allow the Health prompt on the Watch and do not force-quit the Watch app.
Without HealthKit, keep the Watch awake: *Watch Settings → General → Wake Screen → Wake Duration → On Tap → 70 seconds*.

**Nothing is detected at all.**
* *Debug → Sensors* shows live values only when the Watch app is running in fight/practice mode (opening Debug does that).
  Flat zeros mean the Watch is not sending: re-open the Watch app.
* On the Watch tap **PRACTICE** and punch: it shows the detected gesture without the iPhone.
* Re-calibrate (*Settings → Calibrate*). The calibration “forward” direction is re-learned from your first punch of every
  fight, so throw a normal jab as soon as the countdown starts.

**Punches are detected as the wrong type.**
* Jab vs cross vs power is decided by punch strength (g). Tune *Jab/Cross/Power min* in Debug.
* Hooks vs dodges are decided by wrist rotation: *Hook yaw min* higher = harder to trigger hooks.
* Left/right hooks feel swapped? *Settings → Mirror hooks*.

**Block never triggers / always triggers.** The block pose is the *guard* you calibrated. It needs ≈0.2 s of stillness
within *Block angle* degrees. Increase *Block angle* if it never triggers; re-calibrate with fists clearly higher than your
resting pose if it triggers while idle.

**Tiny wrist flicks count as punches.** Raise *Jab min*. The anti-cheat also enforces a minimum speed, a per-gesture
cooldown, a retract filter and at most 6 punches/second, and stamina makes spamming ineffective.

**Punches are missed during fast combos.** Lower *Jab cooldown* (min 0.05 s) and raise *Responsiveness*. Very fast combos are limited by `maxPunchesPerSecond` in `GestureConfig`.

**Everything works but the first punch of each fight is “lost”.** The first strong horizontal punch locks in the forward
direction (CoreMotion's heading restarts with the sensors); it still counts as a punch. If you start with a hook or a
dodge it can lock the wrong direction; the app re-centres itself after two consistent rejected punches.

## Game

**The Watch buzzes but the iPhone shows nothing (or the reverse).** Check *Settings → Haptics/Sound*, the silent switch
(sound effects use the ambient category and respect it), and *Debug → Event log* to see what arrived.

**“No controller connected” when starting a fight.** Connect the Watch, or accept *Use Developer Controller*.

**I lost my progress.** Everything is in `Application Support/WristBox/profile.json` on the iPhone. A corrupt file is
moved aside as `profile.corrupt-<time>.json` (never deleted) and the app starts fresh.

**Simulator: keyboard shortcuts do nothing.** Click the Simulator window, enable *I/O → Keyboard → Connect Hardware Keyboard*.

## Still stuck?

Collect: iOS/watchOS/Xcode versions, the *Debug* screen (connection state + last decision lines), and Xcode's console
output. Core logic can be exercised without any hardware: `cd Packages/WristBoxCore && swift test`.
