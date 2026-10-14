import AppKit
import Combine
import KeyboardShortcuts
import MyNotchCore
import NotchUI
import SwiftUI

struct GeneralSettingsPage: View {
    let settings: SettingsStore
    let hotkeys: HotkeyRegistry
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var needsApproval = LaunchAtLogin.needsApproval
    @State private var launchError: String?
    @State private var shortcutRevision = 0

    var body: some View {
        Form {
            Section("Khởi động") {
                Toggle("Khởi động cùng máy", isOn: Binding(
                    get: { launchAtLogin },
                    set: { enabled in
                        launchError = LaunchAtLogin.set(enabled)
                        if let launchError {
                            Log.logger(category: "app").error("Launch at login change failed: \(launchError, privacy: .public)")
                        }
                        refreshLaunchAtLogin()
                    }
                ))
                if needsApproval {
                    HStack {
                        Text("macOS cần bạn cho phép MyNotch trong Login Items.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Mở Login Items") { LaunchAtLogin.openLoginItemsSettings() }
                    }
                }
                if let launchError {
                    Text(launchError).foregroundStyle(.red).font(.caption)
                }
                Toggle("Hiện icon trên menu bar", isOn: settings.binding(AppSettings.showMenuBarIcon))
                Text("Khi ẩn icon, mở lại MyNotch từ Finder để vào Settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Quay và chia sẻ màn hình") {
                Picker("Ẩn MyNotch khi quay hoặc chia sẻ màn hình", selection: settings.binding(InterfaceSettings.hideFromCapture)) {
                    Text("Không ẩn").tag(CaptureHiding.never)
                    Text("Chỉ khi notch đóng").tag(CaptureHiding.whenCollapsed)
                    Text("Luôn ẩn").tag(CaptureHiding.always)
                }
                Text("Chỉ áp dụng cho notch. Cửa sổ thư viện clipboard và các cửa sổ nổi vẫn hiện.")
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
        .onAppear(perform: refreshLaunchAtLogin)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLaunchAtLogin()
        }
    }

    private func refreshLaunchAtLogin() { launchAtLogin = LaunchAtLogin.isEnabled; needsApproval = LaunchAtLogin.needsApproval }
}
