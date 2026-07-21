import SwiftUI

/// A pill-shaped date/time field: a capsule showing the value that opens a
/// graphical picker in a popover — no native spinner arrows anywhere.
struct PillDateField: View {
    @Binding var date: Date
    var components: DatePickerComponents = .date
    var range: ClosedRange<Date>? = nil
    @State private var open = false

    private var text: String {
        let f = DateFormatter()
        f.dateFormat = components == .date ? "EEE, d MMM" : "HH:mm"
        return f.string(from: date)
    }

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: components == .date ? "calendar" : "clock")
                    .font(.system(size: 11, weight: .semibold))
                Text(text).font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 12).frame(height: 30)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.8))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            Group {
                if components == .date {
                    picker.datePickerStyle(.graphical).frame(width: 300)
                } else {
                    #if os(macOS)
                    picker.datePickerStyle(.field).labelsHidden()
                    #else
                    picker.datePickerStyle(.compact).labelsHidden()
                    #endif
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder private var picker: some View {
        if let range {
            DatePicker("", selection: $date, in: range, displayedComponents: components).labelsHidden()
        } else {
            DatePicker("", selection: $date, displayedComponents: components).labelsHidden()
        }
    }
}

/// A pill-shaped stepper: −  value  +  in one capsule, no native arrows.
struct PillStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    let format: (Int) -> String

    var body: some View {
        HStack(spacing: 2) {
            button("minus") { value = max(range.lowerBound, value - step) }
            Text(format(value))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(minWidth: 62)
                .contentTransition(.numericText())
            button("plus") { value = min(range.upperBound, value + step) }
        }
        .padding(.horizontal, 4).frame(height: 30)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.8))
        .animation(.snappy, value: value)
    }

    private func button(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                .frame(width: 26, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
