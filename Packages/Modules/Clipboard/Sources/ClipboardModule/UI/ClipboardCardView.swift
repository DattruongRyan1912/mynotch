import AppKit
import NotchUI
import SwiftUI

/// One card of the row: a preview by kind, the source app, when it was copied and whether it is pinned.
struct ClipboardCardView: View {
    static let size = CGSize(width: 112, height: 120)

    let item: ClipboardItem
    let isSelected: Bool
    let isPinned: Bool
    /// Read by the tab at least once a minute, for the relative time.
    let now: Date
    /// The stored PNG of an image item.
    let imageURL: URL?
    let thumbnails: ClipboardThumbnailCache

    @Environment(\.notchAccent) private var accent
    @Environment(\.notchSurface) private var surface
    @State private var isHovered = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .padding(8)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(NotchTokens.fill(isHovered ? 0.12 : 0.07), in: shape)
        .overlay {
            if isSelected { shape.strokeBorder(accent, lineWidth: 2) }
        }
        .contentShape(shape)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ClipboardCardText.accessibilityLabel(for: item, isPinned: isPinned, now: now))
    }

    private var preview: some View {
        ClipboardContentPreview(content: item.content, codeLanguage: item.codeLanguage, imageURL: imageURL, thumbnails: thumbnails, style: .notch(onGlass: surface.isLiquidGlass))
    }

    private var footer: some View {
        HStack(spacing: 4) {
            if let bundleID = item.sourceBundleID, let icon = ClipboardIcons.app(bundleID: bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 12, height: 12)
                    .help(item.sourceAppName ?? bundleID)
            }
            Text(ClipboardCardText.relativeTime(item.copiedAt, now: now))
                .font(.system(size: 10))
                .foregroundStyle(NotchTokens.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(accent)
                    .accessibilityLabel("Đã ghim")
            }
        }
        .frame(height: 12)
    }
}
