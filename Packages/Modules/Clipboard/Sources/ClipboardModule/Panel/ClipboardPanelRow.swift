import SwiftUI

/// One row of the panel's list: a picture of what was copied, a line of it, the app and when, and the ⌘N that picks it.
struct ClipboardPanelRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    /// 1 to 9 for the first nine rows.
    let shortcut: Int?
    let timeLabel: String
    let accessibilityLabel: String
    let imageURL: URL?
    let thumbnails: ClipboardThumbnailCache

    @Environment(\.notchAccent) private var accent
    @State private var isHovered = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    private var detail: String {
        [item.sourceAppName, timeLabel].compactMap(\.self).joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            ClipboardItemGlyph(item: item, imageURL: imageURL, thumbnails: thumbnails, iconSize: 26)
                .frame(width: 34, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(ClipboardCardText.rowTitle(of: item.content))
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 4) {
                    ClipboardLibraryAppIcon(item: item, size: 11)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let shortcut {
                Text("⌘\(shortcut)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(ClipboardLibraryStyle.fill(isSelected: isSelected, isHovered: isHovered && !isSelected, accent: accent), in: shape)
        .overlay {
            if isSelected { shape.strokeBorder(accent, lineWidth: 1.5) }
        }
        .contentShape(shape)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(shortcut.map { "Phím tắt ⌘\($0)" } ?? "")
    }
}
