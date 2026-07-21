import BetterBobShared
import SwiftUI

/// The app-wide backdrop: the shared BetterBob gradient with soft glows in
/// the brand's blues — the accent up top, a deeper navy below — so the
/// Liquid Glass surfaces have real color to refract instead of a flat grey.
struct BobBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    /// The icon background's deep navy, one register darker than the accent.
    private var deepNavy: Color {
        Color(red: 0.05, green: 0.14, blue: 0.22)
    }

    var body: some View {
        ZStack {
            DashboardBG()
            RadialGradient(
                colors: [Color.accentColor.opacity(scheme == .dark ? 0.32 : 0.20), .clear],
                center: .init(x: 0.15, y: 0.02), startRadius: 0, endRadius: 480)
            RadialGradient(
                colors: [deepNavy.opacity(scheme == .dark ? 0.55 : 0.16), .clear],
                center: .init(x: 1.05, y: 0.85), startRadius: 0, endRadius: 420)
            RadialGradient(
                colors: [Color.accentColor.opacity(scheme == .dark ? 0.16 : 0.10), .clear],
                center: .init(x: 0.9, y: 0.35), startRadius: 0, endRadius: 360)
        }
        .ignoresSafeArea()
    }
}

/// Standard screen chrome: the backdrop behind the content, hidden scroll
/// background, large navigation title. Toolbars are left untouched so
/// iOS 26's own scroll-aware glass takes over.
struct BobScreen: ViewModifier {
    var title: String

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(BobBackdrop())
            .navigationTitle(title)
    }
}

extension View {
    func bobScreen(title: String) -> some View {
        modifier(BobScreen(title: title))
    }
}
