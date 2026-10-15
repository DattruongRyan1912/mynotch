import MyNotchCore
import SwiftUI

/// The list of all live activities under the collapsed notch: one row each, its icon and a one-line summary. A row of a
/// module that has a tab opens it; the others are only text.
struct ActivityList: View {
    let rows: [ActivitySlot]
    let label: (ActivityCenter.Entry) -> String
    let hasTab: (ModuleID) -> Bool
    let open: (ModuleID) -> Void
    @Environment(\.notchSurface) private var surface

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                switch row {
                case .activity(let entry):
                    if hasTab(entry.module) {
                        Button { open(entry.module) } label: { content(entry) }.buttonStyle(ActivityRowStyle())
                    } else {
                        // Swallows the tap, so a click on a row that goes nowhere does not open the notch behind it.
                        content(entry).onTapGesture {}
                    }
                case .overflow(let count):
                    rowLayout {
                        Text("+\(count)").frame(width: NotchTokens.listIconSize)
                        Text(ActivityLabel.overflow(count: count))
                    }
                    .accessibilityElement(children: .combine)
                    .onTapGesture {}
                }
            }
        }
        .padding(.vertical, NotchGeometry.listInset)
        .accessibilityElement(children: .contain)
    }

    private func content(_ entry: ActivityCenter.Entry) -> some View {
        rowLayout {
            ActivityIcon(activity: entry.activity, size: NotchTokens.listIconSize, minimalSize: NotchTokens.listIconSize)
            Text(label(entry))
        }
        .accessibilityElement(children: .combine)
    }

    private func rowLayout<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            content()
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
        .foregroundStyle(surface.secondaryStyle)
        .lineLimit(1)
        .frame(height: NotchGeometry.listRowHeight)
        .contentShape(Rectangle())
    }
}

/// Dims a row a little while it is pressed.
private struct ActivityRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.5 : 1)
    }
}
