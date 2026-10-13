import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Plain rows: the Settings page provides the Form and the section.
struct MediaSettingsView: View {
    /// System Settings › Privacy & Security › Screen & System Audio Recording, where "System Audio Recording Only" is.
    static let audioCaptureSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!

    @Binding var showActivity: Bool
    @Binding var pauseGraceSeconds: Int
    @Binding var hiddenApps: [String]
    @Binding var realSpectrum: Bool
    /// Only for the permission hint; the module keeps the store for its whole life, running or not.
    let store: NowPlayingStore

    var body: some View {
        Group {
            Toggle("Hiện bên cạnh notch khi đang phát nhạc", isOn: $showActivity)
            Group {
                Stepper(value: $pauseGraceSeconds, in: MediaSettingsKeys.pauseGraceRange) {
                    Text(pauseGraceSeconds == 0 ? "Ẩn ngay khi tạm dừng" : "Ẩn sau khi tạm dừng \(pauseGraceSeconds) giây")
                }
                HiddenAppsRows(bundleIDs: $hiddenApps)
            }
            .disabled(!showActivity)
            Toggle(isOn: $realSpectrum) {
                Text("Cột sóng theo phổ âm thanh thật")
                Text("Cần quyền ghi âm thanh hệ thống. Khi tắt, cột sóng chạy hiệu ứng giả.")
            }
            if realSpectrum && store.spectrumPermissionLikelyDenied {
                LabeledContent {
                    Link("Mở System Settings", destination: Self.audioCaptureSettingsURL)
                } label: {
                    Text("Không nhận được âm thanh hệ thống")
                    Text("Có thể quyền đã bị từ chối. Bật MyNotch trong Quyền riêng tư & Bảo mật › Ghi màn hình & âm thanh hệ thống.")
                }
            }
        }
    }
}

/// Apps whose playback never shows beside the notch, picked as .app bundles and stored as bundle IDs.
struct HiddenAppsRows: View {
    @Binding var bundleIDs: [String]
    /// A plain class held in state: filling it while drawing changes no state, and it lives as long as the rows.
    @State private var apps = PlayerAppCache()

    var body: some View {
        LabeledContent {
            Button("Thêm app…", action: pickApps)
        } label: {
            Text("Không hiện cho các app")
            Text("Nhạc từ các app này vẫn có trong tab Media.")
        }
        ForEach(bundleIDs, id: \.self) { bundleID in
            HiddenAppRow(bundleID: bundleID, app: apps.app(for: bundleID)) { bundleIDs.removeAll { $0 == bundleID } }
        }
    }

    /// `bundleIDs` plus the bundle IDs of `apps` it does not have yet, in order; bundles without an ID are skipped.
    static func adding(apps: [URL], to bundleIDs: [String]) -> [String] {
        apps.compactMap { Bundle(url: $0)?.bundleIdentifier }.reduce(into: bundleIDs) { result, bundleID in
            if !result.contains(bundleID) { result.append(bundleID) }
        }
    }

    private func pickApps() {
        let panel = NSOpenPanel()
        panel.message = "Chọn app không hiện bên cạnh notch khi phát nhạc"
        panel.prompt = "Thêm"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(filePath: "/Applications", directoryHint: .isDirectory)
        let binding = $bundleIDs
        let add = { (response: NSApplication.ModalResponse) in
            guard response == .OK else { return }
            binding.wrappedValue = Self.adding(apps: panel.urls, to: binding.wrappedValue)
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: add)
        } else {
            panel.begin(completionHandler: add)
        }
    }
}

private struct HiddenAppRow: View {
    let bundleID: String
    let app: PlayerApp?
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let icon = app?.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
                }
            }
            .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(app?.name ?? bundleID)
                if app != nil {
                    Text(bundleID).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: remove) {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Bỏ khỏi danh sách")
            .accessibilityLabel("Bỏ \(app?.name ?? bundleID) khỏi danh sách")
        }
    }
}
