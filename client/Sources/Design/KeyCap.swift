// client/Sources/Design/KeyCap.swift
import SwiftUI

struct KeyCap: View {
    enum Style { case neutral, primary, danger, latched }
    let label: String
    var style: Style = .neutral
    var minWidth: CGFloat = 38
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(textColor)
                .frame(minWidth: minWidth, minHeight: 34)
                .padding(.horizontal, 8)
        }
        .background {
            if style == .latched {
                Capsule().fill(Theme.accentGradient)
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8))
                    .shadow(color: Color.white.opacity(0.18), radius: 6, x: 0, y: 0)
            } else {
                Color.clear.liquidGlassCapsule()
            }
        }
        .buttonStyle(.plain)
    }

    private var textColor: Color {
        switch style {
        case .neutral: return Theme.textPrimary
        case .primary: return Theme.accent
        case .danger:  return Theme.danger
        case .latched: return .black
        }
    }
}
