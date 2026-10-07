import SwiftUI
import WristBoxCore

/// Short-lived visual effects. Each carries its creation time so views can
/// animate them from `TimelineView` without the view model publishing every frame.

struct Banner: Identifiable {
    let id = UUID()
    let text: String
    var subtitle: String?
    let color: Color
    let size: CGFloat
    let created: Date
    let duration: Double

    func progress(at now: Date) -> Double {
        min(1, max(0, now.timeIntervalSince(created) / duration))
    }
}

struct FloatingNumber: Identifiable {
    let id = UUID()
    let text: String
    let color: Color
    /// Horizontal anchor, -1...1 across the arena.
    let x: CGFloat
    /// Vertical anchor, 0...1 down the arena.
    let y: CGFloat
    let size: CGFloat
    let created: Date
    let duration = 0.9
}

struct ImpactBurst: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let color: Color
    let big: Bool
    let created: Date
    let duration = 0.35
}

struct PunchFX: Equatable {
    var type: PunchType
    var start: Date
}

struct DodgeFX: Equatable {
    var side: Side
    var start: Date
}

/// Starburst used for impact effects.
struct StarShape: Shape {
    var points = 9
    var innerRatio: CGFloat = 0.45

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerRatio
        var p = Path()
        for i in 0..<(points * 2) {
            let r = i % 2 == 0 ? outer : inner
            let a = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
            let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

func easeOut(_ t: Double) -> Double { 1 - pow(1 - min(max(t, 0), 1), 3) }
func easeInOut(_ t: Double) -> Double {
    let x = min(max(t, 0), 1)
    return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
}
