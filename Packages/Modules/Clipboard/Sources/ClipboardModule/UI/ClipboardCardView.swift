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
        .background(Color.white.opacity(isHovered ? 0.12 : 0.07), in: shape)
        .overlay {
            if isSelected { shape.strokeBorder(NotchTokens.accent, lineWidth: 2) }
        }
        .contentShape(shape)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ClipboardCardText.accessibilityLabel(for: item, isPinned: isPinned, now: now))
    }

    @ViewBuilder private var preview: some View {
        switch item.content {
        case .text(let text), .richText(let text, _):
            Text(ClipboardCardText.preview(of: text))
                .font(.system(size: 11))
                .foregroundStyle(NotchTokens.primaryText)
                .lineLimit(4)
        case .link(let url):
            let link = ClipboardCardText.link(url)
            VStack(alignment: .leading, spacing: 3) {
                Label(link.title, systemImage: "link")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchTokens.primaryText)
                    .lineLimit(1)
                    // Keeps both ends of a long host, e.g. "develo…ple.com".
                    .truncationMode(.middle)
                if let detail = link.detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(NotchTokens.secondaryText)
                        .lineLimit(3)
                }
            }
        case .color(let hex):
            VStack(alignment: .leading, spacing: 6) {
                swatch(hex)
                Text(hex)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(NotchTokens.primaryText)
            }
        case .image:
            ClipboardThumbnailView(url: imageURL, cache: thumbnails)
        case .files(let urls):
            let files = ClipboardCardText.files(urls)
            VStack(alignment: .leading, spacing: 3) {
                if let first = urls.first {
                    Image(nsImage: ClipboardIcons.file(first))
                        .resizable()
                        .frame(width: 32, height: 32)
                }
                Text(files.title)
                    .font(.system(size: 11))
                    .foregroundStyle(NotchTokens.primaryText)
                    .lineLimit(2)
                if let detail = files.detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(NotchTokens.secondaryText)
                        .lineLimit(1)
                }
            }
        }
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
                    .foregroundStyle(NotchTokens.accent)
                    .accessibilityLabel("Đã ghim")
            }
        }
        .frame(height: 12)
    }

    private func swatch(_ hex: String) -> some View {
        let color = ClipboardCardText.colorComponents(hex: hex)
            .map { Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue, opacity: $0.alpha) }
        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(color ?? .clear)
            .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.white.opacity(0.2)) }
    }
}

/// An image card's preview, decoded once per file and off the main thread.
private struct ClipboardThumbnailView: View {
    let url: URL?
    let cache: ClipboardThumbnailCache

    @State private var loaded: NSImage?

    var body: some View {
        Group {
            if let image = loaded ?? url.flatMap(cache.cachedThumbnail(for:)) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 26))
                    .foregroundStyle(NotchTokens.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            guard let url else { return }
            loaded = await cache.thumbnail(for: url)
        }
    }
}
