# Architecture

The system is split into layers that only talk through small, high-level types. The boxing game never
sees a sensor; the sensor code never knows what a "damage" is.

```
Motion Layer ─► Gesture Layer ─► Communication Layer ─► Game Controller ─► Boxing Game ─► UI
 (Watch)         (Watch)          (WatchConnectivity)     (iPhone)          (core)       (SwiftUI)
 CoreMotion      WristBoxCore     WireMessage             WristController   FightEngine  FightView
 MotionSample    GestureRecognizer                        GestureEvent      OpponentAI
```

## Modules

| Module | Frameworks | Contents |
|---|---|---|
| `WristBoxCore` (Swift package) | Foundation only | everything testable: motion math, gesture engine, game engine, AI, progression, persistence, wire protocol |
| `WristBox` (iPhone app) | SwiftUI, Combine, AVFoundation, WatchConnectivity, HealthKit | UI, `WristController`, `PhoneLink`, sound/haptics, view models |
| `WristBoxWatch` (Watch app) | SwiftUI, CoreMotion, WatchConnectivity, HealthKit, WatchKit | `MotionEngine`, `WatchLink`, calibration runner, workout session, haptics, tiny UI |

Because `WristBoxCore` depends on Foundation only, it compiles and tests on macOS, Linux and Windows toolchains.
That is how this project was developed without Xcode, and it keeps the game engine free of platform concerns.

## 1. Motion layer (Watch)

`Watch/Motion/MotionEngine.swift` is the only code that touches Core Motion.
It converts each `CMDeviceMotion` into a `MotionSample`:

| Field | Meaning |
|---|---|
| `userAccel` | acceleration without gravity, device frame, g |
| `gravity` | gravity direction, device frame |
| `rotationRate` | gyro, device frame, rad/s |
| `worldAccel` | `userAccel` in a world frame (z up) using the attitude matrix |
| `timestamp` | wall-clock time (boot-relative CoreMotion time + boot offset) |

`WorldFrameMapper` (core) converts device → world. Whether `CMRotationMatrix` maps world→device or device→world is easy
to get backwards, so the mapper tests both conventions against the measured gravity vector and locks the one that agrees.

Sensors run at 100 Hz, only while a fight/practice/calibration is active (battery), on a dedicated serial queue.

## 2. Gesture layer (core, runs on the Watch)

`GestureRecognizer.process(_ sample:) -> [GestureEvent]` is a state machine:

```
raw sample
  → noise filtering        median-of-3 (kills one-sample spikes) + EMA smoothing
  → baseline calibration   gyro bias removed; yaw = rotation about the vertical axis
  → motion vector          world accel → player coordinates (forward / lateral / vertical) via Calibration
  → peak detection         burst starts above a threshold; classification fires when the magnitude falls
                           to 72 % of its peak (≈ 70–120 ms into the punch - low latency)
  → direction detection    magnitude-weighted unit direction of the burst
  → classification         GestureClassifier (pure function, directly unit-tested)
  → validation             per-gesture cooldown, ≤ 6 punches/s, retract filter, shake lockout, confidence floor
  → GestureEvent
```

Classification rules (all thresholds live in `GestureConfig`):

| Dominant direction | Extra condition | Gesture |
|---|---|---|
| up | peak ≥ uppercutMin | `UPPERCUT` |
| sideways | yaw rate ≥ hookYawMin | `LEFT_HOOK` / `RIGHT_HOOK` |
| sideways | low rotation, moderate peak | `DODGE_LEFT` / `DODGE_RIGHT` |
| forward | peak ≥ powerMin / crossMin / jabMin | `POWER_PUNCH` / `CROSS` / `JAB` |
| backward / down / diagonal | – | rejected (`wrongDirection`, `ambiguous`) |

Separately a `BlockDetector` emits `BLOCK` / `BLOCK_END` when gravity is within an angle of the calibrated guard pose and
the wrist is still for 0.2 s. Several strong, similar, alternating bursts on one axis emit `GUARD_BREAK` (shake).

**Quality scores** (`PunchResult`): `power` (peak vs a per-type reference blended with integrated hand speed),
`accuracy` (how well the direction matches the ideal axis; sloppy punches whiff in the game), `speed`, `confidence`.

**Anti-cheat**: minimum peak, minimum speed, maximum plausible peak (24 g), min/max burst duration, per-type cooldown
(jab 120 ms), rolling-second punch cap, retract rejection, direction validation, confidence floor. Stamina in the game
makes spamming ineffective on top of that.

**Heading recovery**: CoreMotion's world heading is arbitrary and changes each time the sensors restart, so the calibrated
“forward” can be stale. The recogniser therefore (a) *locks in* forward from the first strong horizontal punch of each
session (that punch still counts) and (b) *re-centres* after two consistent strong punches that were rejected as
backwards/ambiguous (retracts are excluded). Both are unit-tested.

**Calibration** (`CalibrationBuilder`, driven by `CalibrationRunner` on the Watch): neutral pose (acceleration baseline,
orientation, gyro baseline, noise floor), guard pose, reference punch (forward axis). Stored on the iPhone in the profile
and pushed to the Watch (`SyncContext` via `updateApplicationContext`, so the Watch has it even before the app runs).
`controller.startCalibration()` / `controller.resetCalibration()` are `WristController` methods.

## 3. Communication layer

`WireMessage` (core) is a plist-safe dictionary protocol (`gesture`, `heartbeat`, `ping/pong`, `state`, `haptic`,
`command`, `calibration…`, `rawBatch`, `decision`). Unknown/malformed messages decode to `nil`, never crash.

* Gestures use `sendMessage` (immediate); if the iPhone is unreachable they are dropped (stale punches are worthless).
* Calibration/thresholds also go through `updateApplicationContext` so they survive restarts.
* `ConnectionMonitor` (pure, tested) decides the shown state: unsupported / notPaired / appNotInstalled / inactive /
  disconnected / connected, from reachability **and** heartbeat freshness (Watch sends one per second).
* On disconnect the fight pauses and held inputs (block) are released; reconnect resumes it. `sessionDidDeactivate`
  re-activates the session (Watch switch); the app re-activates on every foreground.
* **Latency**: `ClockSync` estimates the Watch↔iPhone clock offset with ping/pong (lowest-RTT filter);
  `LatencyTracker` reports *sensor time → game action* (last/avg/min/max/p95) in the Debug screen and an optional overlay.

## 4. Game controller (iPhone)

`WristController` is the single input hub: it owns `PhoneLink`, the monitor, clock sync, calibration flow, the event log and
the **Developer Controller Mode** (`SimulatedController` produces the same `GestureEvent`s from buttons).
It exposes one hook, `onGesture`, consumed by the active fight (or the onboarding test).

## 5. Boxing game (core)

`FightEngine` consumes `GestureEvent`s and `update(dt)`; time moves only when `update` is called, randomness comes from a
seeded RNG → fights are deterministic and testable with simulated motion.

```swift
switch event {
case .jab(let r), .cross(let r), .leftHook(let r), .rightHook(let r), .uppercut(let r): handlePunch(r)
case .power(let r): specialReady ? activateSpecial() : handlePunch(r)
case .dodgeLeft:  handleDodge(.left)
case .blockStart: setBlocking(true)
…
}
```

* **Damage** = base(type) × (power) × (accuracy) × combo multiplier × named-combo bonus × perfect × counter × exposed × crit
  × upgrades × stamina state.
* **Combos**: landed punches inside a window chain; getting hit, dodged or sloppy punches break it (blocked ones don't).
  `ComboLibrary` recognises named sequences.
* **Counters**: a correctly-directed dodge before the impact opens a counter window; the dodge is “perfect” if within 180 ms.
* **Perfect punch**: punching in the first 0.3 s of an opening (after a whiffed attack, a finished pattern, a stun recovery).
* **Stamina**: punches/dodges cost; regeneration is delayed, faster while blocking, slower when low; low stamina cuts power
  *and* damage.
* **Special**: meter from landed hits (quality-scaled), perfects, counters, dodges; fires a 6-hit POWER COMBO while the
  player is invulnerable and the opponent stunned.
* **Rounds**: best of 3 × 60 s; two knockdowns in a round = KO; decision by health %, then damage.
* **Events**: the engine emits `FightEvent`s (punch results, combos, counters, telegraphs, knockdowns…) that drive UI, sound and
  haptics. `FightEvent.hapticCue` maps them to Watch haptic patterns (one cue per moment).

### Opponent AI

`OpponentAI` is a state machine with the states IDLE, WATCH, ATTACK, BLOCK, DODGE, STUNNED, VULNERABLE, KNOCKED_DOWN.
It plays weighted **attack patterns** (scripts of `wait / attack / guardUp / feint / quickAttack`) with a visible wind-up
(telegraph), so players can learn each boxer. Reactions to punches use a *reaction time* (the first punches of a flurry
land), blocks/dodges have probabilities, defended punches can trigger counters, and a *poise* meter turns sustained
damage into a stun. Profiles (`OpponentProfile.roster`) differ in reaction time, attack speed, rest time, block/dodge/counter
chance, poise, opening chance and combo scripts, not just health. `BalanceTests` plays whole fights with scripted players
of different skill to keep the difficulty curve honest.

## 6. UI

SwiftUI, iOS 16+. Screens: Home → Career → Fight → Result → Upgrades, plus Daily Challenge, Stats, Settings, Debug and
Onboarding. The fight screen is entirely vector art (no assets): animated opponent states, wind-up/lunge, first-person gloves,
screen shake, impact bursts, floating numbers, combo/counter/perfect banners, KO and knockdown sequences, countdown.
Sound effects are synthesised in code (`SoundService`).

The Watch UI is deliberately minimal: connection state, READY, round/time/combo during a fight, calibration prompts and a
local PRACTICE mode.

## 7. Persistence and progression

`PlayerProfile` (Codable, tolerant decoding: unknown/missing/corrupt fields fall back to defaults) holds level, XP, coins,
upgrades, career progress, lifetime stats, calibration, settings and daily challenge state. `FileProfileStore` writes JSON
atomically to Application Support; a corrupt file is moved aside, never deleted. No backend, no account, fully offline.

## 8. Threading

| Thread | What runs there |
|---|---|
| Watch motion `OperationQueue` (serial) | CoreMotion callback, `GestureRecognizer`, sending gesture messages, calibration runner |
| Watch main | UI, mode changes, heartbeat |
| WatchConnectivity queue | delegate callbacks → hop to main (iPhone) / parse + hop (Watch) |
| iPhone main | everything else (engine updates from `CADisplayLink`, gesture handling) |

`GestureRecognizer` is not thread-safe by design; settings reach it through `MotionEngine.apply(…)` on its queue.

## 9. Decisions worth knowing

* **Recognition on the Watch, not the iPhone**: tiny messages, lower latency, battery-friendly, and the game stays
  independent of raw data. A raw 10 Hz stream is available only for the Debug screen.
* **Core as a Swift package**: testable without Xcode; the same code runs on Watch and iPhone.
* **XcodeGen**: the `.xcodeproj` is generated (can't be hand-written reliably, merges badly).
* **HealthKit workout session on the Watch**: required to keep sensors running when the wrist moves; discarded afterwards.
* **Left hook = leftward swing**: gestures are named by swing direction, not by which hand wears the watch; *Mirror hooks*
  flips it.
