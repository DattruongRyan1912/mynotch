import AppKit
import Combine
import KeyboardShortcuts
import MyNotchCore
import NotchUI
import SwiftUI

struct GeneralSettingsPage: View {
    let settings: SettingsStore
    let hotkeys: HotkeyRegistry
    let configSync: ConfigSyncService
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var needsApproval = LaunchAtLogin.needsApproval
    @State private var launchError: String?
    @State private var shortcutRevision = 0

    var body: some View {
        Form {
            Section("Khởi động & Menu Bar") {
                Toggle(isOn: Binding(
                    get: { launchAtLogin },
                    set: { enabled in
                        launchError = LaunchAtLogin.set(enabled)
                        if let launchError {
                            Log.logger(category: "app").error("Launch at login change failed: \(launchError, privacy: .public)")
                        }
                        refreshLaunchAtLogin()
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Khởi động cùng máy")
                        if needsApproval {
                            HStack(spacing: 4) {
                                Text("Cần cho phép trong Login Items.")
                                    .font(.caption).foregroundStyle(.orange)
                                Button("Mở Login Items") { LaunchAtLogin.openLoginItemsSettings() }
                                    .buttonStyle(.link)
                                    .font(.caption)
                            }
                        }
                    }
                }

                if let launchError {
                    Text(launchError).foregroundStyle(.red).font(.caption)
                }

                Toggle(isOn: settings.binding(AppSettings.showMenuBarIcon)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hiện biểu tượng trên menu bar")
                        Text("Khi ẩn icon, mở lại MyNotch từ Finder để vào Cài đặt.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            MenuBarHiderSettingsSection(settings: settings)

            Section {
                Picker("Ẩn MyNotch khi quay hoặc chia sẻ màn hình", selection: settings.binding(InterfaceSettings.hideFromCapture)) {
                    Text("Không ẩn").tag(CaptureHiding.never)
                    Text("Chỉ khi notch đóng").tag(CaptureHiding.whenCollapsed)
                    Text("Luôn ẩn").tag(CaptureHiding.always)
                }
            } header: {
                Text("Quay và chia sẻ màn hình")
            } footer: {
                Text("Áp dụng cho notch, bảng và thư viện Clipboard, màn hình khoá và khung xếp cửa sổ. Các cửa sổ khác của MyNotch, như Cài đặt hay trình chú thích ảnh chụp, vẫn hiện.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Phím tắt toàn cục") {
                ForEach(hotkeys.registrations) { registration in
                    KeyboardShortcuts.Recorder(registration.title, name: registration.name) { _ in shortcutRevision += 1 }
                }
                let conflicts = shortcutRevision >= 0 ? hotkeys.conflicts() : []
                ForEach(conflicts.indices, id: \.self) { index in
                    Label("Trùng phím: " + conflicts[index].map(\.title).joined(separator: ", "), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                HStack {
                    Text("Đường dẫn:").foregroundStyle(.secondary)
                    Text(configSync.displayPath)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Button("Mở Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([configSync.configFileURL])
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                HStack {
                    Button("Tải lại tệp") {
                        _ = configSync.reload()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Xuất cài đặt hiện tại") {
                        _ = try? configSync.exportCurrentSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let error = configSync.lastLoadError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                } else if let loadedAt = configSync.lastLoadedAt {
                    Text("Đã áp dụng \(configSync.appliedKeyCount) cài đặt lúc \(loadedAt.formatted(date: .omitted, time: .standard))")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            } header: {
                Text("Tệp cấu hình (Dotfiles)")
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshLaunchAtLogin)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLaunchAtLogin()
        }
    }

    private func refreshLaunchAtLogin() { launchAtLogin = LaunchAtLogin.isEnabled; needsApproval = LaunchAtLogin.needsApproval }
}
