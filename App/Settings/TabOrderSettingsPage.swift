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
        VStack(spacing: 0) {
            List {
                SwiftUI.Section("Trên thanh") { rows(bar, on: .bar, in: arrangement) }
                SwiftUI.Section("Trong mục Khác") { rows(overflow, on: .overflow, in: arrangement) }
            }
            Divider()
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bar.count + overflow.count < 2
                        ? "Cần ít nhất hai module có trang trên notch mới sắp xếp được."
                        : "Kéo để đổi thứ tự các trang, hoặc kéo sang phần kia để đổi chỗ. Vuốt hai ngón cũng đi theo thứ tự này, mục Khác là một điểm dừng.")
                    Text("Các trang trong mục Khác vẫn mở được bằng phím tắt.")
                }
                .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Thứ tự mặc định") {
                    settings.reset(ModuleRegistry.tabOrderKey)
                    settings.reset(ModuleRegistry.tabOverflowKey)
                }
                .disabled(settings.value(ModuleRegistry.tabOrderKey).isEmpty && settings.value(ModuleRegistry.tabOverflowKey) == nil)
            }
            .padding(12)
        }
        .navigationTitle("Trang trên notch")
    }

    /// The rows of one side, which is also where a page dragged into it lands: before the row it is dropped on, or at the end.
    @ViewBuilder private func rows(_ tabs: [NotchTab], on side: TabGroups.Side, in arrangement: TabGroups.Arrangement) -> some View {
        ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
            row(tab, index: index, on: side, in: arrangement)
        }
        if tabs.isEmpty {
            Text(side == .bar ? "Kéo một trang lên đây." : "Kéo một trang vào đây để gom vào mục Khác.")
                .foregroundStyle(.secondary)
                .dropDestination(for: String.self) { dropped, _ in accept(dropped, on: side, at: 0, in: arrangement) }
        }
    }

    private func row(_ tab: NotchTab, index: Int, on side: TabGroups.Side, in arrangement: TabGroups.Arrangement) -> some View {
        let other = side.other
        return HStack {
            Label(tab.title, systemImage: tab.systemImage)
            Spacer()
            Button(other.moveTitle) { move(tab.id, to: other, in: arrangement) }
                .buttonStyle(.borderless).font(.caption)
            Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .draggable(tab.id.rawValue)
        .dropDestination(for: String.self) { dropped, _ in accept(dropped, on: side, at: index, in: arrangement) }
        .contextMenu { Button(other.moveTitle) { move(tab.id, to: other, in: arrangement) } }
        .accessibilityAction(named: "Chuyển lên") { move(tab.id, to: side, at: index - 1, in: arrangement) }
        .accessibilityAction(named: "Chuyển xuống") { move(tab.id, to: side, at: index + 1, in: arrangement) }
        .accessibilityAction(named: other.moveTitle) { move(tab.id, to: other, in: arrangement) }
    }

    /// `page` moved to `side` at `index`, which is the end of it by default.
    private func move(_ page: ModuleID, to side: TabGroups.Side, at index: Int = .max, in arrangement: TabGroups.Arrangement) {
        save(TabGroups.moving(page, to: side, at: index, in: arrangement))
    }

    /// A page dropped on `side` at `index`. False for what is not a page that is listed.
    @discardableResult private func accept(_ dropped: [String], on side: TabGroups.Side, at index: Int, in arrangement: TabGroups.Arrangement) -> Bool {
        guard let page = dropped.first.flatMap({ ModuleID(rawValue: $0) }),
              arrangement.bar.contains(page) || arrangement.overflow.contains(page) else { return false }
        move(page, to: side, at: index, in: arrangement)
        return true
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
