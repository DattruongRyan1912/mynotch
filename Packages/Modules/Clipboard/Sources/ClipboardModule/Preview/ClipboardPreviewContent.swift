import Foundation

/// What the large preview shows for an item, decided apart from the drawing so every kind is testable as values. Nothing here
/// touches the disk except `ClipboardFileFacts.system`, which only asks about files, and nothing is written anywhere.
enum ClipboardPreviewContent: Equatable, Sendable {
    case text(ClipboardPreviewText)
    case image(ClipboardPreviewImageInfo)
    case color(ClipboardColorValues)
    case link(ClipboardPreviewLink)
    case files(ClipboardPreviewFiles)

    init(item: ClipboardItem, facts: ClipboardFileFacts = .system) {
        switch item.content {
        case .text(let text), .richText(let text, _):
            self = .text(ClipboardPreviewText(text, language: item.codeLanguage))
        case .image(let image):
            self = .image(ClipboardPreviewImageInfo(image))
        case .color(let hex, let original):
            // A stored colour is always readable; one that is not is shown as the words it was copied as.
            if let values = ClipboardColorValues(hex: hex, original: original) {
                self = .color(values)
            } else {
                self = .text(ClipboardPreviewText(original ?? hex, language: nil))
            }
        case .link(let url):
            self = .link(ClipboardPreviewLink(url))
        case .files(let urls):
            self = .files(ClipboardPreviewFiles(urls, facts: facts))
        }
    }
}

/// The words of a text or of code, bounded so a 2 MB copy neither stalls the window nor fills memory with layout.
struct ClipboardPreviewText: Equatable, Sendable {
    /// The most characters the preview lays out. A text this long fills a screen hundreds of times over.
    static let characterLimit = 200_000

    /// What is shown: the start of the text, cut between characters, with its blank lines and indentation.
    let text: String
    /// The text had more than `characterLimit` characters; the rest is not shown.
    let isTruncated: Bool
    /// The size of the whole text, not of what is shown.
    let byteCount: Int
    /// Set for code, which is coloured by it.
    let language: CodeLanguage?

    init(_ text: String, language: CodeLanguage?) {
        byteCount = text.utf8.count
        self.language = language
        // A character is at least one byte, so a text of that many bytes or fewer cannot be over the limit: no count of characters.
        guard byteCount > Self.characterLimit else {
            self.text = text
            isTruncated = false
            return
        }
        let shown = text.prefix(Self.characterLimit)
        self.text = String(shown)
        isTruncated = shown.endIndex != text.endIndex
    }
}

struct ClipboardPreviewImageInfo: Equatable, Sendable {
    let fileName: String
    let pixelWidth: Int
    let pixelHeight: Int
    let byteCount: Int

    init(_ image: ClipboardImage) {
        fileName = image.fileName
        pixelWidth = image.pixelWidth
        pixelHeight = image.pixelHeight
        byteCount = image.byteCount
    }

    var dimensionsText: String { "\(pixelWidth) × \(pixelHeight)" }
    var sizeText: String { ClipboardPreviewFormat.size(byteCount) }
}

/// A link as the preview shows it: the whole address, large, and its parts. Never fetched: there is no title unless the item had
/// one, and an item holds only the address.
struct ClipboardPreviewLink: Equatable, Sendable {
    let address: String
    let scheme: String?
    /// The host of a web link; what follows the scheme for a link with none (mail).
    let host: String
    /// Path and query of a web link; nil when there is none.
    let detail: String?

    init(_ url: URL) {
        address = url.absoluteString
        scheme = url.scheme
        let parts = ClipboardCardText.link(url)
        host = parts.title
        detail = parts.detail
    }
}

/// A colour's three common spellings, worked out from its stored hex, for the swatch's caption.
struct ClipboardColorValues: Equatable, Sendable {
    let hex: String
    let rgb: String
    let hsl: String
    /// 0 to 1.
    let alpha: Double
    /// The words it was copied as when they were not hex (`rgb(255, 136, 0)`), as the card shows them.
    let original: String?

    /// nil for a hex that is not "#RRGGBB" or "#RRGGBBAA".
    init?(hex: String, original: String?) {
        guard let channels = ClipboardCardText.colorComponents(hex: hex) else { return nil }
        self.hex = hex
        self.original = original
        alpha = channels.alpha
        let red = Int((channels.red * 255).rounded()), green = Int((channels.green * 255).rounded()), blue = Int((channels.blue * 255).rounded())
        // Opaque, however it was written: the plain functions.
        let alphaText = (channels.alpha * 255).rounded() >= 255 ? nil : Self.alphaText(channels.alpha)
        let (hue, saturation, lightness) = Self.hsl(channels.red, channels.green, channels.blue)
        if let alphaText {
            rgb = "rgba(\(red), \(green), \(blue), \(alphaText))"
            hsl = "hsla(\(hue), \(saturation)%, \(lightness)%, \(alphaText))"
        } else {
            rgb = "rgb(\(red), \(green), \(blue))"
            hsl = "hsl(\(hue), \(saturation)%, \(lightness)%)"
        }
    }

    /// 0.5, 0.2, 0.94, 0.05, 0: at most two decimals and no trailing zero, whatever the locale.
    private static func alphaText(_ alpha: Double) -> String {
        let hundredths = Int((alpha * 100).rounded())
        if hundredths % 100 == 0 { return "\(hundredths / 100)" }
        if hundredths % 10 == 0 { return "0.\(hundredths / 10)" }
        return "0." + (hundredths < 10 ? "0" : "") + "\(hundredths)"
    }

    /// Whole degrees and percents, as CSS is usually written.
    private static func hsl(_ red: Double, _ green: Double, _ blue: Double) -> (Int, Int, Int) {
        let high = max(red, green, blue), low = min(red, green, blue)
        let lightness = (high + low) / 2
        let spread = high - low
        guard spread > 0 else { return (0, 0, Int((lightness * 100).rounded())) }
        let saturation = spread / (1 - abs(2 * lightness - 1))
        var hue: Double
        switch high {
        case red: hue = ((green - blue) / spread).truncatingRemainder(dividingBy: 6)
        case green: hue = (blue - red) / spread + 2
        default: hue = (red - green) / spread + 4
        }
        hue *= 60
        if hue < 0 { hue += 360 }
        return (Int(hue.rounded()) % 360, Int((saturation * 100).rounded()), Int((lightness * 100).rounded()))
    }
}

/// What the preview asks the file system about a file already on disk. A value of one closure, so tests answer for fake paths and
/// nothing reads a real one. It only asks: nothing in the preview creates, copies or writes a file.
nonisolated struct ClipboardFileFacts: Sendable {
    struct Look: Equatable, Sendable {
        var isDirectory: Bool
        /// A folder that Finder treats as one thing, like an app.
        var isPackage = false
        var byteCount: Int?
        /// "Tài liệu PDF", in the system's words.
        var kind: String?
    }

    /// nil when there is no such file any more.
    var look: @Sendable (URL) -> Look?

    static let none = ClipboardFileFacts { _ in nil }

    /// Of the file a link leads to, not of the link: an app that is a link to somewhere else (Safari's is) is an app, and a link
    /// that leads nowhere is a file that is gone.
    static let system = ClipboardFileFacts { url in
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .fileSizeKey, .localizedTypeDescriptionKey]
        // `realpath` follows links all the way (`resolvingSymlinksInPath` keeps /tmp and /var as they are) and fails for a file that
        // is not there, which a dangling link is.
        guard let resolved = realpath(url.path(percentEncoded: false), nil) else { return nil }
        defer { free(resolved) }
        guard let values = try? URL(fileURLWithPath: String(cString: resolved)).resourceValues(forKeys: keys) else { return nil }
        return Look(
            isDirectory: values.isDirectory ?? false, isPackage: values.isPackage ?? false, byteCount: values.fileSize,
            kind: values.localizedTypeDescription
        )
    }
}

nonisolated struct ClipboardPreviewFiles: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let url: URL
        let name: String
        /// The folder it is in, as a path.
        let folder: String
        /// false when the file is gone, which is said instead of drawn as if it were there.
        let exists: Bool
        let isDirectory: Bool
        let isPackage: Bool
        let kind: String?
        let sizeText: String?
    }

    /// The most files listed; a copy of a whole folder can name thousands.
    static let entryLimit = 100

    let entries: [Entry]
    /// Files beyond the limit, not listed.
    let omittedCount: Int

    /// Asks about each file where it is called.
    init(_ urls: [URL], facts: ClipboardFileFacts) {
        entries = urls.prefix(Self.entryLimit).map { url in
            let look = facts.look(url)
            return Entry(
                url: url, name: url.lastPathComponent,
                folder: (url.path(percentEncoded: false) as NSString).deletingLastPathComponent, exists: look != nil,
                isDirectory: look?.isDirectory ?? false, isPackage: look?.isPackage ?? false, kind: look?.kind,
                sizeText: look?.byteCount.map(ClipboardPreviewFormat.size)
            )
        }
        omittedCount = max(urls.count - Self.entryLimit, 0)
    }

    /// The same, asked off the main actor: a file on a network mount that does not answer, or one that iCloud has yet to download,
    /// can take seconds, which the main actor must never wait for.
    @concurrent static func load(_ urls: [URL], facts: ClipboardFileFacts = .system) async -> ClipboardPreviewFiles {
        ClipboardPreviewFiles(urls, facts: facts)
    }

    /// The file Quick Look is asked to draw: a single one that is there and is not a plain folder.
    var quickLookURL: URL? {
        guard omittedCount == 0, entries.count == 1, let entry = entries.first, entry.exists, !entry.isDirectory || entry.isPackage else { return nil }
        return entry.url
    }
}

nonisolated enum ClipboardPreviewFormat {
    /// "1,2 MB", in the system's units.
    static func size(_ byteCount: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }
}
