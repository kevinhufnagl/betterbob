import SwiftUI

// MARK: - Small shared components (same family as BetterVPN/Colimate)

extension View {
    /// Instant tooltip.
    func fastTooltip(_ text: String) -> some View {
        help(text)
    }
}

/// Shared chrome for a window page: one glass-effect rounded container.
extension View {
    func pagePanelChrome() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
            .clipShape(.rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.05), lineWidth: 0.5)
            )
    }
}

/// Single-line page header: icon, title, optional subtitle.
struct PageHeader: View {
    let icon: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(0.06)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6))
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

/// Subtle inset card for content nested inside a glass page panel.
extension View {
    func insetCard(cornerRadius: CGFloat = 12) -> some View {
        self
            .background(Color.primary.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
    }

    /// A solid, slightly-elevated grouped card — the iOS/macOS System Settings
    /// look. Use one per settings section with a header above it.
    func settingsCard(cornerRadius: CGFloat = 12) -> some View {
        self
            .background(Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }
}

/// A titled settings section: an uppercase header above one solid grouped card.
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold)).kerning(0.5)
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .settingsCard()
        }
    }
}

/// Small uppercase section caption used inside cards.
struct SectionCaption: View {
    let text: String
    let symbol: String

    init(_ text: String, symbol: String) {
        self.text = text
        self.symbol = symbol
    }

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Theme-adaptive accent colors
//
// The stock .green/.orange read as washed-out on the popover's glass panel.
// These are hand-picked to stay legible in both appearances: deeper and more
// saturated in light mode, brighter in dark mode.
extension Color {
    /// The Mac's accent hue re-lit with our own saturation/brightness recipe
    /// — how every brand color stays legible in both appearances while
    /// following System Settings.
    static func systemAccentHued(sat: Double, bri: Double) -> Color {
        Color(hue: accentHue, saturation: sat, brightness: bri)
    }

    /// The Mac's accent hue (0…1).
    static var accentHue: Double {
        var h: CGFloat = 0.51, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        (NSColor.controlAccentColor.usingColorSpace(.deviceRGB) ?? .systemTeal)
            .getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Double(h)
    }

    /// Re-light any hue with our saturation/brightness recipe — used to build
    /// the water in the accent hue, or in bobOrange/bobRed for over-limit days.
    static func hued(_ hue: Double, sat: Double, bri: Double) -> Color {
        Color(hue: hue, saturation: sat, brightness: bri)
    }

    /// This color's hue (0…1), so a fixed brand color can be re-lit by `hued`.
    var hueComponent: Double {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        (NSColor(self).usingColorSpace(.deviceRGB) ?? .systemTeal)
            .getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Double(h)
    }

    /// BetterBob's primary accent — the system accent color (the same one
    /// buttons and sidebar selections wear), deepened for light mode and
    /// brightened for dark so it stays legible. Replaces the old work green
    /// and the popover's system blue.
    static func primaryAccent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? systemAccentHued(sat: 0.65, bri: 0.85)
                        : systemAccentHued(sat: 0.85, bri: 0.50)
    }
    /// A brighter cut of the accent for control fills and borders — close to
    /// the raw system accent native filled controls wear. Text should keep
    /// `primaryAccent`, which is deepened for legibility.
    static func controlAccent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? systemAccentHued(sat: 0.60, bri: 0.95)
                        : systemAccentHued(sat: 0.80, bri: 0.72)
    }
    /// Fixed mid-tone for contexts that can't read the color scheme
    /// (menu-bar tint, clock-state dots) — legible on both appearances.
    static var bobTeal: Color { systemAccentHued(sat: 0.82, bri: 0.62) }
    /// Fixed warm tones tuned to complement the teal: a coral-leaning orange
    /// for break/attention and a rose-leaning red for hard warnings.
    static let bobOrange = Color(red: 0.88, green: 0.47, blue: 0.24)
    static let bobRed = Color(red: 0.85, green: 0.27, blue: 0.33)
    /// A cool violet, distinct from teal/orange/red — flags a past day whose
    /// work entries carry no reason (untagged).
    static let bobViolet = Color(red: 0.58, green: 0.44, blue: 0.86)

    static func workAccent(_ scheme: ColorScheme) -> Color {
        primaryAccent(scheme)
    }
    static func breakAccent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 1.00, green: 0.63, blue: 0.43)
                        : Color(red: 0.75, green: 0.34, blue: 0.13)
    }
    static func reasonAccent(_ scheme: ColorScheme) -> Color {
        primaryAccent(scheme)
    }
    /// Clock-out / stop red — rose-leaning to sit well next to the teal,
    /// muted in light mode where system red is too hot.
    static func outAccent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 1.00, green: 0.44, blue: 0.50)
                        : Color(red: 0.72, green: 0.15, blue: 0.23)
    }
}

// MARK: - Clock-state visual vocabulary

extension ClockState {
    var tint: Color {
        switch self {
        case .clockedOut: return .secondary
        case .working: return .bobTeal
        case .onBreak: return .bobOrange
        }
    }

    var symbol: String {
        switch self {
        case .clockedOut: return "clock"
        case .working: return "clock.fill"
        case .onBreak: return "pause.circle.fill"
        }
    }

    var title: String {
        switch self {
        case .clockedOut: return "Clocked out"
        case .working: return "Working"
        case .onBreak: return "On break"
        }
    }
}

/// The three second-factor methods as one tied-together button group; each
/// starts the automatic sign-in for that factor (one click, code field or push
/// wait appears in place). Shared by the popover and the sign-in window.
struct SignInFactorGroup: View {
    @ObservedObject var state: BobState

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(SignInFactor.allCases.enumerated()), id: \.element.id) { i, factor in
                if i > 0 { Divider().frame(height: 34) }
                Button { state.startAutoSignIn(factor: factor) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: factor.icon).font(.system(size: 13, weight: .semibold))
                        Text(factor.shortLabel).font(.system(size: 10, weight: .medium))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

/// Inline auto sign-in card: shown wherever auto sign-in is started (popover,
/// onboarding, dashboard, settings) instead of a separate window. The code
/// field is available right away so the user can enter it while the hidden
/// browser is still filling email + password in the background; a small step
/// line tracks progress, and the button shows a "verifying" state after submit.
struct AutoLoginInline: View {
    @ObservedObject var state: BobState
    /// Fill the container width (popover) instead of the capped card width used
    /// in wide windows.
    var fillWidth = false
    @State private var code = ""
    @FocusState private var focused: Bool

    private var trimmed: String { code.trimmingCharacters(in: .whitespaces) }
    private var canSubmit: Bool { trimmed.count >= 4 && !state.otpSubmitting }
    /// This sign-in uses push (no code field at any point).
    private var isPush: Bool { state.signInFactor?.isPush == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 30, height: 30)
                    Image(systemName: isPush ? "bell.badge.fill" : "lock.shield.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(headerTitle)
                        .font(.system(size: 12, weight: .semibold))
                    Text(substatus)
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if isPush {
                // Push sign-in: no code field ever — just wait for phone approval.
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(state.pushPending
                         ? "Waiting for you to approve the push in Okta Verify."
                         : "A push is on its way to your phone.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 8) {
                    // Plain field (not secure) marked as a one-time code: enables
                    // macOS AutoFill and 1Password Universal Autofill (Cmd-\).
                    TextField("000000", text: $code)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .textContentType(.oneTimeCode)
                        .focused($focused)
                        .disabled(state.otpSubmitting)
                        .frame(maxWidth: .infinity)
                        // Vertical padding rather than a fixed height, so the glyphs
                        // (and the placeholder) are never clipped when unfocused.
                        .padding(.vertical, 9)
                        .padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(focused ? 0.5 : 0.12), lineWidth: 1))
                        .onSubmit(submit)

                    Button(action: submit) {
                        Group {
                            if state.otpSubmitting {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Sign in")
                            }
                        }
                        .frame(width: 56, height: 20)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canSubmit)
                    .keyboardShortcut(.defaultAction)
                }

                if let err = state.otpError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10)).foregroundStyle(Color.bobOrange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button("Cancel", action: state.cancelAutoSignIn)
                .buttonStyle(.plain)
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(14)
        .frame(maxWidth: fillWidth ? .infinity : 300)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .animation(.easeInOut(duration: 0.15), value: state.otpSubmitting)
        .animation(.easeInOut(duration: 0.15), value: state.autoLoginStatus)
        .animation(.easeInOut(duration: 0.15), value: state.otpError)
        .animation(.easeInOut(duration: 0.15), value: state.pushPending)
        .onAppear { if !isPush { focused = true } }
    }

    private var headerTitle: String {
        if isPush { return state.pushPending ? "Approve on your phone" : "Signing you in…" }
        return "Two-factor code"
    }

    private var substatus: String {
        if isPush { return state.pushPending ? "Sent to your phone" : (state.autoLoginStatus.isEmpty ? "Connecting…" : state.autoLoginStatus) }
        if state.otpSubmitting { return "Verifying your code…" }
        if state.awaitingOTP { return "Ready — enter the code from your app" }
        return state.autoLoginStatus.isEmpty ? "Signing you in…" : state.autoLoginStatus
    }

    private func submit() {
        guard canSubmit else { return }
        state.submitOTP(trimmed)
    }
}
