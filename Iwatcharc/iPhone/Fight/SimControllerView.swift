import SwiftUI
import WristBoxCore

/// Developer Controller Mode: on-screen buttons that produce exactly the events
/// the Apple Watch would. With a hardware keyboard (Simulator) the keys shown
/// in the corner of each button work too.
struct SimControllerView: View {
    @EnvironmentObject var controller: WristController
    @State private var blockOn = false

    private let rows: [[SimulatedInput]] = [
        [.jab, .cross, .power],
        [.leftHook, .uppercut, .rightHook],
        [.dodgeLeft, .block, .dodgeRight]
    ]

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("DEVELOPER CONTROLLER").font(.heavy(10)).foregroundColor(Theme.gold)
                Spacer()
                Button { controller.simulate(.special) } label: {
                    Text("SPECIAL ␣").font(.heavy(10)).foregroundColor(.black)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Theme.gold).clipShape(Capsule())
                }
                .keyboardShortcut(" ", modifiers: [])
            }
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(rows[r], id: \.self) { input in
                        button(for: input)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func button(for input: SimulatedInput) -> some View {
        if input == .block {
            Button {
                blockOn.toggle()
                controller.simulateBlock(pressed: blockOn)
            } label: {
                label(input, active: blockOn)
            }
            .keyboardShortcut(KeyEquivalent(input.shortcutKey), modifiers: [])
        } else {
            Button {
                controller.simulate(input)
            } label: {
                label(input, active: false)
            }
            .keyboardShortcut(KeyEquivalent(input.shortcutKey), modifiers: [])
        }
    }

    private func label(_ input: SimulatedInput, active: Bool) -> some View {
        HStack(spacing: 4) {
            Text(input == .block ? (active ? "BLOCK ON" : "BLOCK") : input.title)
                .font(.heavy(13))
            Text(String(input.shortcutKey).uppercased())
                .font(.mono(9))
                .opacity(0.6)
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background(active ? Theme.blue : tint(for: input))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func tint(for input: SimulatedInput) -> Color {
        switch input {
        case .jab, .cross, .leftHook, .rightHook, .uppercut: return Theme.red.opacity(0.85)
        case .power: return Theme.orange
        case .dodgeLeft, .dodgeRight: return Color(hex: "1F8A70")
        case .block: return Color(hex: "3A4A7A")
        case .special: return Theme.gold
        }
    }
}
