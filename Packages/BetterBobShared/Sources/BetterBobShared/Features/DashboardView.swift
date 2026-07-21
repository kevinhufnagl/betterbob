import SwiftUI
import Charts

// Shared dashboard building blocks (cards, tiles, palette, date helpers).
// The window shell lives in MainWindow.swift; the panes in DashboardSections.

/// A section header used at the top of each pane.
struct PaneHeader: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 22, weight: .bold))
            if let subtitle {
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Subtle top-down gradient so the glass cards have something to sit on.
public struct DashboardBG: View {
    @Environment(\.colorScheme) private var scheme
    public init() {}
    public var body: some View {
        LinearGradient(
            colors: scheme == .dark
                ? [Color(red: 0.11, green: 0.12, blue: 0.15), Color(red: 0.07, green: 0.07, blue: 0.09)]
                : [Color(red: 0.96, green: 0.97, blue: 0.99), Color(red: 0.92, green: 0.93, blue: 0.96)],
            startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Reusable card + tiles

struct Card<Content: View>: View {
    var title: String? = nil
    var symbol: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Label {
                    Text(title.uppercased()).kerning(0.5)
                } icon: {
                    if let symbol { Image(systemName: symbol) }
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        // primary-based border + soft shadow so the card's true extent is
        // visible in light mode too (a white hairline vanishes there, making
        // cards read narrower than the hero).
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }
}

/// A KPI tile: big value, small caption, optional accent + trailing glyph.
struct StatTile: View {
    let value: String
    let caption: String
    var tint: Color = .primary
    var symbol: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(value).font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(Motion.numeric, value: value)
            Text(caption.uppercased()).kerning(0.4)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }
}

// MARK: - Date helpers

enum DayFmt {
    static let iso: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian); f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"; return f
    }()
    static func date(_ s: String) -> Date? { iso.date(from: s) }
    static func today() -> String { iso.string(from: Date()) }
}

func hoursText(_ h: Double) -> String {
    let m = Int((h * 60).rounded()); return "\(m / 60)h \(String(format: "%02d", m % 60))m"
}
func signedHours(_ h: Double) -> String {
    let m = Int((abs(h) * 60).rounded())
    return "\(h < 0 ? "−" : "+")\(m / 60)h \(String(format: "%02d", m % 60))m"
}
