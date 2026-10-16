import Foundation

/// What was read from a link's page, kept with the link's item. The picture is a small file named after the link, not part of the item:
/// `imageFileName(forHash:)`.
nonisolated struct ClipboardLinkPreview: Codable, Sendable, Hashable {
    /// The page's title, cleaned and at most `ClipboardLinkText.titleLimit` characters; nil when the page had none.
    var title: String?
    /// Whether the picture file was stored.
    var hasImage: Bool

    var isEmpty: Bool { title == nil && !hasImage }

    init(title: String?, hasImage: Bool) {
        self.title = title
        self.hasImage = hasImage
    }

    /// `history.json` is the user's to edit, and it is drawn in cards: a missing flag is no picture, and a title is made plain and cut again
    /// (its first 2,000 characters, so a megabyte of it costs nothing), as when it was read.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? container.decodeIfPresent(String.self, forKey: .title)).flatMap { ClipboardLinkText.title(from: String($0.prefix(2_000))) }
        hasImage = (try? container.decodeIfPresent(Bool.self, forKey: .hasImage)) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case title, hasImage
    }

    /// The file of a link's picture, from the link item's content hash, which is the same for the same address. Its own pattern, so
    /// a picture of an image item can never be taken for it.
    static func imageFileName(forHash hash: String) -> String {
        "link-\(hash).png"
    }

    static func isImageFileName(_ fileName: String) -> Bool {
        fileName.wholeMatch(of: /link-[0-9a-f]{64}\.png/) != nil
    }
}

nonisolated extension ClipboardItem {
    /// The file of this link's picture, whether or not there is one.
    var linkPreviewFileName: String? {
        guard case .link = content else { return nil }
        return ClipboardLinkPreview.imageFileName(forHash: contentHash)
    }
}

nonisolated extension ClipboardHistory {
    /// The files that items hold a picture in. An item of a board that has a lock holds none: nothing of what it was ever read
    /// from the network stays with it.
    var linkPreviewFileNames: Set<String> {
        let holders = items.filter { $0.linkPreview?.hasImage == true }
        guard !holders.isEmpty else { return [] }
        let hidden = protectedItemIDs
        return Set(holders.filter { !hidden.contains($0.id) }.compactMap(\.linkPreviewFileName))
    }

    /// Sets what was read of the item's page. False for an item that is gone, that is not a link, or that is in a board that has a lock.
    @discardableResult
    mutating func setLinkPreview(_ preview: ClipboardLinkPreview, for id: UUID) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }), case .link = items[index].content,
              !boards.contains(where: { $0.isProtected && $0.itemIDs.contains(id) }) else { return false }
        items[index].linkPreview = preview
        return true
    }
}
