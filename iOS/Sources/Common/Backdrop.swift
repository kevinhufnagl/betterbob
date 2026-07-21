import BetterBobShared
import SwiftUI

/// Standard screen chrome: the shared BetterBob gradient behind the content,
/// hidden scroll background, large navigation title. Toolbars are left
/// untouched so iOS 26's own scroll-aware glass takes over.
struct BobScreen: ViewModifier {
    var title: String

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(DashboardBG().ignoresSafeArea())
            .navigationTitle(title)
    }
}

extension View {
    func bobScreen(title: String) -> some View {
        modifier(BobScreen(title: title))
    }
}
