import MyNotchCore
import SwiftUI

struct TabBar: View {
    let tabs: [NotchTab]
    let selected: ModuleID?
    let onSelect: (ModuleID) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tabs) { tab in
                Button { onSelect(tab.id) } label: {
                    Label(tab.title, systemImage: tab.systemImage)
                        .labelStyle(.iconOnly)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 24)
                        .foregroundStyle(tab.id == selected ? NotchTokens.primaryText : NotchTokens.secondaryText)
                        .background(tab.id == selected ? Color.white.opacity(0.14) : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tab.title)
                .accessibilityAddTraits(tab.id == selected ? .isSelected : [])
            }
        }
    }
}
