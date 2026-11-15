import MyNotchCore
import SwiftUI

/// Where the user arranges the pages of the open notch: which are on the tab bar and which in its "Khác" item, and the order in each. Pages
/// are dragged within a section and between the two; a button and the row's menu move one too, and so do the accessibility actions. Only
/// modules that run and have a page are listed; the rest keep their place for when they run again.
struct TabOrderSettingsPage: View {
    let settings: SettingsStore
    let registry: ModuleRegistry

    var body: some View {
        let bar = registry.barTabs
        let overflow = registry.overflowTabs
        let arrangement = TabGroups.Arrangement(bar: bar.map(\.id), overflow: overflow.map(\.id))

        Form {
            Section {
                rows(bar, on: .bar, in: arrangement)
            } header: {
                Text("Trên thanh Notch")
            }

            Section {
                rows(overflow, on: .overflow, in: arrangement)
            } header: {
                Text("Trong mục Khác (Thu gọn)")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bar.count + overflow.count < 2
                        ? "Cần ít nhất hai mô-đun có trang trên notch mới sắp xếp được."
                        : "Kéo để đổi thứ tự các trang, hoặc kéo sang phần kia để đổi chỗ. Vuốt hai ngón cũng đi theo thứ tự này.")
                    Text("Các trang trong mục Khác vẫn có thể mở nhanh được bằng phím tắt.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Button("Khôi phục thứ tự mặc định") {
                    settings.reset(ModuleRegistry.tabOrderKey)
                    settings.reset(ModuleRegistry.tabOverflowKey)
                }
                .buttonStyle(.bordered)
                .disabled(settings.value(ModuleRegistry.tabOrderKey).isEmpty && settings.value(ModuleRegistry.tabOverflowKey) == nil)
            }
        }
        .formStyle(.grouped)
    }

    /// The rows of one side, which is also where a page dragged into it lands: before the row it is dropped on, or at the end.
    @ViewBuilder private func rows(_ tabs: [NotchTab], on side: TabGroups.Side, in arrangement: TabGroups.Arrangement) -> some View {
        ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
            row(tab, index: index, of: tabs.count, on: side, in: arrangement)
        }
        if tabs.isEmpty {
            Text(side == .bar ? "Kéo một trang lên đây." : "Kéo một trang vào đây để gom vào mục Khác.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .dropDestination(for: String.self) { dropped, _ in accept(dropped, on: side, in: arrangement) }
        }
    }

    private func row(_ tab: NotchTab, index: Int, of count: Int, on side: TabGroups.Side, in arrangement: TabGroups.Arrangement) -> some View {
        let other = side.other
        return HStack(spacing: 10) {
            AppleSidebarIconBadge(
                visuals: AppleSettingsVisuals.forModule(tab.id, fallbackImage: tab.systemImage),
                size: 22
            )

            Text(tab.title)
                .font(.system(size: 13))

            Spacer()

            Button(other.moveTitle) { move(tab.id, to: other, in: arrangement) }
                .buttonStyle(.bordered)
                .controlSize(.small)

            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .draggable(tab.id.rawValue)
        .dropDestination(for: String.self) { dropped, _ in accept(dropped, before: tab.id, in: arrangement) }
        .contextMenu {
            Button("Chuyển lên") { move(tab.id, to: side, at: index - 1, in: arrangement) }.disabled(index == 0)
            Button("Chuyển xuống") { move(tab.id, to: side, at: index + 1, in: arrangement) }.disabled(index == count - 1)
            Divider()
            Button(other.moveTitle) { move(tab.id, to: other, in: arrangement) }
        }
        .accessibilityAction(named: "Chuyển lên") { move(tab.id, to: side, at: index - 1, in: arrangement) }
        .accessibilityAction(named: "Chuyển xuống") { move(tab.id, to: side, at: index + 1, in: arrangement) }
        .accessibilityAction(named: other.moveTitle) { move(tab.id, to: other, in: arrangement) }
    }

    /// `page` moved to `side` at `index`, which is the end of it by default.
    private func move(_ page: ModuleID, to side: TabGroups.Side, at index: Int = .max, in arrangement: TabGroups.Arrangement) {
        save(TabGroups.moving(page, to: side, at: index, in: arrangement))
    }

    /// A page dropped on an empty `side`, which is where it lands. False for what is not a page that is listed.
    @discardableResult private func accept(_ dropped: [String], on side: TabGroups.Side, in arrangement: TabGroups.Arrangement) -> Bool {
        guard let page = listed(dropped, in: arrangement) else { return false }
        move(page, to: side, at: 0, in: arrangement)
        return true
    }

    /// A page dropped on the row of `target`, which is where it lands: just before it.
    @discardableResult private func accept(_ dropped: [String], before target: ModuleID, in arrangement: TabGroups.Arrangement) -> Bool {
        guard let page = listed(dropped, in: arrangement) else { return false }
        save(TabGroups.moving(page, before: target, in: arrangement))
        return true
    }

    private func listed(_ dropped: [String], in arrangement: TabGroups.Arrangement) -> ModuleID? {
        dropped.first.flatMap { ModuleID(rawValue: $0) }.flatMap { arrangement.bar.contains($0) || arrangement.overflow.contains($0) ? $0 : nil }
    }

    /// Stores `visible` as the order and the placement, keeping the place of the modules that are not on screen.
    private func save(_ visible: TabGroups.Arrangement) {
        let stored = TabGroups.stored(
            for: visible, order: settings.value(ModuleRegistry.tabOrderKey), overflow: settings.value(ModuleRegistry.tabOverflowKey)
        )
        settings.set(stored.order, for: ModuleRegistry.tabOrderKey)
        settings.set(stored.overflow, for: ModuleRegistry.tabOverflowKey)
    }
}

private extension TabGroups.Side {
    var other: TabGroups.Side { self == .bar ? .overflow : .bar }

    /// What moving a page onto this side is called.
    var moveTitle: String { self == .overflow ? "Chuyển vào Khác" : "Đưa lên thanh" }
}
