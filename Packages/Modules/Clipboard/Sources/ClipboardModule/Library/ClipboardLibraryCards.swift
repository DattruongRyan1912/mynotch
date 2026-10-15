import AppKit
import SwiftUI

/// Colors shared by the library's cards, rows and tiles. System colors, so the window follows light and dark.
enum ClipboardLibraryStyle {
    static func fill(isSelected: Bool, isHovered: Bool) -> Color {
        isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(isHovered ? 0.1 : 0.06)
    }
}

/// One card of the library's grid: a preview by kind, the source app, when it was copied and whether it is pinned.
struct ClipboardLibraryCard: View {
    let item: ClipboardItem
    let size: ClipboardLibraryCardSize
    let isSelected: Bool
    let isPinned: Bool
    let timeLabel: String
    let accessibilityLabel: String
    /// The stored PNG of an image item.
    let imageURL: URL?
    let thumbnails: ClipboardThumbnailCache

    @State private var isHovered = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ClipboardContentPreview(content: item.content, codeLanguage: item.codeLanguage, imageURL: imageURL, thumbnails: thumbnails, style: .library(size))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            footer
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .frame(height: size.height)
        .background(ClipboardLibraryStyle.fill(isSelected: isSelected, isHovered: isHovered), in: shape)
        .overlay {
            if isSelected { shape.strokeBorder(Color.accentColor, lineWidth: 2) }
        }
        .contentShape(shape)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var footer: some View {
        HStack(spacing: 5) {
            ClipboardLibraryAppIcon(item: item, size: 14)
            Text(timeLabel)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Đã ghim")
            }
        }
        .frame(height: 14)
    }
}

/// One row of the library's list: icon, what was copied, the source app and when.
struct ClipboardLibraryRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let isPinned: Bool
    let timeLabel: String
    let accessibilityLabel: String
    let imageURL: URL?
    let thumbnails: ClipboardThumbnailCache

    @State private var isHovered = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 12) {
            ClipboardItemGlyph(item: item, imageURL: imageURL, thumbnails: thumbnails)
                .frame(width: 40, height: 32)
            Text(ClipboardCardText.rowTitle(of: item.content))
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                ClipboardLibraryAppIcon(item: item, size: 16)
                Text(item.sourceAppName ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)
            Text(timeLabel)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 100, alignment: .trailing)
            Image(systemName: "pin.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.accentColor)
                .opacity(isPinned ? 1 : 0)
                .frame(width: 14)
                .accessibilityHidden(!isPinned)
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(ClipboardLibraryStyle.fill(isSelected: isSelected, isHovered: isHovered), in: shape)
        .overlay {
            if isSelected { shape.strokeBorder(Color.accentColor, lineWidth: 1.5) }
        }
        .contentShape(shape)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// The icon of the app an item was copied from, or nothing when it is unknown or no longer installed.
struct ClipboardLibraryAppIcon: View {
    let item: ClipboardItem
    let size: CGFloat

    var body: some View {
        if let bundleID = item.sourceBundleID, let icon = ClipboardIcons.app(bundleID: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: size, height: size)
                .help(item.sourceAppName ?? bundleID)
        }
    }
}

/// A board in the row above the history: its name and how many items it holds. Items dropped on it are added.
struct ClipboardLibraryBoardTile: View {
    let board: ClipboardBoard
    let count: Int
    let isTargeted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: board.systemImage)
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(board.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text("\(count) mục")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(width: 176, height: 62)
        .modifier(ClipboardLibraryTileBackground(isTargeted: isTargeted))
        .accessibilityElement(children: .combine)
    }
}

/// The dashed tile after the boards, which asks for a name for a new one.
struct ClipboardLibraryNewBoardTile: View {
    var body: some View {
        Label("Board mới", systemImage: "plus")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 176, height: 62)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ClipboardLibraryTileBackground: ViewModifier {
    let isTargeted: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        content
            .background(Color.primary.opacity(isTargeted ? 0.16 : 0.06), in: shape)
            .overlay {
                if isTargeted { shape.strokeBorder(Color.accentColor, lineWidth: 2) }
            }
            .contentShape(shape)
    }
}
