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

    /// The start of the text without leading blank lines, which would waste the card's four lines.
    static func preview(of text: String) -> String {
        let start = text.firstIndex { !$0.isWhitespace } ?? text.endIndex
        return String(text[start...].prefix(previewCharacters))
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
}
