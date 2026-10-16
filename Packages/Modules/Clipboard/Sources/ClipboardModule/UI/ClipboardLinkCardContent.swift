import SwiftUI

/// A link's card when its page has been read: the picture, the title and the host. In the colours of the style it is drawn in, so it reads on
/// the black notch, on Liquid Glass, in a window and on the panel's material alike.
struct ClipboardLinkCardContent: View {
    let url: URL
    let display: ClipboardLinkPreviewDisplay
    let thumbnails: ClipboardThumbnailCache
    let style: ClipboardContentPreview.Style

    var body: some View {
        let parts = ClipboardCardText.link(url)
        VStack(alignment: .leading, spacing: 3) {
            if let imageURL = display.imageURL {
                ClipboardThumbnailView(url: imageURL, cache: thumbnails, placeholder: style.secondary, placeholderSize: 14)
                    .frame(height: style.linkImageHeight)
            }
            if let title = display.title {
                Text(title)
                    .font(.system(size: style.textSize, weight: .semibold))
                    .foregroundStyle(style.primary)
                    .lineLimit(style.linkTitleLines)
            }
            Label(parts.title, systemImage: "link")
                .font(.system(size: style.detailSize))
                .foregroundStyle(style.secondary)
                .lineLimit(1)
                // Keeps both ends of a long host, e.g. "develo…ple.com".
                .truncationMode(.middle)
            if style.showsLinkPath, let detail = parts.detail {
                Text(detail)
                    .font(.system(size: style.detailSize))
                    .foregroundStyle(style.secondary)
                    .lineLimit(2)
            }
        }
    }
}

/// Asks the module to read a link's page once its card has been on screen for a moment, so a card that is only scrolled past reads nothing.
/// Cards of other kinds add nothing.
private struct ClipboardLinkPreviewRequest: ViewModifier {
    let item: ClipboardItem
    let module: ClipboardModule

    @ViewBuilder
    func body(content: Content) -> some View {
        if case .link = item.content {
            content.task(id: item.id) {
                try? await Task.sleep(for: module.linkPreviewDwell)
                guard !Task.isCancelled else { return }
                module.requestLinkPreview(for: item)
            }
        } else {
            content
        }
    }
}

extension View {
    /// The link of `item`, when it is one, is read by `module` once this view has been shown for a moment.
    func requestsLinkPreview(of item: ClipboardItem, from module: ClipboardModule) -> some View {
        modifier(ClipboardLinkPreviewRequest(item: item, module: module))
    }
}
