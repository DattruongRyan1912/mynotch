import AppKit
import NotchUI
import SwiftUI

/// What a card shows for an item's content, by kind. The notch draws it light on black; the library in the system's
/// colors and at the size its slider chose; the floating panel's preview pane in the system's colors, larger.
struct ClipboardContentPreview: View {
    struct Style {
        var primary: Color
        var secondary: Color
        var swatchBorder: Color
        var textLines: Int
        var textSize: CGFloat
        var detailSize: CGFloat
        var fileIconSize: CGFloat
        /// How much of a long text is laid out; the card's four lines never need more than a few hundred.
        var textCharacters = ClipboardCardText.previewCharacters
        /// The colours of code, which follow the system's appearance unless the card is always dark.
        var codePalette = CodePalette.adaptive

        static let notch = Style(
            primary: NotchTokens.primaryText, secondary: NotchTokens.secondaryText, swatchBorder: .white.opacity(0.2),
            textLines: 4, textSize: 11, detailSize: 10, fileIconSize: 32, codePalette: .dark
        )

        /// The floating panel's preview pane, which has the room for a longer excerpt.
        static let panel = Style(
            primary: .primary, secondary: .secondary, swatchBorder: .primary.opacity(0.2),
            textLines: 14, textSize: 13, detailSize: 11, fileIconSize: 48, textCharacters: 1_500
        )

        static func library(_ size: ClipboardLibraryCardSize) -> Style {
            Style(
                primary: .primary, secondary: .secondary, swatchBorder: .primary.opacity(0.2),
                textLines: size.textLines, textSize: 12, detailSize: 11, fileIconSize: size == .small ? 28 : 40
            )
        }
    }

    let content: ClipboardContent
    /// Set for a text that is code, which is then coloured by this language.
    var codeLanguage: CodeLanguage?
    /// The stored PNG of an image item.
    let imageURL: URL?
    let thumbnails: ClipboardThumbnailCache
    let style: Style

    var body: some View {
        switch content {
        case .text(let text), .richText(let text, _):
            if let codeLanguage {
                ClipboardCodeText(
                    text: ClipboardCardText.codePreview(of: text, limit: style.textCharacters), language: codeLanguage,
                    palette: style.codePalette, size: style.textSize, lines: style.textLines, color: style.primary
                )
            } else {
                Text(ClipboardCardText.preview(of: text, limit: style.textCharacters))
                    .font(.system(size: style.textSize))
                    .foregroundStyle(style.primary)
                    .lineLimit(style.textLines)
            }
        case .link(let url):
            let link = ClipboardCardText.link(url)
            VStack(alignment: .leading, spacing: 3) {
                Label(link.title, systemImage: "link")
                    .font(.system(size: style.textSize, weight: .semibold))
                    .foregroundStyle(style.primary)
                    .lineLimit(1)
                    // Keeps both ends of a long host, e.g. "develo…ple.com".
                    .truncationMode(.middle)
                if let detail = link.detail {
                    Text(detail)
                        .font(.system(size: style.detailSize))
                        .foregroundStyle(style.secondary)
                        .lineLimit(3)
                }
            }
        case .color(let hex, let original):
            VStack(alignment: .leading, spacing: 6) {
                ClipboardColorSwatch(hex: hex, border: style.swatchBorder)
                Text(original ?? hex)
                    .lineLimit(2)
                    .font(.system(size: style.textSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(style.primary)
            }
        case .image:
            ClipboardThumbnailView(url: imageURL, cache: thumbnails, placeholder: style.secondary)
        case .files(let urls):
            let files = ClipboardCardText.files(urls)
            VStack(alignment: .leading, spacing: 3) {
                if let first = urls.first {
                    Image(nsImage: ClipboardIcons.file(first))
                        .resizable()
                        .frame(width: style.fileIconSize, height: style.fileIconSize)
                }
                Text(files.title)
                    .font(.system(size: style.textSize))
                    .foregroundStyle(style.primary)
                    .lineLimit(2)
                if let detail = files.detail {
                    Text(detail)
                        .font(.system(size: style.detailSize))
                        .foregroundStyle(style.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// A color item's swatch; an unreadable hex draws as empty.
struct ClipboardColorSwatch: View {
    let hex: String
    let border: Color
    var cornerRadius: CGFloat = 6

    var body: some View {
        let color = ClipboardCardText.colorComponents(hex: hex)
            .map { Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue, opacity: $0.alpha) }
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(color ?? .clear)
            .overlay { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(border) }
    }
}

/// An image card's preview, decoded once per file and off the main thread.
struct ClipboardThumbnailView: View {
    let url: URL?
    let cache: ClipboardThumbnailCache
    /// Color of the stand-in shown until the thumbnail is ready.
    let placeholder: Color
    var placeholderSize: CGFloat = 26

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
                    .font(.system(size: placeholderSize))
                    .foregroundStyle(placeholder)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            guard let url else { return }
            loaded = await cache.thumbnail(for: url)
        }
    }
}
