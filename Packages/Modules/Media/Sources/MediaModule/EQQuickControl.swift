import MyNotchCore
import NotchUI
import SwiftUI

/// The EQ at the end of the row above the player: the word "EQ", a menu of the profiles, the switch and "Chỉnh…", which opens the
/// Âm thanh tab. It reads and writes the state that module shares with this one (neither imports the other), so the switch here and
/// the one there are one switch, and it is drawn only while that module runs (`isAvailable`). One chip high, so the row is what
/// the chips make it.
struct EQQuickControl: View {
    static let height = MediaSourceChipsView.height
    static let editTitle = "Chỉnh…"
    /// What the menu says when every profile was deleted and the equalizer is flat.
    static let flatTitle = "Phẳng"
    static let emptyMenuTitle = "Chưa có hồ sơ"
    /// A profile name can be 40 characters; the menu shows this much of it.
    static let maxTitleWidth: CGFloat = 96
    /// Between this and the chips before it.
    static let leadingGap: CGFloat = 8

    /// One line of the menu.
    struct MenuItem: Identifiable, Equatable {
        let id: UUID
        let name: String
        let isSelected: Bool
    }

    /// Nil is a module built without one.
    let equalizer: EqualizerState?
    @State private var isHoveringEdit = false

    static func isShown(_ equalizer: EqualizerState?) -> Bool {
        equalizer?.isAvailable == true
    }

    var menuItems: [MenuItem] {
        equalizer?.profiles.map { MenuItem(id: $0.id, name: $0.name, isSelected: $0.id == equalizer?.selectedID) } ?? []
    }

    /// The selected profile's name, or "Phẳng" when there is none.
    var title: String { equalizer?.selected?.name ?? Self.flatTitle }

    var isOn: Binding<Bool> {
        Binding(get: { equalizer?.isEnabled ?? false }, set: { equalizer?.isEnabled = $0 })
    }

    func select(_ id: UUID) { equalizer?.select(id) }

    func edit() { equalizer?.openEditor?() }

    var body: some View {
        if Self.isShown(equalizer) {
            HStack(spacing: 6) {
                Text("EQ")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(NotchTokens.secondaryText)
                profileMenu
                Toggle("Bật EQ", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                editButton
            }
            .padding(.leading, Self.leadingGap)
            .frame(height: Self.height)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Bộ chỉnh âm")
        }
    }

    private var profileMenu: some View {
        Menu {
            if menuItems.isEmpty {
                Text(Self.emptyMenuTitle)
            }
            ForEach(menuItems) { item in
                // A switch in a menu is drawn with the check mark.
                Toggle(item.name, isOn: Binding(get: { item.isSelected }, set: { _ in select(item.id) }))
            }
        } label: {
            HStack(spacing: 3) {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: Self.maxTitleWidth, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .accessibilityHidden(true)
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(NotchTokens.primaryText)
            .padding(.horizontal, 7)
            .frame(height: Self.height)
            .background { Capsule().fill(NotchTokens.fill(0.14)) }
            .contentShape(Capsule())
        }
        // A button-style menu draws this label as it is; the borderless one flattens it to its text and ignores the width.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Hồ sơ EQ")
        .accessibilityValue(Text(title))
    }

    private var editButton: some View {
        Button(action: edit) {
            Text(Self.editTitle)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(NotchTokens.primaryText)
                .padding(.horizontal, 7)
                .frame(height: Self.height)
                .background { Capsule().fill(NotchTokens.fill(isHoveringEdit ? 0.14 : 0.08)) }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHoveringEdit = $0 }
        .help("Mở tab Âm thanh để chỉnh các băng")
    }
}
