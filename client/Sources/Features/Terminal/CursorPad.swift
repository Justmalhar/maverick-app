// client/Sources/Features/Terminal/CursorPad.swift
import SwiftUI

/// A small joystick that converts a finger drag into continuous arrow key emission.
///
/// While the user is pressing and dragging:
///   - The drag direction is computed from a fixed anchor (where the press started).
///   - As long as the drag is past `deadZone` in any direction, a timer fires every
///     `repeatInterval` and emits the arrow key for the dominant axis.
///   - The repeat rate accelerates the further the finger is from the anchor:
///     small drag = slow, larger drag = fast (typical D-pad behavior).
struct CursorPad: View {
    let terminalVC: TerminalViewController
    var deadZone: CGFloat = 10
    var maxDistance: CGFloat = 36

    @State private var anchor: CGPoint?
    @State private var currentOffset: CGSize = .zero
    @State private var emitter: Timer?
    @State private var activeDirection: Direction?

    private enum Direction: CaseIterable { case up, down, left, right }

    var body: some View {
        ZStack {
            Color.clear.liquidGlassCircle()
            if activeDirection != nil {
                Circle()
                    .strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1)
                    .shadow(color: Theme.accent.opacity(0.4), radius: 6)
            }

            // Directional ticks
            VStack {
                Tri().fill(tickColor(.up)).frame(width: 8, height: 6)
                Spacer()
                Tri().fill(tickColor(.down)).frame(width: 8, height: 6).rotationEffect(.degrees(180))
            }
            .padding(.vertical, 7)
            HStack {
                Tri().fill(tickColor(.left)).frame(width: 6, height: 8).rotationEffect(.degrees(-90))
                Spacer()
                Tri().fill(tickColor(.right)).frame(width: 6, height: 8).rotationEffect(.degrees(90))
            }
            .padding(.horizontal, 7)

            // Center thumb showing drag direction
            Circle()
                .fill(activeDirection != nil ? Theme.accent : Theme.textTertiary)
                .frame(width: 12, height: 12)
                .offset(currentOffset)
                .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.7), value: currentOffset)
        }
        .frame(width: 60, height: 60)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if anchor == nil {
                        anchor = value.location
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    guard let a = anchor else { return }
                    let dx = value.location.x - a.x
                    let dy = value.location.y - a.y
                    let clamped = clamp(dx: dx, dy: dy)
                    currentOffset = CGSize(width: clamped.x, height: clamped.y)

                    let dir = dominantDirection(dx: dx, dy: dy)
                    if dir != activeDirection {
                        activeDirection = dir
                        scheduleEmitter(for: dir, distance: hypot(dx, dy))
                    } else if let dir {
                        // Re-tune emitter rate based on current distance.
                        scheduleEmitter(for: dir, distance: hypot(dx, dy))
                    }
                }
                .onEnded { _ in
                    stopEmitter()
                    anchor = nil
                    activeDirection = nil
                    withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.7)) {
                        currentOffset = .zero
                    }
                }
        )
    }

    // MARK: - geometry

    private func clamp(dx: CGFloat, dy: CGFloat) -> CGPoint {
        let len = hypot(dx, dy)
        guard len > maxDistance else { return CGPoint(x: dx, y: dy) }
        let ratio = maxDistance / len
        return CGPoint(x: dx * ratio, y: dy * ratio)
    }

    private func dominantDirection(dx: CGFloat, dy: CGFloat) -> Direction? {
        let absX = abs(dx), absY = abs(dy)
        if max(absX, absY) < deadZone { return nil }
        if absX > absY {
            return dx > 0 ? .right : .left
        } else {
            return dy > 0 ? .down : .up
        }
    }

    private func tickColor(_ dir: Direction) -> Color {
        activeDirection == dir ? Theme.accent : Theme.textTertiary.opacity(0.7)
    }

    // MARK: - emission

    private func scheduleEmitter(for dir: Direction?, distance: CGFloat) {
        emitter?.invalidate()
        emitter = nil
        guard let dir else { return }

        // Map drag distance (deadZone…maxDistance) to repeat interval (0.18s…0.05s)
        let ratio = max(0, min(1, (distance - deadZone) / max(1, maxDistance - deadZone)))
        let interval: TimeInterval = 0.18 - Double(ratio) * 0.13

        // Fire one immediately on direction change for snappy feedback…
        emit(dir)
        // …then schedule continuous repeats.
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            emit(dir)
        }
        RunLoop.main.add(t, forMode: .common)
        emitter = t
    }

    private func stopEmitter() {
        emitter?.invalidate()
        emitter = nil
    }

    private func emit(_ dir: Direction) {
        switch dir {
        case .up:    terminalVC.sendArrow("[A")
        case .down:  terminalVC.sendArrow("[B")
        case .right: terminalVC.sendArrow("[C")
        case .left:  terminalVC.sendArrow("[D")
        }
    }
}

private struct Tri: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
