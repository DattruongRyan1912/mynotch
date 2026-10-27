import AppKit
import MyNotchCore
import SwiftUI

/// The large preview: the item the window it belongs to has selected, drawn big. It follows that selection while it is open,
/// and draws nothing once there is none (the item went away, or its board locked).
struct ClipboardPreviewView: View {
    let host: any ClipboardPreviewHosting
    let module: ClipboardModule

    var body: some View {
        Group {
            if let item = host.previewedItem {
                // A fresh view per item and per version of its words, so nothing loaded for the one before can show for the next, and
                // an item the editor replaced is drawn again.
                ClipboardPreviewItemView(
                    item: item,
                    imageSource: module.previewImageSource(of: item),
                    link: module.linkPreviewDisplay(for: item),
                    onEditImage: { host.closePreview() }
                )
                .id(ClipboardPreviewIdentity(id: item.id, contentHash: item.contentHash))
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Xem trước")
    }
}

/// What makes a preview view the same view: the item and its words.
struct ClipboardPreviewIdentity: Hashable {
    let id: UUID
    let contentHash: String
}

struct ClipboardPreviewItemView: View {
    let item: ClipboardItem
    let imageSource: ClipboardPreviewImageSource?
    /// What was read of a link's page, when link previews are on and this link may be read.
    var link: ClipboardLinkPreviewDisplay?
    var onEditImage: (() -> Void)?
    /// Worked out once, the first time it is needed: the view is made again at every change of the history while it is open, and the
    /// cut of a 2 MB text should not be.
    @State private var cache = ContentCache()

    final class ContentCache {
        private var content: ClipboardPreviewContent?

        func content(for item: ClipboardItem) -> ClipboardPreviewContent {
            if let content { return content }
            // The files' facts are left to the files pane, which asks off the main actor.
            let made = ClipboardPreviewContent(item: item, facts: .none)
            content = made
            return made
        }
    }

    private var content: ClipboardPreviewContent { cache.content(for: item) }

    var body: some View {
        VStack(spacing: 0) {
            pane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
    }

    private var pane: some View {
        ClipboardPreviewPane(content: content, item: item, imageSource: imageSource, link: link)
    }

    private func filesOf(_ item: ClipboardItem) -> [URL] {
        if case .files(let urls) = item.content { urls } else { [] }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Label(kindTitle, systemImage: item.isCode ? ClipboardSearchTerms.codeSystemImage : item.content.kind.systemImage)
            if let detail { Text(detail) }
            if let app = item.sourceAppName { Text(app) }
            Text(ClipboardCardText.relativeTime(item.copiedAt, now: .now))
            Spacer(minLength: 12)
            if item.content.kind == .image, imageSource != nil {
                Button {
                    editImage()
                } label: {
                    Label("Sửa ảnh", systemImage: "pencil.and.scribble")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Mở ảnh trong trình chỉnh sửa ảnh (Markup Editor)")
            }
            Text("↑↓ đổi mục  ·  ⏎ dán  ·  esc đóng")
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 18)
        .frame(height: 36)
    }

    private func editImage() {
        guard let imageSource else { return }
        onEditImage?()
        switch imageSource {
        case .file(let url):
            NotificationCenter.default.post(name: .openMarkupEditorForImage, object: url)
        case .memory(let data):
            NotificationCenter.default.post(name: .openMarkupEditorForImage, object: data)
        }
    }

    private var kindTitle: String {
        item.isCode ? ClipboardCardText.kindTitle(of: item) : item.content.kind.title
    }

    /// The size of what it is, for the kinds that have one worth saying.
    private var detail: String? {
        switch content {
        case .image(let info): "\(info.dimensionsText) · \(info.sizeText)"
        case .text(let text): ClipboardPreviewFormat.size(text.byteCount)
        case .files: filesOf(item).count > 1 ? "\(filesOf(item).count) file" : nil
        case .color, .link: nil
        }
    }
}

/// What the large preview and the library's inspector draw for an item, by kind: the large one fills a window and the compact one a
/// pane beside the cards, with smaller type, tighter margins and no Quick Look.
struct ClipboardPreviewPane: View {
    let content: ClipboardPreviewContent
    let item: ClipboardItem
    let imageSource: ClipboardPreviewImageSource?
    var isCompact = false
    var link: ClipboardLinkPreviewDisplay?

    var body: some View {
        switch content {
        case .text(let text): ClipboardPreviewTextPane(text: text, isCompact: isCompact)
        case .image(let info): ClipboardPreviewImagePane(info: info, source: imageSource, isCompact: isCompact)
        case .color(let values): ClipboardPreviewColorPane(values: values, isCompact: isCompact)
        case .link(let address): ClipboardPreviewLinkPane(link: address, isCompact: isCompact, display: link)
        case .files: ClipboardPreviewFilesPane(urls: files, isCompact: isCompact)
        }
    }

    private var files: [URL] {
        if case .files(let urls) = item.content { urls } else { [] }
    }
}

// MARK: Text and code

struct ClipboardPreviewTextPane: View {
    let text: ClipboardPreviewText
    var isCompact = false
    @State private var runs: [ClipboardPreviewHighlight.Run] = []

    var body: some View {
        VStack(spacing: 0) {
            ClipboardPreviewTextView(text: text.text, isCode: text.language != nil, runs: runs, isCompact: isCompact)
            if text.isTruncated {
                Divider()
                Text("Văn bản dài: chỉ hiện \(ClipboardPreviewText.characterLimit.formatted()) ký tự đầu")
                    .font(.system(size: isCompact ? 11 : 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }
        }
        // Off the main actor and after the text is on screen, so a long code never holds the window up. The colours are not
        // kept anywhere but here: closing the preview forgets them.
        .task {
            guard let language = text.language else { return }
            let found = await ClipboardPreviewHighlight.runsOffMain(for: text.text, language: language)
            if !Task.isCancelled { runs = found }
        }
    }
}

// MARK: Pictures

struct ClipboardPreviewImagePane: View {
    let info: ClipboardPreviewImageInfo
    let source: ClipboardPreviewImageSource?
    var isCompact = false

    @Environment(\.displayScale) private var scale
    @State private var image: CGImage?
    @State private var failed = false

    private struct Request: Hashable {
        let size: CGSize
        let scale: CGFloat
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        // Never larger than the picture itself, which would only blur it.
                        .frame(maxWidth: CGFloat(info.pixelWidth) / scale, maxHeight: CGFloat(info.pixelHeight) / scale)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else if failed {
                    Label("Không đọc được ảnh này", systemImage: "photo.badge.exclamationmark")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .task(id: Request(size: geometry.size, scale: scale)) {
                guard let source else {
                    failed = true
                    return
                }
                let pixels = ClipboardPreviewImage.maxPixelSize(
                    display: geometry.size, scale: scale, pixelWidth: info.pixelWidth, pixelHeight: info.pixelHeight
                )
                // After a short wait, so a picture the user is only passing is cancelled before it is decoded.
                let decoded = await ClipboardPreviewImage.loadAfterPause(source, maxPixelSize: pixels)
                guard !Task.isCancelled else { return }
                image = decoded
                failed = decoded == nil
            }
        }
        .padding(isCompact ? 8 : 20)
        .accessibilityLabel("Ảnh \(info.dimensionsText)")
    }
}

// MARK: Colours

struct ClipboardPreviewColorPane: View {
    let values: ClipboardColorValues
    var isCompact = false

    var body: some View {
        VStack(spacing: isCompact ? 8 : 22) {
            ClipboardColorSwatch(hex: values.hex, border: .primary.opacity(0.2), cornerRadius: isCompact ? 10 : 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Grid(alignment: .leading, horizontalSpacing: isCompact ? 10 : 18, verticalSpacing: isCompact ? 2 : 8) {
                if let original = values.original {
                    row("Đã chép", original)
                }
                row("HEX", values.hex)
                row("RGB", values.rgb)
                row("HSL", values.hsl)
            }
        }
        .padding(isCompact ? 10 : 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Màu \(values.original ?? values.hex), \(values.rgb), \(values.hsl)")
    }

    private func row(_ name: String, _ value: String) -> some View {
        GridRow {
            Text(name)
                .font(.system(size: isCompact ? 11 : 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: isCompact ? 12 : 22, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: Links

struct ClipboardPreviewLinkPane: View {
    let link: ClipboardPreviewLink
    var isCompact = false
    /// What was read of the page, when link previews are on and this link may be read; nil when it is not read at all.
    var display: ClipboardLinkPreviewDisplay?

    /// What the note under the address says: that the page is not opened, or where the title and picture come from. Nothing while
    /// nothing has been read yet.
    var note: String? {
        guard let display else { return "Chỉ hiện địa chỉ: MyNotch không mở trang này." }
        return display.isEmpty ? nil : "Tiêu đề và ảnh lấy từ trang của link."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: isCompact ? 6 : 14) {
                if let imageURL = display?.imageURL {
                    ClipboardLinkPreviewPicture(url: imageURL, height: isCompact ? 70 : 150)
                } else {
                    Image(systemName: "link")
                        .font(.system(size: isCompact ? 18 : 34))
                        .foregroundStyle(.secondary)
                }
                if let title = display?.title {
                    Text(title)
                        .font(.system(size: isCompact ? 14 : 26, weight: .semibold))
                    Text(link.host)
                        .font(.system(size: isCompact ? 11 : 16))
                        .foregroundStyle(.secondary)
                } else {
                    Text(link.host)
                        .font(.system(size: isCompact ? 16 : 30, weight: .semibold))
                }
                if let detail = link.detail {
                    Text(detail)
                        .font(.system(size: isCompact ? 11 : 18, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Divider()
                Text(link.address)
                    .font(.system(size: isCompact ? 11 : 15, design: .monospaced))
                    .textSelection(.enabled)
                if !isCompact, let note {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(isCompact ? 12 : 32)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(display?.title.map { "Link \($0), \(link.address)" } ?? "Link \(link.address)")
    }
}

/// The small picture read from a link's page, decoded where it is drawn and never larger than it is.
struct ClipboardLinkPreviewPicture: View {
    let url: URL
    let height: CGFloat

    @Environment(\.displayScale) private var scale
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: CGFloat(image.width) / scale, maxHeight: min(height, CGFloat(image.height) / scale), alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Color.clear.frame(height: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: url) {
            let decoded = await ClipboardThumbnailCache.decode(url, maxPixelSize: ClipboardLinkImage.maxPixelSize)
            if !Task.isCancelled { image = decoded }
        }
    }
}

// MARK: Files

struct ClipboardPreviewFilesPane: View {
    let urls: [URL]
    var isCompact = false
    @State private var files: ClipboardPreviewFiles?

    var body: some View {
        Group {
            if let files {
                loaded(files)
            } else {
                ProgressView()
            }
        }
        // Asked off the main actor, since a file on a network mount can take its time to answer.
        .task {
            let found = await ClipboardPreviewFiles.load(urls)
            if !Task.isCancelled { files = found }
        }
    }

    @ViewBuilder private func loaded(_ files: ClipboardPreviewFiles) -> some View {
        // The compact pane lists the files only: Quick Look's own drawing belongs to the large preview.
        if !isCompact, let url = files.quickLookURL, let entry = files.entries.first {
            VStack(spacing: 0) {
                row(entry, iconSize: 40)
                    .padding(14)
                Divider()
                // Quick Look's own drawing of the file, as Finder shows it.
                ClipboardQuickLookView(url: url)
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(files.entries.enumerated()), id: \.offset) { _, entry in
                        row(entry, iconSize: isCompact ? 28 : 36)
                    }
                    if files.omittedCount > 0 {
                        Text("và \(files.omittedCount) file khác")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(isCompact ? 12 : 24)
            }
        }
    }

    /// The file's icon, name, kind, size and folder, or that it is not there any more.
    private func row(_ entry: ClipboardPreviewFiles.Entry, iconSize: CGFloat) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: ClipboardIcons.file(entry.url))
                .resizable()
                .frame(width: iconSize, height: iconSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(entry.exists ? [entry.kind, entry.sizeText].compactMap(\.self).joined(separator: " · ") : "Không còn trên máy")
                    .font(.system(size: 12))
                    .foregroundStyle(entry.exists ? Color.secondary : Color.red)
                Text(entry.folder)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
