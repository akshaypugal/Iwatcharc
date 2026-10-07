# WristBox — *Your wrist. Your fight.*

A boxing game where your **Apple Watch is the controller**. Throw real punches; the Watch reads
your wrist motion, recognises the gesture, and the iPhone shows the fight.

This repository is the MVP: **one game (boxing)**, built to be fun in a 2–3 minute session and to
prove that a Watch can be a physical game controller.

```
APPLE WATCH                                     IPHONE
Accelerometer + Gyroscope                       Boxing game engine + AI
   │  noise filter → calibration → peaks          │  damage, combos, counters,
   │  → direction → classification                │  stamina, special, rounds
   ▼                                              ▼
Gesture events ───── WatchConnectivity ────►  Game controller ──► UI, sound, haptics
   ▲                                              │
   └────────────── haptic cues ◄──────────────────┘
```

## What's inside

| Area | Where |
|---|---|
| iPhone app (SwiftUI) | [`iPhone/`](iPhone) |
| Apple Watch app (SwiftUI, Core Motion, WatchConnectivity, HealthKit workout) | [`Watch/`](Watch) |
| Platform-independent core (gestures, game, AI, progression, wire protocol) | [`Packages/WristBoxCore`](Packages/WristBoxCore) |
| Unit tests (core: 173, app: smoke tests) | [`Packages/WristBoxCore/Tests`](Packages/WristBoxCore/Tests), [`iPhoneTests/`](iPhoneTests) |
| Xcode project definition (XcodeGen) | [`project.yml`](project.yml), [`Config/`](Config) |
| CI (core tests on Linux + full iPhone/Watch build on macOS) | [`.github/workflows/ci.yml`](.github/workflows/ci.yml) |
| Docs | [`docs/`](docs) |

## Quick start (on a Mac)

```bash
git clone <this repo> && cd <repo>
bash scripts/bootstrap.sh      # installs XcodeGen, runs the core tests, generates WristBox.xcodeproj, opens Xcode
```

Then in Xcode: select your Team, run **WristBox** on your iPhone. The Watch app installs through the
paired iPhone. Full instructions: **[docs/SETUP.md](docs/SETUP.md)**. If something misbehaves:
**[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)**.

No Watch handy? Run in the iOS Simulator: the app starts in **Developer Controller Mode** with on-screen
buttons (JAB, CROSS, L/R HOOK, UPPERCUT, DODGE L/R, BLOCK, POWER) and keyboard shortcuts. The game cannot tell
the difference between those buttons and the Watch.

## The game

* **Career**: BOXER → ROOKIE → CONTENDER → PRO → CHAMPION. Five opponents that differ in *behaviour*, not just health:
  reaction time, attack speed, defence, counters and combo scripts (the champion even feints).
* **Fights**: best of 3 rounds, 60 s each, KO possible. Knockdown count; second knockdown in a round is a KO.
* **Gestures**: jab, cross, left/right hook, uppercut, power punch, dodge left/right, block (hold your guard), shake (special).
* **Punch quality**: power, accuracy, speed → damage. Sloppy direction whiffs.
* **Combos**: named sequences (ONE-TWO, ONE-TWO-HOOK, THE FULL COMBO …) with bonus damage; getting hit or missing breaks them.
* **Counters**: dodge an attack, then punch inside the window → ⚡ COUNTER (⚡ PERFECT COUNTER for a perfectly timed dodge).
* **Perfect punches**: hit an opening the moment the guard drops.
* **Stamina**: spamming drains it; gassed fighters hit weaker and recover slower. Block and rest to recover.
* **Special**: fill the meter, throw a POWER punch (or shake) for the 6-hit POWER COMBO.
* **Progression**: XP, level, coins; upgrades (Power, Speed, Defense, Stamina); 3 daily challenges (+100 XP, +50 coins each).
* **Offline-first**: everything is stored locally. No account, no server.

## Verification status (please read)

| Part | How it was verified |
|---|---|
| `WristBoxCore` (gestures, engine, AI, progression, wire protocol, persistence) | Compiled and **173 unit tests pass** with Swift 5.10 on Linux, including bot-simulated fights for balance. |
| iPhone / Watch apps | Written on a Windows PC without Xcode, **syntax-checked and code-reviewed, but not compiled**. The first build on a Mac (or the included GitHub Actions workflow) is the real compile check. Fix-ups from that first build are expected to be small. |
| Gesture thresholds | Tuned on synthetic data only. Real-wrist tuning (Phase 6) happens on your Watch with the Debug screen: see [docs/TUNING.md](docs/TUNING.md). |

## Documentation

* [docs/SETUP.md](docs/SETUP.md) – install, sign, run on iPhone + Watch, Simulator mode, CI
* [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) – layers, data flow, protocols, threading, decisions
* [docs/TUNING.md](docs/TUNING.md) – tuning gestures on a real Watch
* [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) – pairing, signing, sensors, latency, gestures
