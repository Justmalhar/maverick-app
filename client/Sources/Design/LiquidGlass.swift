// client/Sources/Design/LiquidGlass.swift
import SwiftUI

// MARK: - Surface (rounded rect)

struct LiquidGlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 16
    var elevation: CGFloat = 1.0
    var strokeOpacity: Double = 0.18

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            // Real Liquid Glass: dynamic refraction, specular highlights, background sampling.
            content
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        } else {
            // Pre-iOS 26 fallback: frosted glass via ultraThinMaterial + manual sheen.
            content
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.06), Color.white.opacity(0)],
                                    startPoint: .top, endPoint: .bottom
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
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 0.8
                        )
                )
                .shadow(color: .black.opacity(0.45 * elevation), radius: 12 * elevation, x: 0, y: 4 * elevation)
        }
    }
}

// MARK: - Capsule

struct LiquidGlassCapsule: ViewModifier {
    var strokeOpacity: Double = 0.20

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
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
                            colors: [Color.white.opacity(strokeOpacity), Color.white.opacity(strokeOpacity * 0.4)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 0.7
                    )
                )
                .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 1)
        }
    }
}

// MARK: - Circle

struct LiquidGlassCircle: ViewModifier {
    var strokeOpacity: Double = 0.20

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: .circle)
        } else {
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
}

// MARK: - Extensions

extension View {
    func liquidGlassSurface(cornerRadius: CGFloat = 16, elevation: CGFloat = 1) -> some View {
        modifier(LiquidGlassSurface(cornerRadius: cornerRadius, elevation: elevation))
    }
    func liquidGlassCapsule() -> some View { modifier(LiquidGlassCapsule()) }
    func liquidGlassCircle() -> some View { modifier(LiquidGlassCircle()) }

    /// Interactive glass circle — real Liquid Glass on iOS 26 (scaling, bounce, shimmer on touch),
    /// frosted-circle fallback on older OS.
    @ViewBuilder
    func glassInteractiveCircle() -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular.interactive(), in: .circle)
        } else {
            self
                .background(Circle().fill(Color.white.opacity(0.08)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        }
    }

    /// Glass circle button style — used for small icon-only nav buttons.
    @ViewBuilder
    func glassCircleButtonStyle() -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular.interactive(), in: .circle)
        } else {
            self
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.7))
        }
    }
}

// MARK: - Connect button style shim

extension View {
    /// Applies .glassProminent button style on iOS 26; caller supplies the pre-iOS-26 styling.
    @ViewBuilder
    func connectButtonStyle() -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.plain)
        }
    }

    /// Applies the closure's styling only on iOS < 26 (so iOS 26 can use glass instead).
    @ViewBuilder
    func ifNot26<T: View>(@ViewBuilder transform: (Self) -> T) -> some View {
        if #available(iOS 26, *) {
            self
        } else {
            transform(self)
        }
    }
}

// MARK: - GlassEffectContainer availability shim

/// Wraps content in a real GlassEffectContainer on iOS 26+ (shared sampling region +
/// morphing support), or just passes through content on older OS.
struct GlassEffectContainerIfAvailable<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 8) { content() }
        } else {
            content()
        }
    }
}
