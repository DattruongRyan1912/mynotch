import MyNotchCore
import SwiftUI

/// Plain rows: the Settings page provides the Form and the section. They work whether or not the module runs.
struct ShortcutsSettingsView: View {
    static let hotkeyNote = "Mỗi shortcut ưa thích có thể có phím tắt toàn cục riêng, đặt trong mục Phím tắt."

    let module: ShortcutsModule
    let settings: ModuleSettings
    let keys: ShortcutsSettingKeys

    var body: some View {
        Group {
            LabeledContent("Shortcut ưa thích") {
                if module.state.isLoading {
                    ProgressView().controlSize(.small)
                }
                Button("Làm mới", systemImage: "arrow.clockwise") { Task { await module.refresh() } }
                    .disabled(module.state.isLoading)
            }
            list
            Text(Self.hotkeyNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task { if module.state.shortcuts.isEmpty { await module.refresh() } }
    }

    @ViewBuilder private var list: some View {
        let shortcuts = module.state.shortcuts
        if let error = module.state.listError {
            Text("Không đọc được danh sách: \(error)")
                .font(.caption)
                .foregroundStyle(.red)
        }
        if shortcuts.isEmpty {
            Text("Không có shortcut nào.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(shortcuts) { shortcut in
                        Toggle(shortcut.name, isOn: Binding(
                            get: { settings.value(keys.favorites).contains(shortcut.id) },
                            set: { isOn in
                                settings.set(ShortcutFavorites.setting(shortcut.id, isFavorite: isOn, in: settings.value(keys.favorites)), for: keys.favorites)
                            }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 180)
        }
    }
}
