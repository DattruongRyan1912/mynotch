import CryptoKit
import Foundation

/// What one history item holds. Image bytes live in a separate file so history stays small.
nonisolated enum ClipboardContent: Codable, Sendable, Hashable {
    case text(String)
    case richText(plain: String, rtf: Data)
    case link(URL)
    /// Normalized uppercase "#RRGGBB" or "#RRGGBBAA", for the swatch. `original` is the text as copied when it was not
    /// a hex code (`rgb(255, 136, 0)`, `hsl(…)`), which the card shows and copying back writes; nil for hex colors.
    case color(hex: String, original: String? = nil)
    case image(ClipboardImage)
    case files([URL])

    var kind: ClipboardKind {
        switch self {
        case .text, .richText: .text
        case .link: .link
        case .color: .color
        case .image: .image
        case .files: .file
        }
    }

    /// Text used for search and "copy as plain text"; nil for images.
    var plainText: String? {
        switch self {
        case .text(let text): text
        case .richText(let plain, _): plain
        case .link(let url): url.absoluteString
        case .color(let hex, let original): original ?? hex
        case .image: nil
        case .files(let urls): urls.map { $0.path(percentEncoded: false) }.joined(separator: "\n")
        }
    }

    /// SHA-256 hex of the kind plus the canonical string, so the same string as text and as a color stay distinct
    /// while rich text and plain text with the same characters count as one item. Images use their file name,
    /// which is already the hash of the PNG data.
    static func hash(of content: ClipboardContent) -> String {
        let canonical = if case .image(let image) = content { image.fileName } else { content.plainText ?? "" }
        return Data("\(content.kind.rawValue):\(canonical)".utf8).sha256Hex
    }
}

/// Metadata of an image stored as `images/<fileName>`.
nonisolated struct ClipboardImage: Codable, Sendable, Hashable {
    /// "<sha256 of the PNG data>.png".
    let fileName: String
    let pixelWidth: Int
    let pixelHeight: Int
    let byteCount: Int
}

/// Filter categories shown in the tab.
nonisolated enum ClipboardKind: String, Codable, Sendable, CaseIterable {
    case text, link, image, file, color
}

nonisolated extension Data {
    var sha256Hex: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
