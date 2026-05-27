// client/Sources/Features/Terminal/CursorPad.swift
import SwiftUI

/// A small drag pad that converts finger drag direction into arrow keystrokes.
/// Press and drag in any direction; every `stepDistance` of movement emits one
/// arrow key in the dominant axis. Releasing resets.
struct CursorPad: View {
    let terminalVC: TerminalViewController
    var stepDistance: CGFloat = 14

    @State private var anchor: CGPoint?
    @State private var emittedDir: Direction?
    @State private var isPressed = false

    private enum Direction { case left, right, up, down }

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
            Circle()
                .strokeBorder(isPressed ? Theme.accent : Theme.stroke, lineWidth: 1)
            // 4 directional ticks
            VStack {
                Triangle().fill(tickColor(.up)).frame(width: 8, height: 6)
                Spacer()
                Triangle().fill(tickColor(.down)).frame(width: 8, height: 6).rotationEffect(.degrees(180))
            }
            .padding(.vertical, 8)
            HStack {
                Triangle().fill(tickColor(.left)).frame(width: 6, height: 8).rotationEffect(.degrees(-90))
                Spacer()
                Triangle().fill(tickColor(.right)).frame(width: 6, height: 8).rotationEffect(.degrees(90))
            }
            .padding(.horizontal, 8)
            // Center label
            Image(systemName: "dpad.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isPressed ? Theme.accent : Theme.textSecondary)
        }
        .frame(width: 64, height: 64)
        .shadow(color: isPressed ? Theme.accent.opacity(0.35) : .clear, radius: 12)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if anchor == nil {
                        anchor = value.location
                        isPressed = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    guard let a = anchor else { return }
                    let dx = value.location.x - a.x
                    let dy = value.location.y - a.y
                    let direction = self.direction(dx: dx, dy: dy)
                    guard let direction else { return }
                    if direction != emittedDir {
                        emit(direction)
                        emittedDir = direction
                        // Reset anchor so the next step distance is measured from here,
                        // letting the user continue dragging in the same direction.
                        anchor = value.location
                    }
                }
                .onEnded { _ in
                    anchor = nil
                    emittedDir = nil
                    isPressed = false
                }
        )
    }

    private func direction(dx: CGFloat, dy: CGFloat) -> Direction? {
        let absX = abs(dx), absY = abs(dy)
        if max(absX, absY) < stepDistance { return nil }
        if absX > absY {
            return dx > 0 ? .right : .left
        } else {
            return dy > 0 ? .down : .up
        }
    }

    private func tickColor(_ dir: Direction) -> Color {
        emittedDir == dir ? Theme.accent : Theme.textTertiary
    }

    private func emit(_ dir: Direction) {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        switch dir {
        case .up:    terminalVC.sendArrow("[A")
        case .down:  terminalVC.sendArrow("[B")
        case .right: terminalVC.sendArrow("[C")
        case .left:  terminalVC.sendArrow("[D")
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
