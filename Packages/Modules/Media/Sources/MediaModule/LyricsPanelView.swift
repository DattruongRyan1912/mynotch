import AppKit
import NotchUI
import Observation
import SwiftUI

/// What the floating panel's font size setting becomes in its view, so a change redraws the view and nothing else.
@Observable
final class LyricsPanelModel {
    static let fontSizeRange = 14.0...48.0
    static let defaultFontSize = 22.0

    /// The setting's value, which is kept within `fontSizeRange` already.
    var fontSize: Double

    init(fontSize: Double = LyricsPanelModel.defaultFontSize) {
        self.fontSize = min(max(fontSize, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
    }
}

/// What the panel shows at a moment: the lines, or the reason there are none.
enum LyricsPanelContent: Equatable {
    case lines(LyricPanelLines)
    case message(String)
}

extension NowPlayingStore {
    /// The panel's content at `date`. Lyrics the user hid from the notch with the row's button are shown here all the same: the
    /// panel is a choice of its own.
    func lyricsPanelContent(at date: Date) -> LyricsPanelContent {
        if let lines = lyricPanel(at: date) { return .lines(lines) }
        if !state.isActive { return .message("Không có gì đang phát") }
        if !lyricsAreOn { return .message("Bật nguồn lời bài hát trong Cài đặt") }
        if lyricsAreUnsynced { return .message("Chỉ có lời không đồng bộ") }
        return .message("Chưa có lời đồng bộ cho bài này")
    }
}

/// The floating panel's content: the line before, the one being sung (filled word by word when it has its words timed) and
/// the one coming, centred on a dark rounded background. Lines are one row each and shrink to fit the width the user gave.
struct LyricsPanelView: View {
    static let cornerRadius: CGFloat = 18
    static let minimumNeighbourSize = 12.0

    let store: NowPlayingStore
    let model: LyricsPanelModel
    /// Whether the panel can be seen; the views inside read it as `notchIsOnScreen`, as the notch's do, so their timeline stands
    /// still and their sweep is taken away while it cannot.
    let presence: LyricsPanelPresence

    /// The lines around the current one are smaller than it, but never too small to read.
    static func neighbourSize(for size: Double) -> Double {
        max(size * 0.7, minimumNeighbourSize)
    }

    var body: some View {
        LyricsTimelineContent(store: store, model: model)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous).fill(Color.black.opacity(0.82)))
            .environment(\.notchIsOnScreen, presence.isOnScreen)
    }
}

private struct LyricsTimelineContent: View {
    let store: NowPlayingStore
    let model: LyricsPanelModel

    var body: some View {
        LyricTimeline(store: store) { date in
            switch store.lyricsPanelContent(at: date) {
            case .lines(let lines):
                rows(lines)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Lời bài hát")
                    .accessibilityValue(lines.spoken)
            case .message(let text):
                message(text)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Lời bài hát")
                    .accessibilityValue(text)
            }
        }
    }

    private func rows(_ lines: LyricPanelLines) -> some View {
        let size = model.fontSize
        let neighbour = LyricsPanelView.neighbourSize(for: size)
        return VStack(spacing: 6) {
            neighbourRow(lines.previous?.text, size: neighbour)
            current(lines.current, size: size)
            neighbourRow(lines.next?.text, size: neighbour)
        }
        .animation(.easeOut(duration: 0.2), value: lines)
    }

    /// The line being sung; the dimmed note while nothing is.
    @ViewBuilder
    private func current(_ line: LyricLine?, size: Double) -> some View {
        let style = KaraokeStyle(
            fontSize: size, weight: .bold, lit: NSColor(NotchTokens.primaryText), dim: NSColor(NotchTokens.primaryText).withAlphaComponent(0.4)
        )
        if store.karaokeIsActive, let line, line.words != nil {
            KaraokeLine(line: line, store: store, style: style)
                .frame(height: style.lineHeight)
        } else {
            Text(line?.text ?? LyricStrip.note)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(line == nil ? NotchTokens.secondaryText : NotchTokens.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(CGFloat(KaraokeFit.minimumScale))
                .frame(maxWidth: .infinity, minHeight: style.lineHeight)
        }
    }

    private func neighbourRow(_ text: String?, size: Double) -> some View {
        Text(text ?? " ")
            .font(.system(size: size))
            .foregroundStyle(NotchTokens.secondaryText)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(CGFloat(KaraokeFit.minimumScale))
            .frame(maxWidth: .infinity)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(NotchTokens.secondaryText)
            .multilineTextAlignment(.center)
    }
}
