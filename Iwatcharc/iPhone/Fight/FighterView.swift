import SwiftUI
import WristBoxCore

// MARK: - Glove

/// Vector boxing glove (used for the opponent and the player's first-person gloves).
struct GloveView: View {
    var color: Color
    var size: CGFloat = 66

    var body: some View {
        ZStack {
            // cuff
            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                .fill(LinearGradient(colors: [Color.white, Color(white: 0.8)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.72, height: size * 0.3)
                .offset(y: size * 0.46)
            // thumb
            Capsule()
                .fill(color.opacity(0.9))
                .frame(width: size * 0.3, height: size * 0.5)
                .rotationEffect(.degrees(-28))
                .offset(x: -size * 0.36, y: size * 0.05)
            // fist
            Circle()
                .fill(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 2))
            // highlight
            Ellipse()
                .fill(Color.white.opacity(0.35))
                .frame(width: size * 0.38, height: size * 0.2)
                .rotationEffect(.degrees(-30))
                .offset(x: -size * 0.14, y: -size * 0.24)
        }
        .frame(width: size * 1.2, height: size * 1.3)
    }
}

// MARK: - Pose

struct GlovePose {
    var offset = CGSize.zero
    var scale: CGFloat = 1
    var rotation = Angle.zero
}

struct FighterPose {
    var body = CGSize.zero
    var bodyRotation = Angle.zero
    var head = CGSize.zero
    var left = GlovePose()    // viewer's left glove
    var right = GlovePose()   // viewer's right glove
    var glow: Color?
    var glowStrength = 0.0
    var eyesClosed = false
    var stars = false
    var dizzy = false
    var opacity = 1.0
    var hitFlash = 0.0
    var mouthOpen = false
    var angry = false
    var alert = false          // "OPEN!" cue
    var attackingLeft = false
    var attackingRight = false

    static func make(state: OpponentState,
                     attack: ActiveAttack?,
                     perfectWindow: Bool,
                     hitAt: Date?,
                     now: Date) -> FighterPose {
        var p = FighterPose()
        let t = now.timeIntervalSinceReferenceDate

        // Idle bob so the fighter always looks alive.
        let bob = CGFloat(sin(t * 3.2)) * 5
        p.body.height = bob
        p.left.offset = CGSize(width: CGFloat(sin(t * 3.2 + 1)) * 4, height: 0)
        p.right.offset = CGSize(width: CGFloat(sin(t * 3.2 + 2)) * 4, height: 0)

        switch state {
        case .idle:
            break

        case .watch:
            p.body.width = CGFloat(sin(t * 2.0)) * 14
            p.angry = true

        case .attack:
            p.angry = true
            if let a = attack {
                applyAttack(a, to: &p)
            }

        case .block:
            p.left.offset = CGSize(width: 62, height: -56)
            p.right.offset = CGSize(width: -62, height: -56)
            p.left.scale = 1.12
            p.right.scale = 1.12
            p.head.height = 8
            p.angry = true

        case .dodge:
            let dir: CGFloat = Int(t * 6) % 2 == 0 ? 1 : -1
            p.body.width = 78 * dir
            p.bodyRotation = .degrees(Double(dir) * 9)

        case .stunned:
            p.head.width = CGFloat(sin(t * 14)) * 9
            p.left.offset = CGSize(width: -6, height: 54)
            p.right.offset = CGSize(width: 6, height: 54)
            p.stars = true
            p.dizzy = true
            p.mouthOpen = true

        case .vulnerable:
            p.left.offset = CGSize(width: -6, height: 52)
            p.right.offset = CGSize(width: 6, height: 52)
            if perfectWindow {
                p.glow = Theme.gold
                p.glowStrength = 0.9 + 0.1 * sin(t * 24)
                p.alert = true
            } else {
                p.glow = Theme.gold
                p.glowStrength = 0.35
            }

        case .knockedDown:
            p.body = CGSize(width: 0, height: 120)
            p.bodyRotation = .degrees(78)
            p.eyesClosed = true
            p.opacity = 0.92
            p.left.offset = CGSize(width: -10, height: 40)
            p.right.offset = CGSize(width: 10, height: 40)
        }

        if let hitAt {
            let k = now.timeIntervalSince(hitAt) / 0.32
            if k >= 0, k < 1 {
                let s = sin(k * .pi)
                p.body.height -= CGFloat(s) * 14
                p.head.width += CGFloat(sin(k * .pi * 2)) * 12
                p.hitFlash = 1 - k
                p.eyesClosed = true
                p.mouthOpen = true
            }
        }
        return p
    }

    private static func applyAttack(_ a: ActiveAttack, to p: inout FighterPose) {
        let progress = a.progress
        let windup = min(1, progress / 0.85)
        let lunge = progress >= 0.85 ? easeOut((progress - 0.85) / 0.15) : 0
        let warn = Color(red: 1, green: 1 - 0.75 * progress, blue: 0.2 * (1 - progress))

        func apply(_ g: inout GlovePose, back: CGSize, forward: CGSize) {
            let w = CGFloat(easeOut(windup))
            let l = CGFloat(lunge)
            g.offset = CGSize(width: back.width * w + (forward.width - back.width * w) * l,
                              height: back.height * w + (forward.height - back.height * w) * l)
            g.scale = 1 - 0.18 * w + 1.35 * l
        }

        switch a.kind {
        case .jab:
            apply(&p.right, back: CGSize(width: 20, height: -34), forward: CGSize(width: -40, height: 80))
            p.attackingRight = true
        case .cross:
            apply(&p.left, back: CGSize(width: -24, height: -40), forward: CGSize(width: 36, height: 82))
            p.attackingLeft = true
        case .leftHook:
            apply(&p.left, back: CGSize(width: -96, height: -34), forward: CGSize(width: 58, height: 52))
            p.bodyRotation = .degrees(Double(-10 * windup))
            p.attackingLeft = true
        case .rightHook:
            apply(&p.right, back: CGSize(width: 96, height: -34), forward: CGSize(width: -58, height: 52))
            p.bodyRotation = .degrees(Double(10 * windup))
            p.attackingRight = true
        case .uppercut:
            apply(&p.left, back: CGSize(width: -34, height: 82), forward: CGSize(width: 20, height: -26))
            p.body.height += CGFloat(14 * windup)
            p.attackingLeft = true
        }
        if !a.isFeint || progress < 0.55 {
            p.glow = warn
            p.glowStrength = 0.35 + 0.65 * progress
        }
    }
}

// MARK: - Fighter

/// The opponent, drawn entirely from vector shapes (no artwork needed).
struct FighterView: View {
    let profile: OpponentProfile
    let state: OpponentState
    let attack: ActiveAttack?
    let perfectWindow: Bool
    let hitAt: Date?
    let now: Date

    var body: some View {
        let pose = FighterPose.make(state: state, attack: attack, perfectWindow: perfectWindow, hitAt: hitAt, now: now)
        let skin = Color(hex: profile.skinHex)
        let skinShade = skin.opacity(0.78)
        let trunks = Color(hex: profile.trunksHex)
        let glove = Color(hex: profile.gloveHex)
        let hair = Color(hex: profile.hairHex)

        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.4))
                .frame(width: 200, height: 28)
                .offset(y: 168)

            ZStack {
              // ViewBuilder accepts at most 10 children per block, so the body is split in two groups.
              Group {
                // Legs
                RoundedRectangle(cornerRadius: 22).fill(skinShade).frame(width: 46, height: 120).offset(x: -34, y: 118)
                RoundedRectangle(cornerRadius: 22).fill(skinShade).frame(width: 46, height: 120).offset(x: 34, y: 118)
                // Shoes
                Capsule().fill(Color(white: 0.12)).frame(width: 62, height: 24).offset(x: -34, y: 172)
                Capsule().fill(Color(white: 0.12)).frame(width: 62, height: 24).offset(x: 34, y: 172)
                // Trunks
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(LinearGradient(colors: [trunks, trunks.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 150, height: 86).offset(y: 70)
                Capsule().fill(Color.white).frame(width: 150, height: 14).offset(y: 40)
                // Torso
                RoundedRectangle(cornerRadius: 54, style: .continuous)
                    .fill(LinearGradient(colors: [skin, skinShade], startPoint: .top, endPoint: .bottom))
                    .frame(width: 142, height: 150).offset(y: -22)
              }
              Group {
                // Arms
                armPath(from: CGPoint(x: -66, y: -62), to: pose.left, base: CGPoint(x: -72, y: -84), color: skin)
                armPath(from: CGPoint(x: 66, y: -62), to: pose.right, base: CGPoint(x: 72, y: -84), color: skin)

                // Head
                headView(pose: pose, skin: skin, hair: hair)

                // Gloves (drawn last so they overlap the face when blocking)
                gloveView(pose.left, base: CGPoint(x: -72, y: -84), color: glove, glow: pose.attackingLeft ? pose.glow : nil, strength: pose.glowStrength)
                gloveView(pose.right, base: CGPoint(x: 72, y: -84), color: glove, glow: pose.attackingRight ? pose.glow : nil, strength: pose.glowStrength)

                if pose.stars {
                    ForEach(0..<3, id: \.self) { i in
                        Text("★")
                            .font(.system(size: 22))
                            .foregroundColor(Theme.gold)
                            .offset(x: CGFloat(cos(now.timeIntervalSinceReferenceDate * 5 + Double(i) * 2.1)) * 46,
                                    y: -178 + CGFloat(sin(now.timeIntervalSinceReferenceDate * 5 + Double(i) * 2.1)) * 10)
                    }
                }
                if pose.hitFlash > 0 {
                    RoundedRectangle(cornerRadius: 60)
                        .fill(Color.white.opacity(0.55 * pose.hitFlash))
                        .frame(width: 190, height: 330)
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                }
              }
            }
            .offset(pose.body)
            .rotationEffect(pose.bodyRotation, anchor: .bottom)
            .opacity(pose.opacity)

            if pose.alert {
                Text("OPEN!")
                    .font(.heavy(26))
                    .foregroundColor(Theme.gold)
                    .shadow(color: Theme.orange, radius: 8)
                    .offset(y: -214)
            }
        }
        .frame(width: 300, height: 380)
    }

    // MARK: Pieces

    private func armPath(from shoulder: CGPoint, to glove: GlovePose, base: CGPoint, color: Color) -> some View {
        let end = CGPoint(x: base.x + glove.offset.width, y: base.y + glove.offset.height)
        return Path { p in
            p.move(to: CGPoint(x: 150 + shoulder.x, y: 190 + shoulder.y))
            p.addLine(to: CGPoint(x: 150 + end.x, y: 190 + end.y))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 30, lineCap: .round))
        .frame(width: 300, height: 380)
    }

    private func gloveView(_ pose: GlovePose, base: CGPoint, color: Color, glow: Color?, strength: Double) -> some View {
        ZStack {
            if let glow {
                Circle()
                    .stroke(glow.opacity(0.9 * strength), lineWidth: 6)
                    .frame(width: 96, height: 96)
                    .blur(radius: 2)
                Circle()
                    .fill(glow.opacity(0.35 * strength))
                    .frame(width: 110, height: 110)
                    .blur(radius: 10)
            }
            GloveView(color: color, size: 62)
        }
        .scaleEffect(pose.scale)
        .rotationEffect(pose.rotation)
        .offset(x: base.x + pose.offset.width, y: base.y + pose.offset.height)
    }

    private func headView(pose: FighterPose, skin: Color, hair: Color) -> some View {
        ZStack {
            // neck
            RoundedRectangle(cornerRadius: 10).fill(skin.opacity(0.85)).frame(width: 40, height: 30).offset(y: 40)
            // ears
            Circle().fill(skin.opacity(0.9)).frame(width: 22, height: 26).offset(x: -48)
            Circle().fill(skin.opacity(0.9)).frame(width: 22, height: 26).offset(x: 48)
            // face
            Circle()
                .fill(LinearGradient(colors: [skin, skin.opacity(0.82)], startPoint: .top, endPoint: .bottom))
                .frame(width: 96, height: 96)
                .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 2))
            Circle().trim(from: 0.5, to: 1.0).fill(hair).frame(width: 98, height: 98).offset(y: -2)
            // brows
            RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.75)).frame(width: 22, height: 5)
                .rotationEffect(.degrees(pose.angry ? 14 : 0)).offset(x: -18, y: -14)
            RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.75)).frame(width: 22, height: 5)
                .rotationEffect(.degrees(pose.angry ? -14 : 0)).offset(x: 18, y: -14)
            // eyes
            if pose.eyesClosed {
                Capsule().fill(Color.black.opacity(0.7)).frame(width: 16, height: 3).offset(x: -18, y: -2)
                Capsule().fill(Color.black.opacity(0.7)).frame(width: 16, height: 3).offset(x: 18, y: -2)
            } else if pose.dizzy {
                Text("✕").font(.system(size: 16, weight: .black)).foregroundColor(.black.opacity(0.75)).offset(x: -18, y: -3)
                Text("✕").font(.system(size: 16, weight: .black)).foregroundColor(.black.opacity(0.75)).offset(x: 18, y: -3)
            } else {
                Ellipse().fill(Color.white).frame(width: 18, height: 14).offset(x: -18, y: -3)
                Ellipse().fill(Color.white).frame(width: 18, height: 14).offset(x: 18, y: -3)
                Circle().fill(Color.black).frame(width: 7, height: 7).offset(x: -18, y: -3)
                Circle().fill(Color.black).frame(width: 7, height: 7).offset(x: 18, y: -3)
            }
            // nose + mouth
            Capsule().fill(Color.black.opacity(0.14)).frame(width: 8, height: 16).offset(y: 8)
            if pose.mouthOpen {
                Ellipse().fill(Color(hex: "5A0F14")).frame(width: 26, height: 18).offset(y: 28)
            } else {
                Capsule().fill(Color(hex: "5A0F14")).frame(width: 28, height: 6).offset(y: 28)
            }
        }
        .offset(x: pose.head.width, y: -108 + pose.head.height)
    }
}
