import BetterBobShared
import SwiftUI
import WebKit

/// Presents the shared SSO controller's web view whenever a sign-in runs.
/// Swiping the sheet away cancels the attempt.
struct SignInSheetModifier: ViewModifier {
    @ObservedObject var controller = SSOSignInController.shared

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(
            get: { controller.sheetWebView != nil },
            set: { if !$0 { controller.cancel() } }
        )) {
            if let web = controller.sheetWebView {
                SignInWebView(webView: web)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
    }
}

private struct SignInWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}

extension View {
    func signInSheet() -> some View { modifier(SignInSheetModifier()) }
}
