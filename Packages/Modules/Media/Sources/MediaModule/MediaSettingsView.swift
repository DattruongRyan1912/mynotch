import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Plain rows: the Settings page provides the Form and the section.
struct MediaSettingsView: View {
    /// System Settings › Privacy & Security › Screen & System Audio Recording, where "System Audio Recording Only" is.
    static let audioCaptureSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!
    /// Says what leaves the Mac, because lyrics are the one feature here that talks to a server.
    static let lyricsExplanation = "Khi bật, tên bài, nghệ sĩ, album và thời lượng của mỗi bài mới (kể cả video phát trong trình duyệt) được gửi tới lrclib.net để lấy lời."
    static let lyricsUnderNotchTitle = "Hiện lời 2 dòng dưới notch"
    static let lyricsUnderNotchExplanation = "Khi có lời đồng bộ và nhạc đang phát, notch thu gọn hiện câu đang hát và câu sắp tới."

    @Binding var showActivity: Bool
    @Binding var pauseGraceSeconds: Int
    @Binding var hiddenApps: [String]
    @Binding var realSpectrum: Bool
    @Binding var lyrics: Bool
    @Binding var youtubeCaptions: Bool
    @Binding var lyricsUnderNotch: Bool
    @Binding var controlButtons: MediaControlLayout
    let youtubeBridge: YouTubeBridgeModel
    /// Only for the permission hint; the module keeps the store for its whole life, running or not.
    let store: NowPlayingStore
    let appleAccount: AppleMusicAccount
    let connectAppleMusic: () -> Void
    let disconnectAppleMusic: () -> Void

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
            Toggle(isOn: $lyrics) {
                Text("Lời bài hát đồng bộ từ lrclib.net")
                Text(Self.lyricsExplanation)
            }
            if lyrics {
                AppleMusicRows(account: appleAccount, connect: connectAppleMusic, disconnect: disconnectAppleMusic)
            }
            YouTubeBridgeRows(isOn: $youtubeCaptions, model: youtubeBridge)
            Toggle(isOn: $lyricsUnderNotch) {
                Text(Self.lyricsUnderNotchTitle)
                Text(Self.lyricsUnderNotchExplanation)
            }
            MediaControlRows(layout: $controlButtons)
        }
    }
}

/// Which buttons the Media tab has on each side of play and pause: two slots on each side. A button chosen for one slot
/// leaves the slot that had it.
struct MediaControlRows: View {
    static let title = "Nút điều khiển"
    static let explanation = "Các nút bên trái và bên phải nút phát/dừng trong tab Media. Nút nào không dùng được với trình phát hiện tại sẽ mờ đi."
    /// The slots left to right, as the row shows them.
    static let slotTitles = ["Ngoài cùng bên trái", "Cạnh nút phát, bên trái", "Cạnh nút phát, bên phải", "Ngoài cùng bên phải"]

    @Binding var layout: MediaControlLayout

    var body: some View {
        LabeledContent {
            EmptyView()
        } label: {
            Text(Self.title)
            Text(Self.explanation)
        }
        ForEach(Self.slotTitles.indices, id: \.self) { slot in
            Picker(Self.slotTitles[slot], selection: choice(for: slot)) {
                ForEach(MediaControlButton.choices, id: \.self) { Text($0.title).tag($0) }
            }
        }
    }

    /// What the picker shows for a stored button: a button it does not offer (a stored like) is none, as the row draws it.
    static func shownChoice(_ button: MediaControlButton) -> MediaControlButton {
        MediaControlButton.choices.contains(button) ? button : .none
    }

    private func choice(for slot: Int) -> Binding<MediaControlButton> {
        Binding(get: { Self.shownChoice(layout.slots[slot]) }, set: { layout = layout.setting($0, at: slot) })
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
