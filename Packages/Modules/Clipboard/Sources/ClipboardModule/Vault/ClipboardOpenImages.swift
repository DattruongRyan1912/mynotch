import Foundation

/// The pictures of the open locked boards, kept in memory and nowhere else: a picture is a file on disk only for the length of a drag.
/// Cards, thumbnails, copy and paste read them from here, through a URL that names no file (`url(forFileName:)`).
final class ClipboardOpenImages {
    /// The scheme of the URLs that stand for a picture held here; nothing can open one as a file.
    static let scheme = "mynotch-open-image"

    private var byBoard: [UUID: [String: Data]] = [:]

    var isEmpty: Bool { byBoard.values.allSatisfy(\.isEmpty) }

    /// What a view is given in place of a file URL for the picture called `fileName`.
    static func url(forFileName fileName: String) -> URL {
        URL(string: "\(scheme):///\(fileName)") ?? URL(fileURLWithPath: "/")
    }

    func set(_ images: [String: Data], for board: UUID) {
        byBoard[board] = images
    }

    func add(_ data: Data, named fileName: String, to board: UUID) {
        byBoard[board, default: [:]][fileName] = data
    }

    func data(forFileName fileName: String) -> Data? {
        byBoard.values.lazy.compactMap { $0[fileName] }.first
    }

    func contains(_ fileName: String) -> Bool {
        byBoard.values.contains { $0[fileName] != nil }
    }

    /// The bytes of a picture item held here; nil for any other item.
    func data(for item: ClipboardItem) -> Data? {
        guard case .image(let image) = item.content else { return nil }
        return data(forFileName: image.fileName)
    }

    func images(of board: UUID) -> [String: Data] {
        byBoard[board] ?? [:]
    }

    /// Forgets the pictures of `board` that no item names any more.
    func retain(_ names: Set<String>, for board: UUID) {
        byBoard[board] = byBoard[board]?.filter { names.contains($0.key) }
    }

    func remove(board: UUID) {
        byBoard[board] = nil
    }

    func removeAll() {
        byBoard = [:]
    }
}
