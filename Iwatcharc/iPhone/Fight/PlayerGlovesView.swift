import SwiftUI
import WristBoxCore

/// The player's gloves in first person at the bottom of the screen. They throw
/// the punch that was just recognised, raise into a guard when blocking, and
/// lean away when dodging.
struct PlayerGlovesView: View {
    let punch: PunchFX?
    let dodge: DodgeFX?
    let blocking: Bool
    let now: Date

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let leftBase = CGPoint(x: w * 0.30, y: h * 0.72)
            let rightBase = CGPoint(x: w * 0.70, y: h * 0.72)
            let pair = poses(w: w, h: h)
            let dodgeShift = dodgeOffset(w: w)

            ZStack {
                glove(pair.0, base: leftBase, color: Color(hex: "D7263D"))
                glove(pair.1, base: rightBase, color: Color(hex: "D7263D"))
            }
            .offset(x: dodgeShift)
            .animation(.easeOut(duration: 0.12), value: blocking)
        }
        .allowsHitTesting(false)
    }

    private func glove(_ pose: GlovePose, base: CGPoint, color: Color) -> some View {
        GloveView(color: color, size: 92)
            .rotationEffect(pose.rotation)
            .scaleEffect(pose.scale)
            .position(x: base.x + pose.offset.width, y: base.y + pose.offset.height)
    }

    private func dodgeOffset(w: CGFloat) -> CGFloat {
        guard let d = dodge else { return 0 }
        let k = now.timeIntervalSince(d.start) / 0.45
        guard k >= 0, k < 1 else { return 0 }
        let dir: CGFloat = d.side == .left ? -1 : 1
        return dir * w * 0.18 * CGFloat(sin(k * .pi))
    }

    /// Left and right glove poses for this instant.
    private func poses(w: CGFloat, h: CGFloat) -> (GlovePose, GlovePose) {
        var left = GlovePose()
        var right = GlovePose()

        // Idle sway.
        let t = now.timeIntervalSinceReferenceDate
        left.offset = CGSize(width: 0, height: CGFloat(sin(t * 3.0)) * 4)
        right.offset = CGSize(width: 0, height: CGFloat(sin(t * 3.0 + 1.5)) * 4)

        if blocking {
            left.offset = CGSize(width: w * 0.16, height: -h * 0.55)
            right.offset = CGSize(width: -w * 0.16, height: -h * 0.55)
            left.scale = 1.15
            right.scale = 1.15
            left.rotation = .degrees(14)
            right.rotation = .degrees(-14)
        }

        guard let p = punch else { return (left, right) }
        let k = now.timeIntervalSince(p.start) / 0.32
        guard k >= 0, k < 1 else { return (left, right) }
        let x = CGFloat(sin(k * .pi))                      // out and back
        let far = 1 - 0.38 * x                              // gloves shrink as they fly away

        switch p.type {
        case .jab:
            left.offset = CGSize(width: w * 0.16 * x, height: -h * 1.15 * x)
            left.scale = far
        case .cross:
            right.offset = CGSize(width: -w * 0.18 * x, height: -h * 1.2 * x)
            right.scale = far
        case .leftHook:
            left.offset = CGSize(width: w * 0.42 * x, height: -h * 0.85 * x)
            left.rotation = .degrees(Double(60 * x))
            left.scale = 1 - 0.2 * x
        case .rightHook:
            right.offset = CGSize(width: -w * 0.42 * x, height: -h * 0.85 * x)
            right.rotation = .degrees(Double(-60 * x))
            right.scale = 1 - 0.2 * x
        case .uppercut:
            right.offset = CGSize(width: -w * 0.1 * x, height: -h * 1.05 * x)
            right.scale = 1 + 0.15 * x
            right.rotation = .degrees(Double(-18 * x))
        case .power:
            left.offset = CGSize(width: w * 0.12 * x, height: -h * 1.2 * x)
            right.offset = CGSize(width: -w * 0.12 * x, height: -h * 1.2 * x)
            left.scale = far * 1.15
            right.scale = far * 1.15
        }
        return (left, right)
    }
}
