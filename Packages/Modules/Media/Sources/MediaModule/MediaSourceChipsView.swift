import AppKit
import NotchUI
import SwiftUI

/// The row of chips above the player, one per source: the app's icon (Chrome's for a tab), the track in short, a dot while it plays. A
/// tap shows that source in the player; a right click offers to pin it as the one the notch follows. Only with two sources or more,
/// and it scrolls sideways when they do not fit, so it never takes more room than its one row.
struct MediaSourceChipsView: View {
    static let height: CGFloat = 18
    static let spacing: CGFloat = 6
    static let iconSize: CGFloat = 12
    static let maxTitleWidth: CGFloat = 110
    static let pinTitle = "Luôn hiện nguồn này"
    static let unpinTitle = "Bỏ ghim nguồn này"

    /// What VoiceOver says of a chip besides its title.
    static func state(of chip: MediaSourceChip) -> String {
        [chip.isPlaying ? "đang phát" : "tạm dừng", chip.isPinned ? "đã ghim" : nil].compactMap { $0 }.joined(separator: ", ")
    }

    let model: MediaSourceModel
    let icons: PlayerAppCache

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Self.spacing) {
                ForEach(model.chips) { chip in
                    MediaSourceChipButton(chip: chip, icon: chip.iconBundleID.flatMap(icons.app(for:))?.icon, select: { model.select(chip.id) })
                        .contextMenu {
                            Button(chip.isPinned ? Self.unpinTitle : Self.pinTitle) { model.togglePin(chip.id) }
                        }
                }
            }
            .padding(.horizontal, 1)
        }
        .frame(height: Self.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Nguồn âm thanh")
    }
}

private struct MediaSourceChipButton: View {
    let chip: MediaSourceChip
    let icon: NSImage?
    let select: () -> Void
    @Environment(\.notchAccent) private var accent
    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 4) {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: MediaSourceChipsView.iconSize, height: MediaSourceChipsView.iconSize)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: MediaSourceChipsView.iconSize, height: MediaSourceChipsView.iconSize)
                }
                Text(chip.title.isEmpty ? "—" : chip.title)
                    .font(.system(size: 10.5, weight: chip.isShown ? .semibold : .medium))
                    .lineLimit(1)
                    .frame(maxWidth: MediaSourceChipsView.maxTitleWidth, alignment: .leading)
                    .fixedSize()
                if chip.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 7, weight: .bold))
                        .accessibilityHidden(true)
                }
                if chip.isPlaying {
                    // Still, not an animation: a row that is on screen for as long as the tab is would otherwise cost a frame loop.
                    Circle()
                        .fill(accent)
                        .frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(chip.isShown ? NotchTokens.primaryText : NotchTokens.secondaryText)
            .padding(.horizontal, 7)
            .frame(height: MediaSourceChipsView.height)
            .background {
                Capsule().fill(NotchTokens.fill(chip.isShown ? 0.22 : (isHovering ? 0.14 : 0.08)))
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(chip.detail.isEmpty ? chip.title : "\(chip.title) — \(chip.detail)")
        .accessibilityLabel(Text(chip.title))
        .accessibilityValue(Text(MediaSourceChipsView.state(of: chip)))
        .accessibilityAddTraits(chip.isShown ? .isSelected : [])
    }
}
