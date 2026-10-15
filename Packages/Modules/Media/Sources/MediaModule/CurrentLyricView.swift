import AppKit
import NotchUI
import SwiftUI

/// What the row under the transport controls holds. `reserved` is the row with nothing in it: while a lyrics source
/// is on and the words are still on their way (or the track has none), the player keeps its place.
nonisolated enum LyricRow: Equatable, Sendable {
    case absent, reserved, synced, unsynced
}

/// The line being sung, centred under the transport controls. One dimmed note when lrclib has the words but no
/// timing; nothing at all (not even the row's height) while no lyrics source is on.
/// The row keeps its height between lines, so the player does not jump at each pause in the song.
struct CurrentLyricView: View {
    static let height: CGFloat = 14
    /// What the button at the row's end takes on each side, so that the line stays centred and never runs under it.
    static let toggleWidth: CGFloat = 24

    let store: NowPlayingStore
    /// Puts the floating lyrics panel up or takes it down.
    var togglePanel: () -> Void = {}
    @Environment(\.notchSurface) private var surface

    var body: some View {
        let hasRow = store.lyricRow != .absent
        // Read here, in the body, and handed down: the row's closures run later, where the environment is not this view's to read.
        content(karaoke: surface.isLiquidGlass ? .rowOnGlass : .row)
            .padding(.horizontal, hasRow ? Self.toggleWidth : 0)
            .overlay(alignment: .trailing) {
                if hasRow { PanelToggleButton(isShown: store.lyricsPanelShown, action: togglePanel) }
            }
    }

    @ViewBuilder
    private func content(karaoke: KaraokeStyle) -> some View {
        switch store.lyricRow {
        case .absent:
            EmptyView()
        case .reserved:
            Color.clear.frame(height: Self.height)
        case .synced:
            // At each line when it is filled word by word, else four times a second, which is fine-grained enough for lines
            // that last seconds; the clock itself is exact.
            LyricTimeline(store: store) { date in
                let line = store.lyric(at: date)
                let text = line?.text ?? ""
                Group {
                    if store.karaokeIsActive, let line, !text.isEmpty, line.words != nil {
                        KaraokeLine(line: line, store: store, style: karaoke)
                            .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height)
                    } else {
                        row(text)
                            .foregroundStyle(NotchTokens.primaryText.opacity(0.9))
                            .contentTransition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: text)
            }
        case .unsynced:
            row("Chỉ có lời không đồng bộ")
                .foregroundStyle(NotchTokens.secondaryText.opacity(0.7))
        }
    }

    /// One centred line of fixed height; a long one is cut at its tail.
    private func row(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .center)
    }
}

extension KaraokeStyle {
    /// The current line of the Media tab's row, which is a little smaller and dimmer than the strip's. White, as the black notch's
    /// text always was: a colour in a layer is made once, so it cannot be a token that follows the look.
    static let row = KaraokeStyle(
        fontSize: 11, weight: .medium, lit: NSColor(Color.white).withAlphaComponent(0.9),
        dim: NSColor(Color.white.opacity(0.6)).withAlphaComponent(0.7)
    )
    /// The same row on Liquid Glass: the system's label colours, which turn dark on light glass.
    static let rowOnGlass = KaraokeStyle(
        fontSize: 11, weight: .medium, lit: .dynamic(.labelColor, alpha: 0.9), dim: .dynamic(.secondaryLabelColor, alpha: 0.7)
    )
}

/// How the button for the floating lyrics panel looks: the panel up is lit, like the lyrics button among the controls.
enum LyricsPanelToggle {
    static func look(isShown: Bool) -> MediaControlLook {
        MediaControlLook(
            symbol: isShown ? "pip.exit" : "pip.enter", label: "Bảng lời nổi: \(isShown ? "bật" : "tắt")", isEnabled: true, isActive: isShown
        )
    }
}

/// At the end of the lyric row: a small button that puts the panel up or takes it down.
private struct PanelToggleButton: View {
    let isShown: Bool
    let action: () -> Void
    @Environment(\.notchAccent) private var accent
    @State private var isHovering = false

    var body: some View {
        let look = LyricsPanelToggle.look(isShown: isShown)
        Button(action: action) {
            Image(systemName: look.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(look.isActive ? accent : NotchTokens.secondaryText)
                .opacity(isHovering || look.isActive ? 1 : 0.7)
                .frame(width: CurrentLyricView.toggleWidth - 4, height: CurrentLyricView.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(look.label)
        .accessibilityLabel(look.label)
        .accessibilityAddTraits(look.isActive ? .isSelected : [])
    }
}
