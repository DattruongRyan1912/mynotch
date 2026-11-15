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
    /// Listening to the film to find the delay: what it is doing, and starting or stopping it.
    var alignment: SubtitleAlignment?
    var align: () -> Void = {}
    var cancelAlign: () -> Void = {}
    /// Turns watching the film for drift (an advertisement in the video) on or off.
    var setWatching: (Bool) -> Void = { _ in }
    /// The subtitles floating over the film all the time: whether they are, and turning them on or off.
    var floating: (() -> Bool)?
    var setFloating: (Bool) -> Void = { _ in }
    /// The subtitles under notch: whether they are shown, and turning them on or off.
    var notchSubtitles: (() -> Bool)?
    var setNotchSubtitles: (Bool) -> Void = { _ in }
    /// Finding subtitles for the film on subtitlecat: what it is doing, and starting it.
    var finder: SubtitleFinder?
    var find: () -> Void = {}
}

/// What the auto-alignment came to, beside the notch for a few seconds.
struct SubtitleAlignmentToast: View {
    let text: String

    /// What watching says when it moved the subtitles of the part playing.
    static func realignedText(delay: Double) -> String {
        "Đã căn lại phụ đề: \(SubtitleQuickControl.offsetText(delay: delay))"
    }

    static func text(for phase: SubtitleAlignment.Phase) -> String? {
        switch phase {
        case .aligned(let delay): "Đã căn phụ đề: \(SubtitleQuickControl.offsetText(delay: delay))"
        case .failed(let reason): "Chưa căn được: \(reason)"
        case .idle, .listening: nil
        }
    }

    var body: some View {
        Label(text, systemImage: "waveform")
            .font(.caption.weight(.medium))
            .foregroundStyle(NotchTokens.primaryText)
            .lineLimit(2)
    }
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

    /// The room the figure keeps whatever it says: two digits and a half, either way.
    static let widestOffset = "−00.5s"

    static let alignTitle = "Tự căn theo tiếng thoại"
    static let alignExplanation = "Nghe tiếng phim khoảng \(SubtitleAlignment.listeningSeconds) giây rồi dời phụ đề cho khớp lúc nhân vật nói. Lần đầu macOS hỏi quyền ghi âm thanh hệ thống; âm thanh không được lưu hay gửi đi đâu."
    static let stopAlignTitle = "Dừng nghe"
    static let notchSubtitlesTitle = "Hiện phụ đề dưới notch"
    static let notchSubtitlesExplanation = "Hiện câu phụ đề / lời bài hát 2 dòng ngay dưới notch khi đang phát."
    static let floatingTitle = "Hiện phụ đề nổi trên phim"
    static let floatingExplanation = "Phụ đề hiện ở đáy màn hình của trình phát, toàn màn hình hay không. Kéo chữ để đổi độ cao; chụm hai ngón hoặc cuộn trên chữ để phóng to, thu nhỏ."
    static let watchTitle = "Tự căn lại khi bị lệch"
    static let watchExplanation = "Trong lúc phim phát, MyNotch nghe tiếng thoại ở nền và căn lại phụ đề khi chúng lệch đi, như sau một quảng cáo chèn giữa phim. Chỉ đoạn sau quảng cáo bị dời."

    static let findTitle = "Tìm phụ đề tự động"
    static let findAgainTitle = "Tìm bản phụ đề khác"
    static let findExplanation = "Hỏi LLM của module Dịch (nếu đã cài) tên gốc của phim theo tiêu đề trang, tìm trên subtitlecat.com, rồi nghe phim khoảng 45 giây để chọn bản khớp tiếng thoại nhất. Tiêu đề trang được gửi tới LLM đó, tên phim tới subtitlecat.com."
    static let findingTitle = "Đang tìm…"

    /// What the finder is doing, for the pointer resting on the control; nil while it does nothing to say.
    static func findHelp(_ phase: SubtitleFinder.Phase?) -> String? {
        switch phase {
        case .guessing: "Đang đoán tên gốc của phim"
        case .searching(let query): "Đang tìm “\(query)” trên subtitlecat"
        case .trying(let query, let releases): "Đang nghe phim và tải \(releases) bản phụ đề của “\(query)”"
        case .found(let text), .failed(let text): text
        case .idle, nil: nil
        }
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

    @ViewBuilder
    private func loadButton(_ controls: SubtitleControls) -> some View {
        let unreadable = controls.book.unreadableName
        let help = unreadable.map { "\($0) không có phụ đề SRT hoặc VTT nào. Chọn file khác" } ?? "Nạp file phụ đề .srt hoặc .vtt cho video đang phát"
        if let finder = controls.finder {
            let listening = controls.alignment?.phase
            Menu {
                Button("Nạp file…") { pick(controls) }
                Button(Self.findTitle) { controls.find() }
                    .help(Self.findExplanation)
                    .disabled(finder.isBusy)
                if let notchSubtitles = controls.notchSubtitles {
                    Divider()
                    Toggle(Self.notchSubtitlesTitle, isOn: Binding(get: notchSubtitles, set: controls.setNotchSubtitles))
                        .help(Self.notchSubtitlesExplanation)
                }
            } label: {
                capsule {
                    Image(systemName: finder.isBusy ? "magnifyingglass" : "captions.bubble")
                        .accessibilityHidden(true)
                    if finder.isBusy, case .listening(let left) = listening {
                        Text("\(left)s").monospacedDigit()
                    } else {
                        Text(finder.isBusy ? Self.findingTitle : unreadable == nil ? Self.loadTitle : Self.unreadableTitle)
                    }
                }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(Self.findHelp(finder.phase) ?? help)
        } else {
            Menu {
                Button("Nạp file…") { pick(controls) }
                if let notchSubtitles = controls.notchSubtitles {
                    Divider()
                    Toggle(Self.notchSubtitlesTitle, isOn: Binding(get: notchSubtitles, set: controls.setNotchSubtitles))
                        .help(Self.notchSubtitlesExplanation)
                }
            } label: {
                capsule {
                    Image(systemName: "captions.bubble")
                        .accessibilityHidden(true)
                    Text(unreadable == nil ? Self.loadTitle : Self.unreadableTitle)
                }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(help)
        }
    }

    private func loaded(_ entry: SubtitleBook.Entry, _ controls: SubtitleControls) -> some View {
        // A nudge while listening would be undone by what the listening finds.
        let listening = controls.alignment?.isListening ?? false
        return HStack(spacing: 2) {
            stepButton("minus", help: Self.laterHelp) {
                controls.shift(SubtitleBook.smallStep)
            }
            .disabled(listening)
            menu(entry, controls)
            stepButton("plus", help: Self.soonerHelp) {
                controls.shift(-SubtitleBook.smallStep)
            }
            .disabled(listening)
        }
    }

    /// The figure, or while listening the seconds left: in the same room either way.
    /// The delay is that of the part of the video `position` is in.
    static func figure(for entry: SubtitleBook.Entry, phase: SubtitleAlignment.Phase?, at position: Double? = nil) -> String {
        if case .listening(let left) = phase { return "\(left)s" }
        return offsetText(delay: entry.delay(at: position))
    }

    /// What the control says when the pointer rests on it: the file and its delay, and what the last listening came to.
    static func help(for entry: SubtitleBook.Entry, phase: SubtitleAlignment.Phase?, at position: Double? = nil) -> String {
        let parts = entry.parts.isEmpty ? "" : " ở đoạn này (phim chia \(entry.parts.count + 1) đoạn lệch khác nhau, do quảng cáo chèn giữa)"
        let file = "\(entry.name): lệch \(offsetText(delay: entry.delay(at: position)))\(parts)"
        switch phase {
        case .listening: return "Đang nghe tiếng thoại để căn phụ đề"
        case .aligned(let delay): return "\(file). Đã tự căn theo tiếng thoại: \(offsetText(delay: delay))"
        case .failed(let reason): return "\(file). Chưa tự căn được: \(reason)"
        case .idle, nil: return file
        }
    }

    /// Where the video is: read when the state changes (a seek, a pause, another part), which is when the figure may change.
    private var position: Double? { PlaybackClock.position(state, at: Date()) }

    private func menu(_ entry: SubtitleBook.Entry, _ controls: SubtitleControls) -> some View {
        Menu {
            Text(entry.name)
            Divider()
            Button("Sớm hơn 5 giây") { controls.shift(-SubtitleBook.largeStep) }
            Button("Muộn hơn 5 giây") { controls.shift(SubtitleBook.largeStep) }
            Button("Đặt lại độ lệch") { controls.resetDelay() }
                .disabled(!entry.isMoved)
            if controls.alignment?.isListening == true {
                Button(Self.stopAlignTitle) { controls.cancelAlign() }
            } else if controls.alignment != nil {
                Button(Self.alignTitle) { controls.align() }
                    .help(Self.alignExplanation)
            }
            if let floating = controls.floating {
                Toggle(Self.floatingTitle, isOn: Binding(get: floating, set: controls.setFloating))
                    .help(Self.floatingExplanation)
            }
            if let notchSubtitles = controls.notchSubtitles {
                Toggle(Self.notchSubtitlesTitle, isOn: Binding(get: notchSubtitles, set: controls.setNotchSubtitles))
                    .help(Self.notchSubtitlesExplanation)
            }
            if let alignment = controls.alignment {
                Toggle(Self.watchTitle, isOn: Binding(get: { alignment.watchWanted }, set: controls.setWatching))
                    .help(Self.watchExplanation)
            }
            Divider()
            Button("Nạp file khác…") { pick(controls) }
            if let finder = controls.finder {
                Button(Self.findAgainTitle) { controls.find() }
                    .help(Self.findExplanation)
                    .disabled(finder.isBusy)
            }
            Button("Gỡ phụ đề", role: .destructive) { controls.remove() }
        } label: {
            capsule {
                Image(systemName: controls.alignment?.isListening == true ? "waveform" : "captions.bubble.fill")
                    .accessibilityHidden(true)
                // As wide as the widest figure the buttons usually reach, so "0s", "−3s" and "−3.5s" keep the − and + buttons where
                // they are under a pointer pressing them again and again.
                ZStack(alignment: .trailing) {
                    Text(Self.widestOffset).hidden()
                    // A film in parts crosses into the next one as it plays, with no change of state: looked at every few seconds.
                    if entry.parts.isEmpty {
                        Text(Self.figure(for: entry, phase: controls.alignment?.phase, at: position))
                    } else {
                        TimelineView(.periodic(from: .now, by: 2)) { _ in
                            Text(Self.figure(for: entry, phase: controls.alignment?.phase, at: position))
                        }
                    }
                }
                .monospacedDigit()
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Self.findHelp(controls.finder?.phase) ?? Self.help(for: entry, phase: controls.alignment?.phase, at: position))
        .accessibilityLabel("Phụ đề \(entry.name)")
        .accessibilityValue(Text("Lệch \(Self.offsetText(delay: entry.delay(at: position)))"))
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
