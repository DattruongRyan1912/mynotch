import KeyboardShortcuts
import MyNotchCore
import SwiftUI

struct GeneralSettingsPage: View {
    let settings: SettingsStore
    let hotkeys: HotkeyRegistry
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?
    @State private var shortcutRevision = 0

    var body: some View {
        Form {
            Section("Khởi động") {
                Toggle("Khởi động cùng máy", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        launchError = LaunchAtLogin.set(enabled)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                if let launchError {
                    Text(launchError).foregroundStyle(.red).font(.caption)
                }
                Toggle("Hiện icon trên menu bar", isOn: settings.binding(AppSettings.showMenuBarIcon))
                Text("Khi ẩn icon, mở lại MyNotch từ Finder để vào Settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Phím tắt") {
                ForEach(hotkeys.registrations) { registration in
                    KeyboardShortcuts.Recorder(registration.title, name: registration.name) { _ in shortcutRevision += 1 }
                }
                let conflicts = shortcutRevision >= 0 ? hotkeys.conflicts() : []
                ForEach(conflicts.indices, id: \.self) { index in
                    Label("Trùng phím: " + conflicts[index].map(\.title).joined(separator: ", "), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}
