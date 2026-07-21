import BetterBobShared
import WidgetKit
import SwiftUI

/// The mascot-first circular widget: Bob's face fills the circle and his
/// expression IS the status — eyes open while working, sunglasses on a
/// break, asleep when clocked out. No numbers; those live in the other
/// widget slots.
struct BobFaceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BobFace", provider: SnapshotProvider()) { entry in
            BobFaceWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Bob")
        .description("Bob shows your clock state at a glance — shades on breaks, asleep when clocked out.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct BobFaceWidgetView: View {
    let entry: SnapshotEntry

    private var expression: BobFaceMark.Expression {
        switch entry.snapshot?.state {
        case .working: return .awake
        case .onBreak: return .shades
        default: return .asleep
        }
    }

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            BobFaceMark(expression: expression)
                .frame(width: 40, height: 40)
        }
    }
}
