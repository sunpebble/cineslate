import SwiftUI

/// Thin wrappers around the iOS 26 Liquid Glass APIs so call sites stay tidy
/// and we get a graceful material fallback on anything older.
extension View {
    /// Capsule-shaped liquid glass (used by the floating tab bar / pills).
    func glassCapsule(interactive: Bool = false) -> some View {
        modifier(GlassShapeModifier(shape: Capsule(), interactive: interactive, tint: nil))
    }

    /// Circular liquid glass (used by the detail-page nav buttons).
    func glassCircle(interactive: Bool = true) -> some View {
        modifier(GlassShapeModifier(shape: Circle(), interactive: interactive, tint: nil))
    }

    /// Rounded-rect liquid glass (cards, sheets, info panels).
    func glassRoundedRect(_ radius: CGFloat,
                          interactive: Bool = false,
                          tint: Color? = nil) -> some View {
        modifier(GlassShapeModifier(
            shape: RoundedRectangle(cornerRadius: radius, style: .continuous),
            interactive: interactive,
            tint: tint))
    }
}

private struct GlassShapeModifier<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let tint: Color?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            var glass: Glass = .regular
            if let tint { glass = glass.tint(tint) }
            if interactive { glass = glass.interactive() }
            return AnyView(content.glassEffect(glass, in: shape))
        } else {
            return AnyView(
                content
                    .background(.ultraThinMaterial, in: shape)
                    .overlay(shape.stroke(Color.white.opacity(0.16), lineWidth: 0.5))
            )
        }
    }
}
