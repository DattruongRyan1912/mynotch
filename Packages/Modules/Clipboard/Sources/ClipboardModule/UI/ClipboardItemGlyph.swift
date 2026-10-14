import SwiftUI

/// The small picture that leads a list row: an image's thumbnail, a color's swatch, a file's icon, or the symbol of the
/// kind. Shared by the library's list and the floating panel's rows.
struct ClipboardItemGlyph: View {
    let item: ClipboardItem
    let imageURL: URL?
    let thumbnails: ClipboardThumbnailCache
    /// Side of a swatch or a file icon.
    var iconSize: CGFloat = 28

    var body: some View {
        switch item.content {
        case .image:
            ClipboardThumbnailView(url: imageURL, cache: thumbnails, placeholder: .secondary, placeholderSize: 16)
        case .color(let hex, _):
            ClipboardColorSwatch(hex: hex, border: .primary.opacity(0.2))
                .frame(width: iconSize, height: iconSize)
        case .files(let urls):
            if let first = urls.first {
                Image(nsImage: ClipboardIcons.file(first))
                    .resizable()
                    .frame(width: iconSize, height: iconSize)
            }
        case .text, .richText, .link:
            Image(systemName: item.content.kind.systemImage)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
    }
}
