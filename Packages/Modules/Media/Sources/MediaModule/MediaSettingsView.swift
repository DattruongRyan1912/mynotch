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
    /// System Settings › Privacy & Security › Automation, where the user lets MyNotch control Music and Spotify.
    static let automationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
    static let tintTitle = "Màu theo ảnh bìa"
    static let tintExplanation = "Lấy màu chủ đạo của ảnh bìa để nhuộm thanh tiến trình, cột sóng và vầng sáng nền trong tab Media."
    static let karaokeTitle = "Tô theo từng chữ"
    static let karaokeExplanation = "Khi lời có thời gian từng chữ (Apple Music, hoặc lrclib dạng nâng cao), phần đã hát của câu được tô dần ở dưới notch, trong tab Media và trong bảng lời nổi. Lời chỉ có thời gian từng câu vẫn hiện như cũ."

    /// One line: what could not be shown and where to allow it.
    static func deniedAppsHint(for names: [String]) -> String {
        "MyNotch chưa được phép điều khiển \(names.joined(separator: " và ")). Bật lại trong Quyền riêng tư & Bảo mật › Tự động hóa."
    }

    @Binding var showActivity: Bool
    @Binding var pauseGraceSeconds: Int
    @Binding var hiddenApps: [String]
    @Binding var realSpectrum: Bool
    @Binding var tintFromArtwork: Bool
    @Binding var spectrumColorMode: SpectrumColorMode
    @Binding var spectrumGradientStart: SRGBColor
    @Binding var spectrumGradientEnd: SRGBColor
    @Binding var lyrics: Bool
    @Binding var youtubeCaptions: Bool
    @Binding var lyricsUnderNotch: Bool
    @Binding var controlButtons: MediaControlLayout
    @Binding var karaoke: Bool
    @Binding var lyricsPanel: Bool
    @Binding var lyricsPanelFontSize: Double
    @Binding var lyricsPanelOpacity: Double
    @Binding var lyricsPanelClickThrough: Bool
    let youtubeBridge: YouTubeBridgeModel
    /// Only for the permission hint; the module keeps the store for its whole life, running or not.
    let store: NowPlayingStore
    /// The apps MyNotch is not allowed to control, for the hint under the sources.
    var sources = MediaSourceModel()
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
            if !sources.deniedApps.isEmpty {
                LabeledContent {
                    Link("Mở System Settings", destination: Self.automationSettingsURL)
                } label: {
                    Text("Nguồn nhạc bị ẩn")
                    Text(Self.deniedAppsHint(for: sources.deniedApps))
                }
            }
            Toggle(isOn: $tintFromArtwork) {
                Text(Self.tintTitle)
                Text(Self.tintExplanation)
            }
            SpectrumColorRows(mode: $spectrumColorMode, start: $spectrumGradientStart, end: $spectrumGradientEnd, tintIsOn: tintFromArtwork)
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
            Toggle(isOn: $karaoke) {
                Text(Self.karaokeTitle)
                Text(Self.karaokeExplanation)
            }
            LyricsPanelRows(isOn: $lyricsPanel, fontSize: $lyricsPanelFontSize, opacity: $lyricsPanelOpacity, clickThrough: $lyricsPanelClickThrough)
            MediaControlRows(layout: $controlButtons)
        }
    }
}

/// The floating lyrics panel: whether it is up, and how it looks. The Media tab's button and the hotkey flip the first.
struct LyricsPanelRows: View {
    static let title = "Bảng lời nổi"
    static let explanation = "Một bảng nhỏ luôn nằm trên các cửa sổ, hiện câu trước, câu đang hát và câu sau. Kéo bảng đi đâu cũng được, kéo cạnh để đổi cỡ; vị trí được nhớ theo từng màn hình. Có nút bật/tắt trong tab Media và có thể gán phím tắt."
    static let fontSizeTitle = "Cỡ chữ của bảng"
    static let opacityTitle = "Độ mờ của bảng"
    static let clickThroughTitle = "Cho chuột xuyên qua bảng"
    static let clickThroughExplanation = "Bấm vào bảng sẽ bấm xuống cửa sổ bên dưới; bảng không kéo được cho tới khi tắt mục này."

    @Binding var isOn: Bool
    @Binding var fontSize: Double
    @Binding var opacity: Double
    @Binding var clickThrough: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(Self.title)
            Text(Self.explanation)
        }
        Stepper(value: $fontSize, in: LyricsPanelModel.fontSizeRange, step: 2) {
            Text("\(Self.fontSizeTitle): \(Int(fontSize)) pt")
        }
        LabeledContent(Self.opacityTitle) {
            HStack {
                Slider(value: $opacity, in: LyricsPanelController.opacityRange)
                    .frame(width: 140)
                Text("\(Int((opacity * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
        }
        Toggle(isOn: $clickThrough) {
            Text(Self.clickThroughTitle)
            Text(Self.clickThroughExplanation)
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
