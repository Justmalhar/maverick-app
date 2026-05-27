// client/Sources/Design/LiquidGlass.swift
import SwiftUI

/// Apple-style Liquid Glass surface: translucent fill, edge-light highlight,
/// soft shadow. Keeps the monochrome palette intact while adding depth.
struct LiquidGlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 16
    var elevation: CGFloat = 1.0
    var strokeOpacity: Double = 0.18

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    // Subtle inner gradient highlight (top → bottom)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.06),
                                    Color.white.opacity(0.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(strokeOpacity),
                                Color.white.opacity(strokeOpacity * 0.35),
                                Color.white.opacity(strokeOpacity * 0.15)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
            )
            .shadow(color: .black.opacity(0.45 * elevation), radius: 12 * elevation, x: 0, y: 4 * elevation)
    }
}

/// Liquid glass capsule (for keycaps + icon buttons).
struct LiquidGlassCapsule: ViewModifier {
    var strokeOpacity: Double = 0.20

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), Color.white.opacity(0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                }
            )
            .overlay(
                Capsule().strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(strokeOpacity),
                            Color.white.opacity(strokeOpacity * 0.4)
                        ],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.7
                )
            )
            .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 1)
    }
}

/// Liquid glass circle (for round icon buttons + the cursor pad).
struct LiquidGlassCircle: ViewModifier {
    var strokeOpacity: Double = 0.20

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Circle().fill(.ultraThinMaterial)
                    Circle().fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), Color.white.opacity(0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                }
            )
            .overlay(
                Circle().strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(strokeOpacity), Color.white.opacity(strokeOpacity * 0.4)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.7
                )
            )
            .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 1)
    }
}

extension View {
    func liquidGlassSurface(cornerRadius: CGFloat = 16, elevation: CGFloat = 1) -> some View {
        modifier(LiquidGlassSurface(cornerRadius: cornerRadius, elevation: elevation))
    }
    func liquidGlassCapsule() -> some View { modifier(LiquidGlassCapsule()) }
    func liquidGlassCircle() -> some View { modifier(LiquidGlassCircle()) }
}
