import MyNotchCore
import SwiftUI

/// Where the user arranges the pages of the open notch by dragging. Only modules that run and have a page are listed;
/// the rest keep their place in the stored order for when they run again.
struct TabOrderSettingsPage: View {
    let settings: SettingsStore
    let registry: ModuleRegistry

    var body: some View {
        let tabs = registry.tabs
        VStack(spacing: 0) {
            List {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    HStack {
                        Label(tab.title, systemImage: tab.systemImage)
                        Spacer()
                        Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                    .accessibilityAction(named: "Chuyển lên") { move(tabs, from: index, to: index - 1) }
                    .accessibilityAction(named: "Chuyển xuống") { move(tabs, from: index, to: index + 1) }
                }
                .onMove { source, destination in
                    var ids = tabs.map(\.id)
                    ids.move(fromOffsets: source, toOffset: destination)
                    save(ids)
                }
            }
            Divider()
            HStack {
                Text(tabs.count < 2
                    ? "Cần ít nhất hai module có trang trên notch mới sắp xếp được."
                    : "Kéo để đổi thứ tự các trang khi notch mở rộng. Vuốt hai ngón cũng đi theo thứ tự này.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Thứ tự mặc định") { settings.reset(ModuleRegistry.tabOrderKey) }
                    .disabled(settings.value(ModuleRegistry.tabOrderKey).isEmpty)
            }
            .padding(12)
        }
        .navigationTitle("Trang trên notch")
    }

    /// Moves the tab at `index` to `target` (one place up or down), if there is such a place.
    private func move(_ tabs: [NotchTab], from index: Int, to target: Int) {
        guard tabs.indices.contains(target) else { return }
        var ids = tabs.map(\.id)
        ids.swapAt(index, target)
        save(ids)
    }

    private func save(_ visible: [ModuleID]) {
        settings.set(TabOrder.updated(stored: settings.value(ModuleRegistry.tabOrderKey), visible: visible), for: ModuleRegistry.tabOrderKey)
    }
}
