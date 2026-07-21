import SwiftUI

struct TodayTab: View {
    @ObservedObject var state: BobState

    var body: some View {
        ScrollView {
            if state.signedIn {
                TodayTimeline(state: state)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
            } else {
                signInCard
                    .padding(24)
            }
        }
        .background(DashboardBG())
        .navigationTitle("Today")
        .refreshable { await state.reconcile() }
    }

    /// The popover's signed-out prompt, restaged for a phone screen.
    private var signInCard: some View {
        VStack(spacing: 10) {
            AnimatedBob(sleeping: true).frame(width: 96, height: 96)
            Text("Bob's off the clock")
                .font(.system(size: 16, weight: .semibold))
            if !state.autoLoginInProgress {
                Text("Sign in to HiBob to get going")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if state.autoLoginInProgress {
                AutoLoginInline(state: state, fillWidth: true)
            } else if state.canAutoSignIn {
                VStack(spacing: 10) {
                    SignInFactorGroup(state: state)
                    Button("More options") {
                        NotificationCenter.default.post(name: .presentOnboarding, object: nil)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            } else {
                Button {
                    NotificationCenter.default.post(name: .presentOnboarding, object: nil)
                } label: {
                    Label("Sign in…", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}
