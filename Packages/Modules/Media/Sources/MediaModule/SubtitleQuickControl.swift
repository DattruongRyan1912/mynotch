import AppKit
import MyNotchCore
import NotchUI
import SwiftUI
import UniformTypeIdentifiers

/// What the subtitle control acts on: the module's book and what it does when the user loads, moves or removes subtitles.
struct SubtitleControls {
    let book: SubtitleBook
    let load: (URL) -> Void
    let shift: (Double) -> Void
    let resetDelay: () -> Void
    let remove: () -> Void
}

/// Subtitles in the row above the player, before the EQ: "Phụ đề…" opens a subtitle file for what plays now; once one is loaded,
/// + brings the lines sooner and − later by half a second, and the menu has the rest (5 s steps, back to 0, another file, remove).
/// The figure is how much sooner they come, as "+" reads: "+4s" is four seconds ahead of the file, "−4s" four seconds behind.
/// It is there for a film (a page in a browser, or anything longer than a song) and for whatever has subtitles; not for music.
struct SubtitleQuickControl: View {
    static let height = MediaSourceChipsView.height
    static let loadTitle = "Phụ đề…"
    static let unreadableTitle = "Không đọc được"
    /// Longer than this is no song.
    static let filmSeconds = 15.0 * 60
    static let fileTypes: [UTType] = [UTType(filenameExtension: "srt"), UTType(filenameExtension: "vtt")].compactMap { $0 }

    let controls: SubtitleControls?
    let state: NowPlayingState

    static func isShown(_ controls: SubtitleControls?, for state: NowPlayingState) -> Bool {
        guard let controls, state.isActive else { return false }
        return controls.book.current != nil || state.isFromBrowser || (state.durationSeconds ?? 0) > filmSeconds
    }

    /// How much sooner than the file the lines come, for a delay (positive is later): "+1.5s" for a delay of −1.5, "−0.5s" for 0.5,
    /// "0s". A point whatever the locale, as players write seconds.
    static func offsetText(delay: Double) -> String {
        let advance = -delay
        let magnitude = abs(advance).formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US_POSIX")))
        return advance > 0 ? "+\(magnitude)s" : advance < 0 ? "−\(magnitude)s" : "0s"
    }

    static let soonerHelp = "Hiện phụ đề sớm hơn 0.5s"
    static let laterHelp = "Hiện phụ đề muộn hơn 0.5s"

    var body: some View {
        if let controls, Self.isShown(controls, for: state) {
            Group {
                if let entry = controls.book.current {
                    loaded(entry, controls)
                } else {
                    loadButton(controls)
                }
            }
            .padding(.leading, EQQuickControl.leadingGap)
            .frame(height: Self.height)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Phụ đề")
        }
    }

    private func loadButton(_ controls: SubtitleControls) -> some View {
        let unreadable = controls.book.unreadableName
        return Button { pick(controls) } label: {
            capsule {
                Image(systemName: "captions.bubble")
                    .accessibilityHidden(true)
                Text(unreadable == nil ? Self.loadTitle : Self.unreadableTitle)
            }
        }
        .buttonStyle(.plain)
        .help(unreadable.map { "\($0) không có phụ đề SRT hoặc VTT nào. Chọn file khác" } ?? "Nạp file phụ đề .srt hoặc .vtt cho video đang phát")
    }

    private func loaded(_ entry: SubtitleBook.Entry, _ controls: SubtitleControls) -> some View {
        HStack(spacing: 2) {
            stepButton("minus", help: Self.laterHelp) {
                controls.shift(SubtitleBook.smallStep)
            }
            menu(entry, controls)
            stepButton("plus", help: Self.soonerHelp) {
                controls.shift(-SubtitleBook.smallStep)
            }
        }
    }

    private func menu(_ entry: SubtitleBook.Entry, _ controls: SubtitleControls) -> some View {
        Menu {
            Text(entry.name)
            Divider()
            Button("Sớm hơn 5 giây") { controls.shift(-SubtitleBook.largeStep) }
            Button("Muộn hơn 5 giây") { controls.shift(SubtitleBook.largeStep) }
            Button("Đặt lại độ lệch") { controls.resetDelay() }
                .disabled(entry.delay == 0)
            Divider()
            Button("Nạp file khác…") { pick(controls) }
            Button("Gỡ phụ đề", role: .destructive) { controls.remove() }
        } label: {
            capsule {
                Image(systemName: "captions.bubble.fill")
                    .accessibilityHidden(true)
                Text(Self.offsetText(delay: entry.delay))
                    .monospacedDigit()
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("\(entry.name): lệch \(Self.offsetText(delay: entry.delay))")
        .accessibilityLabel("Phụ đề \(entry.name)")
        .accessibilityValue(Text("Lệch \(Self.offsetText(delay: entry.delay))"))
    }

    private func stepButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(NotchTokens.primaryText)
                .frame(width: Self.height, height: Self.height)
                .background { RoundedRectangle(cornerRadius: 5).fill(NotchTokens.fill(0.08)) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func capsule(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 4) { content() }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(NotchTokens.primaryText)
            .padding(.horizontal, 7)
            .frame(height: Self.height)
            .background { Capsule().fill(NotchTokens.fill(0.14)) }
            .contentShape(Capsule())
    }

    /// MyNotch is an agent app, so it is brought forward first or the panel would open behind the browser.
    private func pick(_ controls: SubtitleControls) {
        let panel = NSOpenPanel()
        panel.message = "Chọn file phụ đề cho video đang phát"
        panel.prompt = "Nạp"
        panel.allowedContentTypes = Self.fileTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            controls.load(url)
        }
    }
}
