import Foundation

/// The `.mynotchclip` file: a zip archive holding `manifest.json` and one payload per text, rich text or image
/// (`items/<id>.txt`, `.rtf`, `.png`). Everything small (links, colours, file references, boards) lives in the manifest.
nonisolated enum ClipboardBackupFormat {
    static let fileExtension = "mynotchclip"
    /// Written in the manifest, so a zip of something else is told apart from a backup.
    static let formatName = "mynotchclip"
    /// Bumped when a change would make an older MyNotch misread the file. New optional keys do not need it: they are ignored.
    static let currentVersion = 1
    static let manifestName = "manifest.json"
    /// What a file may hold: no entry over 50 MB, no more than 2 GB (before compression) in all. An export leaves out
    /// what would not fit, and an import refuses a file that goes over, before reading any of it.
    static let maxItemBytes = 50 * 1024 * 1024
    static let maxTotalBytes = 2 * 1024 * 1024 * 1024
    static let limits = ZipLimits(perEntry: maxItemBytes, total: maxTotalBytes, directory: 16 * 1024 * 1024)
    /// What a manifest may list, whatever the size of the file: a hostile one could otherwise make thousands of boards, or pin
    /// everything it brings past the limits of the history for good. A file over any of these is refused before anything is
    /// written. Names are counted in characters.
    static let maxItems = 50_000
    static let maxBoards = 200
    static let maxPinsPerBoard = maxItems
    static let maxPinsTotal = 100_000
    static let maxNameLength = 200

    /// The entry holding one part of an item. Built from the item's id and a fixed extension, never from text in the file.
    static func payloadName(for id: UUID, extension fileExtension: String) -> String {
        "items/\(id.uuidString).\(fileExtension)"
    }

    /// The entry holding a locked board's vault file, built from its id and never from text in the file.
    static func vaultName(for boardID: UUID) -> String {
        "vaults/\(boardID.uuidString).\(ClipboardVaultFile.fileExtension)"
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

/// What to put in a backup.
nonisolated struct ClipboardBackupOptions: Sendable, Equatable {
    enum Scope: String, Sendable, Equatable {
        case allHistory = "all"
        /// Only the items of boards, and every board.
        case pinnedOnly = "pinned"
    }

    var scope: Scope = .allHistory
    /// Items an app marked as secrets stay out of the file unless the user asks for them.
    var skipSensitive = true
    /// Boards that have a lock are left out, name and all, unless the user asks for them. Then each goes in as its vault file, still
    /// sealed, and needs its password to open. (A Touch ID board cannot: its key is in this Mac's Keychain.)
    var includeLockedBoards = false
}

nonisolated enum ClipboardBackupError: Error, Equatable, LocalizedError {
    case moduleStopped
    case notABackup
    case newerVersion(Int)
    /// The manifest is not the JSON a backup holds.
    case malformed
    /// An entry named to leave its folder, a link, a device or a repeated name. Carries the name, which is not shown.
    case unsafeEntry(String)
    case tooLarge
    case tooManyItems
    case tooManyBoards
    case tooManyPins
    /// A board name, or the name or identifier of the app an item came from, over `maxNameLength`.
    case tooLongText
    case itemTooLarge(String)
    case unsupported
    case damaged
    case cannotRead(String)
    case cannotWrite(String)
    case busy

    var errorDescription: String? {
        switch self {
        case .busy: "Hệ thống đang bận dọn dẹp lịch sử, vui lòng thử lại sau."
        case .moduleStopped: "Hãy bật module Clipboard rồi thử lại."
        case .notABackup: "Đây không phải tệp sao lưu của MyNotch."
        case .newerVersion(let version): "Tệp này do bản MyNotch mới hơn tạo (định dạng \(version)). Hãy cập nhật MyNotch rồi khôi phục."
        case .malformed: "Tệp sao lưu bị hỏng: không đọc được danh sách mục."
        case .unsafeEntry: "Tệp có mục không an toàn nên không được dùng."
        case .tooLarge: "Tệp quá lớn: tối đa 2 GB."
        case .tooManyItems: "Tệp có quá nhiều mục (tối đa 50.000)."
        case .tooManyBoards: "Tệp có quá nhiều board (tối đa 200)."
        case .tooManyPins: "Tệp ghim quá nhiều mục vào board."
        case .tooLongText: "Tệp có tên dài bất thường nên không được dùng."
        case .itemTooLarge: "Tệp có mục lớn hơn 50 MB nên không được dùng."
        case .unsupported: "Tệp dùng tính năng của định dạng zip mà MyNotch không hỗ trợ."
        case .damaged: "Tệp sao lưu bị hỏng."
        case .cannotRead(let reason): "Không đọc được tệp: \(reason)"
        case .cannotWrite(let reason): "Không ghi được tệp: \(reason)"
        }
    }

    /// What a failure of the zip layer means to the user.
    init(_ error: ZipError) {
        switch error {
        case .notAnArchive: self = .notABackup
        case .unsupported: self = .unsupported
        case .unsafeName(let name), .duplicateName(let name), .notARegularFile(let name): self = .unsafeEntry(name)
        case .entryTooLarge(let name, _): self = .itemTooLarge(name)
        case .archiveTooLarge, .tooManyEntries: self = .tooLarge
        case .corrupt: self = .damaged
        }
    }
}

/// What an export wrote and what it left out.
nonisolated struct ClipboardBackupExportSummary: Sendable, Equatable {
    var itemCount = 0
    var boardCount = 0
    var skippedSensitive = 0
    /// Over the size limits of the format.
    var skippedTooLarge = 0
    /// An image whose file is gone.
    var skippedUnreadable = 0
    /// Items that hold files, which are saved as paths and may not be found on another Mac.
    var fileItemCount = 0
    /// Boards with a lock that went in as their sealed vault file.
    var lockedBoardCount = 0
    /// Boards with a lock that stayed out: all of them unless the user asked, and a Touch ID board always.
    var skippedLockedBoards = 0
    /// Of those, the ones whose key is in this Mac's Keychain, which cannot be opened anywhere else.
    var skippedTouchIDBoards = 0

    var text: String {
        var text = "Đã sao lưu \(itemCount) mục và \(boardCount) board"
        var skipped = [
            skippedSensitive > 0 ? "bỏ qua \(skippedSensitive) mục nhạy cảm" : nil,
            skippedTooLarge > 0 ? "\(skippedTooLarge) mục quá lớn" : nil,
            skippedUnreadable > 0 ? "\(skippedUnreadable) mục không đọc được" : nil,
        ].compactMap { $0 }
        if skippedLockedBoards > 0 {
            var note = "bỏ qua \(skippedLockedBoards) board đã khoá"
            if skippedTouchIDBoards > 0 { note += " (board dùng Touch ID chỉ mở được trên máy này nên không đưa vào tệp)" }
            skipped.append(note)
        }
        if lockedBoardCount > 0 { skipped.append("gồm \(lockedBoardCount) board đã khoá, vẫn được mã hoá: cần mật khẩu của từng board để mở") }
        if !skipped.isEmpty { text += " (" + skipped.joined(separator: ", ") + ")" }
        text += "."
        if fileItemCount > 0 {
            text += " \(fileItemCount) mục file chỉ lưu đường dẫn nên có thể không khôi phục được trên máy khác."
        }
        return text
    }
}

/// What an import did.
nonisolated struct ClipboardBackupRestoreSummary: Sendable, Equatable {
    var added = 0
    var duplicates = 0
    /// Items of the file that could not be read.
    var unreadable = 0
    var boardsCreated = 0
    /// Boards with a lock that came back sealed, to be opened with their own password.
    var lockedBoardsRestored = 0
    /// Added, then removed at once by the history limits in Settings.
    var prunedByLimits = 0
    /// Items that were in the history, removed to make room under the limits.
    var evictedExisting = 0

    var text: String {
        var parts = ["Đã thêm \(added) mục"]
        if duplicates > 0 { parts.append("bỏ qua \(duplicates) trùng lặp") }
        if unreadable > 0 { parts.append("\(unreadable) mục không đọc được") }
        if boardsCreated > 0 { parts.append("tạo \(boardsCreated) board mới") }
        if lockedBoardsRestored > 0 { parts.append("khôi phục \(lockedBoardsRestored) board đã khoá (mở bằng mật khẩu của nó)") }
        var text = parts.joined(separator: ", ")
        if prunedByLimits > 0 {
            text += ". \(prunedByLimits) mục vượt giới hạn hoặc thời gian giữ trong Cài đặt nên đã bị dọn"
        }
        if evictedExisting > 0 {
            text += ". \(evictedExisting) mục đã có bị xoá để vừa giới hạn lịch sử"
        }
        return text
    }
}

/// The manifest as it is written. Optional keys are ignored when missing and unknown keys are ignored when present, so a
/// file with more in it than this version knows still reads.
nonisolated struct ClipboardBackupManifest: Codable, Sendable {
    /// Read before anything else, so a file from a later version is called that and not "malformed".
    struct Header: Decodable {
        let format: String?
        let version: Int?
    }

    struct Item: Codable, Sendable {
        var id: UUID
        /// text, richText, link, color, image or files.
        var kind: String
        var copiedAt: Date
        var sourceBundleID: String?
        var sourceAppName: String?
        /// The language of a text that is code, or "text" when it is not; left out for other kinds.
        var code: CodeDetection?
        /// true for a secret, false for what is known not to be, left out when it was not known.
        var sensitive: Bool?
        var link: String?
        var color: String?
        var colorOriginal: String?
        var files: [FileReference]?
    }

    struct FileReference: Codable, Sendable {
        var path: String
        /// A bookmark of the file when it existed, which finds it again after it moved.
        var bookmark: Data?
    }

    struct Board: Codable, Sendable {
        var name: String
        var icon: String?
        var color: String?
        var items: [UUID]

        private enum CodingKeys: String, CodingKey {
            case name, icon, color, items
        }

        init(name: String, icon: String?, color: String?, items: [UUID]) {
            self.name = name
            self.icon = icon
            self.color = color
            self.items = items
        }

        /// The look is not worth refusing a file for: an odd icon or colour reads as nothing.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            items = try container.decode([UUID].self, forKey: .items)
            icon = (try? container.decodeIfPresent(String.self, forKey: .icon)) ?? nil
            color = (try? container.decodeIfPresent(String.self, forKey: .color)) ?? nil
        }
    }

    var format: String
    var version: Int
    var createdAt: Date?
    var scope: String?
    var includesSensitive: Bool?
    /// A board with a lock, as its sealed vault file in `vaults/<id>.vault`. Left out when there are none, so a file without them is
    /// the file an earlier version wrote, and an earlier version reading one with them ignores the key.
    struct LockedBoard: Codable, Sendable {
        var id: UUID
        var name: String
        var icon: String?
        var color: String?
        /// As the vault file says; shown while it is locked.
        var itemCount: Int
    }

    var items: [Item]
    var boards: [Board]
    var lockedBoards: [LockedBoard]?
}
