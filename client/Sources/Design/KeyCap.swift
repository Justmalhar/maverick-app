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
        .background(backgroundView)
        .overlay(
            Capsule().strokeBorder(borderColor, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch style {
        case .latched:
            Capsule().fill(Theme.accentGradient)
        case .neutral, .primary, .danger:
            ZStack {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(Color.white.opacity(0.04))
            }
        }
    }

    private var textColor: Color {
        switch style {
        case .neutral: return Theme.textPrimary
        case .primary: return Theme.accent
        case .danger:  return Theme.danger
        case .latched: return .black
        }
    }

    private var borderColor: Color {
        switch style {
        case .neutral, .primary, .danger: return Theme.stroke
        case .latched: return .white.opacity(0.4)
        }
    }
}
