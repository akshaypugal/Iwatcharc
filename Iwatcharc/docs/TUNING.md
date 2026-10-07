# Tuning the controls on a real Watch (Phase 6)

The default thresholds in `GestureConfig` were tuned against synthetic motion. Your wrist is the real test.
Everything below can be changed live from **Settings → Developer mode → Debug → Thresholds**; changes are
sent to the Watch immediately and saved.

## The loop

1. Wear the Watch on your dominant wrist. Calibrate (*Settings → Calibrate*).
2. Open **Debug**. Keep the Watch app open (opening Debug puts it in fight mode and streams sensors).
3. Throw one gesture at a time. Watch **Detected gesture**, **Confidence**, **Last decision** and the **Event log**.
   * An accepted gesture shows e.g. `JAB 84%`.
   * A rejected movement shows `REJECT <reason>` — the reason tells you which threshold to move:

| Reason | Meaning | Fix |
|---|---|---|
| `weak` | peak below the minimum for any gesture/type | lower the relevant *min* (Jab/Cross/Hook/Dodge) |
| `tooShort` | one-sample glitch | usually leave it alone |
| `tooLong` | motion longer than 0.65 s (waving) | leave it alone |
| `wrongDirection` / `ambiguous` | direction not dominated by one axis | re-calibrate; punch straighter; check the *forward* axis |
| `cooldown` | same gesture again within its cooldown | lower *Jab cooldown* |
| `rateLimited` | more than 6 punches in a second | intended; raise `maxPunchesPerSecond` in code if you disagree |
| `retract` | the arm coming back after a punch | intended |
| `implausible` | > 24 g | glitch or abuse |
| `lockout` | just after a shake | intended |
| `lowConfidence` | classified but not clearly | punch cleaner, or lower `confidenceMin` |

4. Aim for: every deliberate gesture recognised, no false positives while standing in guard and moving around.

## Which slider fixes which problem

| Symptom | Move |
|---|---|
| Jabs are missed | *Jab min* ↓ |
| Jabs show up as crosses (or crosses as jabs) | *Cross min* ↑ / ↓ |
| Power punches never trigger | *Power min* ↓ |
| Hooks come out as dodges | *Hook yaw min* ↓ (hooks need more wrist rotation than dodges) |
| Dodges come out as hooks | *Hook yaw min* ↑ |
| Uppercuts missed | *Uppercut min* ↓ |
| Dodges missed | *Dodge min* ↓ |
| Everything feels laggy | *Responsiveness* ↑ (higher = less smoothing = faster but noisier) |
| Block never triggers / triggers constantly | *Block angle* ↑ / ↓, *Block hold* ↓ / ↑, re-calibrate the guard pose |

## What “good” looks like

* **Latency** (Debug → Latency): motion → game under ~100 ms on a healthy connection. The punch is recognised
  roughly 70–120 ms after it starts (we fire once the peak has passed), then ~20–60 ms over WatchConnectivity.
* **False positives**: stand in guard, bob and weave for 30 s: no punches. If there are some, raise *Jab min* a little.
* **Fatigue**: tune when relaxed *and* after a few rounds; a tired jab is weaker.

## Reference: sensor units and typical numbers

* Acceleration is *user acceleration* (gravity removed) in g. Shadow-boxing at the wrist: a lazy jab ≈ 1.8–3 g, a hard cross
  ≈ 3–6 g, a big power punch > 5.5 g; a deliberate dodge ≈ 0.9–2 g with little rotation; hooks ≈ 2–5 g with yaw ≥ 5 rad/s.
  Your numbers will differ: that is what this screen is for.
* Rotation is in rad/s. Yaw is rotation about the vertical axis (computed from gravity).
* The recogniser works in *player coordinates* (forward / lateral / vertical) derived from calibration.

## Developer tips

* The recogniser and classifier are pure Swift and unit-tested: add a regression test in
  `Packages/WristBoxCore/Tests/WristBoxCoreTests/GestureRecognizerTests.swift` with `MotionSynth` whenever you change a
  threshold or rule.
* `GestureRecognizer.process(_:)` takes `[MotionSample]`, so recorded real motion (if you log full samples on the Watch)
  can be replayed through it to make threshold experiments repeatable without a Watch on your wrist. The Debug screen's
  live stream only carries acceleration and gyro (device frame), which is enough to *look at* the signals but not to replay.
* `BalanceTests` simulate whole fights; re-run them (`swift test --filter BalanceTests`) after touching damage, stamina or AI numbers.
