import Foundation

/// What was on the pasteboard at one changeCount (first item only, like most clipboard managers).
nonisolated struct PasteboardSnapshot: Sendable, Equatable {
    /// Raw UTI strings of the first item.
    var types: [String] = []
    /// public.utf8-plain-text
    var string: String?
    /// public.rtf
    var rtf: Data?
    var png: Data?
    var tiff: Data?
    /// public.file-url of every item, so multi-file copies are kept whole.
    var fileURLs: [URL] = []
    /// public.url
    var url: URL?
}
