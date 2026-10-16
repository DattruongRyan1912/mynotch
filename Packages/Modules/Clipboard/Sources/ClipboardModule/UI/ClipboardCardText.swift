import Foundation

/// The words a card shows, apart from the view so they are testable.
enum ClipboardCardText {
    /// Four lines of a 112 pt card never need more; laying out a 2 MB copy would stall scrolling.
    static let previewCharacters = 400

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.unitsStyle = .full
        return formatter
    }()

    /// The start of the text without leading blank lines, which would waste the card's four lines. `limit` is for a
    /// preview that shows more than a card, like the floating panel's.
    static func preview(of text: String, limit: Int = previewCharacters) -> String {
        let start = text.firstIndex { !$0.isWhitespace } ?? text.endIndex
        return String(text[start...].prefix(limit))
    }

    /// Like `preview`, but starts at the line of the first character that is not blank, so that line keeps its indentation,
    /// and shows a tab as four spaces, which a monospaced `Text` would squeeze to one.
    static func codePreview(of text: String, limit: Int = previewCharacters) -> String {
        var lineStart = text.startIndex
        var index = text.startIndex
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
            if text[text.index(before: index)].isNewline { lineStart = index }
        }
        guard index < text.endIndex else { return "" }
        return String(text[lineStart...].prefix(limit)).replacing("\t", with: "    ")
    }

    /// "2 phút trước"; anything under a minute (or in the future, after a clock change) is "Vừa xong", since the tab
    /// refreshes these once a minute.
    static func relativeTime(_ date: Date, now: Date) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return "Vừa xong" }
        return relativeFormatter.localizedString(for: date, relativeTo: now)
    }

    /// Host and path of a web link; mail and other host-less links show what follows the scheme.
    static func link(_ url: URL) -> (title: String, detail: String?) {
        guard let host = url.host(percentEncoded: false), !host.isEmpty else {
            let text = url.absoluteString
            let rest = url.scheme.map { String(text.dropFirst($0.count + 1)) } ?? text
            return (rest.removingPercentEncoding ?? rest, nil)
        }
        var detail = url.path(percentEncoded: false)
        if let query = url.query(percentEncoded: false) { detail += "?" + query }
        return (host, detail.isEmpty || detail == "/" ? nil : detail)
    }

    static func files(_ urls: [URL]) -> (title: String, detail: String?) {
        (urls.first?.lastPathComponent ?? "", urls.count > 1 ? "và \(urls.count - 1) file khác" : nil)
    }

    /// Components of a stored color, which is always "#RRGGBB" or "#RRGGBBAA".
    static func colorComponents(hex: String) -> (red: Double, green: Double, blue: Double, alpha: Double)? {
        guard hex.first == "#", [7, 9].contains(hex.count), let value = UInt64(hex.dropFirst(), radix: 16) else { return nil }
        let rgba = hex.count == 9 ? value : value << 8 | 0xFF
        func channel(_ shift: UInt64) -> Double { Double((rgba >> shift) & 0xFF) / 255 }
        return (channel(24), channel(16), channel(8), channel(0))
    }

    /// What VoiceOver reads for a card: kind, content, time and whether it is pinned.
    static func accessibilityLabel(for item: ClipboardItem, isPinned: Bool, now: Date) -> String {
        var parts = [kindTitle(of: item), summary(of: item.content), relativeTime(item.copiedAt, now: now)]
        if isPinned { parts.append("đã ghim") }
        return parts.joined(separator: ", ")
    }

    /// "Mã Swift" for code, otherwise the name of its kind.
    static func kindTitle(of item: ClipboardItem) -> String {
        guard let language = item.codeLanguage else { return item.content.kind.title }
        return language == .generic ? ClipboardSearchTerms.codeTitle : ClipboardSearchTerms.codeTitle + " " + language.title
    }

    /// What a list row calls the item: an image by its size, anything else by its summary, and a link whose page was read by its host and
    /// then the title of the page. The host comes first and is always there: a page can call itself anything, and a title that is cut at the
    /// end of the row must not take the address with it.
    static func rowTitle(of content: ClipboardContent, linkTitle: String? = nil) -> String {
        if case .image(let image) = content { return "Ảnh \(image.pixelWidth) × \(image.pixelHeight)" }
        if case .link(let url) = content, let linkTitle { return "\(link(url).title) · \(linkTitle)" }
        return summary(of: content)
    }

    /// One line of what the item holds, for VoiceOver and the library's list rows.
    static func summary(of content: ClipboardContent) -> String {
        switch content {
        case .text(let text), .richText(let text, _):
            return preview(of: text).prefix(200).split(whereSeparator: \.isNewline).joined(separator: " ")
        case .link(let url):
            let link = Self.link(url)
            return [link.title, link.detail].compactMap(\.self).joined(separator: " ")
        case .color(let hex, let original):
            return original ?? hex
        case .image(let image):
            return "\(image.pixelWidth) × \(image.pixelHeight)"
        case .files(let urls):
            let files = Self.files(urls)
            return [files.title, files.detail].compactMap(\.self).joined(separator: ", ")
        }
    }
}
