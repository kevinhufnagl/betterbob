import SwiftUI

/// The app-wide glass surface: Liquid Glass with a hairline edge. Every card
/// and section composes this one modifier so the whole app shares a single
/// corner radius and stroke recipe.
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 18
    /// Washes the glass itself in a color — warning banners and other
    /// semantic surfaces; nil keeps the plain material.
    var tint: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .glassEffect(tint.map { Glass.regular.tint($0.opacity(0.22)) } ?? .regular, in: shape)
            .overlay(
                shape.strokeBorder(
                    tint.map { $0.opacity(0.35) } ?? Color.white.opacity(0.08),
                    lineWidth: tint == nil ? 0.5 : 0.7)
            )
    }
}

/// A padded glass card — the basic building block of every screen.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(GlassSurface())
    }
}

extension View {
    func glassSurface(cornerRadius: CGFloat = 18, tint: Color? = nil) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, tint: tint))
    }
}
