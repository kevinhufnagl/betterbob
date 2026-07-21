import SwiftUI

/// The app-wide glass surface: Liquid Glass with a hairline edge. Every card
/// and section composes this one modifier so the whole app shares a single
/// corner radius and stroke recipe.
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
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
    func glassSurface(cornerRadius: CGFloat = 18) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius))
    }
}
