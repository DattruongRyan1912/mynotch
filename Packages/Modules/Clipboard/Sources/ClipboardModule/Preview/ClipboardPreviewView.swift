import AppKit
import SwiftUI

/// The large preview: the item the window it belongs to has selected, drawn big. It follows that selection while it is open,
/// and draws nothing once there is none (the item went away, or its board locked).
struct ClipboardPreviewView: View {
    let host: any ClipboardPreviewHosting
    let module: ClipboardModule

    var body: some View {
        Group {
            if let item = host.previewedItem {
                // A fresh view per item, so nothing loaded for the one before can show for the next.
                ClipboardPreviewItemView(item: item, imageSource: module.previewImageSource(of: item))
                    .id(item.id)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Xem trước")
    }
}

struct ClipboardPreviewItemView: View {
    let item: ClipboardItem
    let imageSource: ClipboardPreviewImageSource?
    private let content: ClipboardPreviewContent

    init(item: ClipboardItem, imageSource: ClipboardPreviewImageSource?) {
        self.item = item
        self.imageSource = imageSource
        content = ClipboardPreviewContent(item: item)
    }

    var body: some View {
        VStack(spacing: 0) {
            pane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
    }

    @ViewBuilder private var pane: some View {
        switch content {
        case .text(let text): ClipboardPreviewTextPane(text: text)
        case .image(let info): ClipboardPreviewImagePane(info: info, source: imageSource)
        case .color(let values): ClipboardPreviewColorPane(values: values)
        case .link(let link): ClipboardPreviewLinkPane(link: link)
        case .files(let files): ClipboardPreviewFilesPane(files: files)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Label(kindTitle, systemImage: item.isCode ? ClipboardSearchTerms.codeSystemImage : item.content.kind.systemImage)
            if let detail { Text(detail) }
            if let app = item.sourceAppName { Text(app) }
            Text(ClipboardCardText.relativeTime(item.copiedAt, now: .now))
            Spacer(minLength: 12)
            Text("↑↓ đổi mục  ·  ⏎ dán  ·  esc đóng")
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 18)
        .frame(height: 36)
    }

    private var kindTitle: String {
        item.isCode ? ClipboardCardText.kindTitle(of: item) : item.content.kind.title
    }

    /// The size of what it is, for the kinds that have one worth saying.
    private var detail: String? {
        switch content {
        case .image(let info): "\(info.dimensionsText) · \(info.sizeText)"
        case .text(let text): ClipboardPreviewFormat.size(text.byteCount)
        case .files(let files): files.entries.count > 1 ? "\(files.entries.count + files.omittedCount) file" : nil
        case .color, .link: nil
        }
    }
}

// MARK: Text and code

struct ClipboardPreviewTextPane: View {
    let text: ClipboardPreviewText
    @State private var runs: [ClipboardPreviewHighlight.Run] = []

    var body: some View {
        VStack(spacing: 0) {
            ClipboardPreviewTextView(text: text.text, isCode: text.language != nil, runs: runs)
            if text.isTruncated {
                Divider()
                Text("Văn bản dài: chỉ hiện \(ClipboardPreviewText.characterLimit.formatted()) ký tự đầu")
                    .font(.system(size: 12))
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
                let decoded = await ClipboardPreviewImage.load(source, maxPixelSize: pixels)
                guard !Task.isCancelled else { return }
                image = decoded
                failed = decoded == nil
            }
        }
        .padding(20)
        .accessibilityLabel("Ảnh \(info.dimensionsText)")
    }
}

// MARK: Colours

struct ClipboardPreviewColorPane: View {
    let values: ClipboardColorValues

    var body: some View {
        VStack(spacing: 22) {
            ClipboardColorSwatch(hex: values.hex, border: .primary.opacity(0.2), cornerRadius: 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                if let original = values.original {
                    row("Đã chép", original)
                }
                row("HEX", values.hex)
                row("RGB", values.rgb)
                row("HSL", values.hsl)
            }
        }
        .padding(28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Màu \(values.original ?? values.hex), \(values.rgb), \(values.hsl)")
    }

    private func row(_ name: String, _ value: String) -> some View {
        GridRow {
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .medium, design: .monospaced))
        }
    }
}

// MARK: Links

struct ClipboardPreviewLinkPane: View {
    let link: ClipboardPreviewLink

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "link")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text(link.host)
                    .font(.system(size: 30, weight: .semibold))
                if let detail = link.detail {
                    Text(detail)
                        .font(.system(size: 18, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Divider()
                Text(link.address)
                    .font(.system(size: 15, design: .monospaced))
                Text("Chỉ hiện địa chỉ: MyNotch không mở trang này.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(32)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Link \(link.address)")
    }
}

// MARK: Files

struct ClipboardPreviewFilesPane: View {
    let files: ClipboardPreviewFiles

    var body: some View {
        if let url = files.quickLookURL, let entry = files.entries.first {
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
                        row(entry, iconSize: 36)
                    }
                    if files.omittedCount > 0 {
                        Text("và \(files.omittedCount) file khác")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
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
