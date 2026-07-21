import SwiftUI

/// An inset-grouped-List look built on the shared glass surface: uppercase
/// header, one glass card of rows, footnote footer. Rows hold native
/// controls (Toggle, LabeledContent, Picker) so they read like Settings.
struct GlassGroupedSection<Content: View>: View {
    var header: String?
    var footer: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let header {
                Text(header.uppercased())
                    .font(.footnote.weight(.semibold))
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 16)
            }
            VStack(spacing: 0) { content() }
                .modifier(GlassSurface())
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
        }
    }
}

/// One row inside a GlassGroupedSection. `showDivider: false` on the first row.
struct GlassRow<Content: View>: View {
    var showDivider = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            if showDivider {
                Divider().opacity(0.6).padding(.leading, 16)
            }
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
        }
    }
}
