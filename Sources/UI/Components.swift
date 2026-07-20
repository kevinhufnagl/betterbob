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
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
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
    static func workAccent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.40, green: 0.88, blue: 0.52)
                        : Color(red: 0.09, green: 0.50, blue: 0.24)
    }
    static func breakAccent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 1.00, green: 0.72, blue: 0.38)
                        : Color(red: 0.78, green: 0.42, blue: 0.04)
    }
    static func reasonAccent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.45, green: 0.72, blue: 1.00)
                        : Color(red: 0.10, green: 0.42, blue: 0.85)
    }
    /// Clock-out / stop red — muted in light mode where system red is too hot.
    static func outAccent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 1.00, green: 0.45, blue: 0.42)
                        : Color(red: 0.72, green: 0.16, blue: 0.14)
    }
}

// MARK: - Clock-state visual vocabulary

extension ClockState {
    var tint: Color {
        switch self {
        case .clockedOut: return .secondary
        case .working: return .green
        case .onBreak: return .orange
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
