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
    static let limits = ZipLimits(perEntry: maxItemBytes, total: maxTotalBytes)

    /// The entry holding one part of an item. Built from the item's id and a fixed extension, never from text in the file.
    static func payloadName(for id: UUID, extension fileExtension: String) -> String {
        "items/\(id.uuidString).\(fileExtension)"
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
    case itemTooLarge(String)
    case unsupported
    case damaged
    case cannotRead(String)
    case cannotWrite(String)

    var errorDescription: String? {
        switch self {
        case .moduleStopped: "Hãy bật module Clipboard rồi thử lại."
        case .notABackup: "Đây không phải tệp sao lưu của MyNotch."
        case .newerVersion(let version): "Tệp này do bản MyNotch mới hơn tạo (định dạng \(version)). Hãy cập nhật MyNotch rồi khôi phục."
        case .malformed: "Tệp sao lưu bị hỏng: không đọc được danh sách mục."
        case .unsafeEntry: "Tệp có mục không an toàn nên không được dùng."
        case .tooLarge: "Tệp quá lớn: tối đa 2 GB."
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

    var text: String {
        var text = "Đã sao lưu \(itemCount) mục và \(boardCount) board"
        let skipped = [
            skippedSensitive > 0 ? "bỏ qua \(skippedSensitive) mục nhạy cảm" : nil,
            skippedTooLarge > 0 ? "\(skippedTooLarge) mục quá lớn" : nil,
            skippedUnreadable > 0 ? "\(skippedUnreadable) mục không đọc được" : nil,
        ].compactMap { $0 }
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
    /// Added, then removed at once by the history limits in Settings.
    var prunedByLimits = 0

    var text: String {
        var parts = ["Đã thêm \(added) mục"]
        if duplicates > 0 { parts.append("bỏ qua \(duplicates) trùng lặp") }
        if unreadable > 0 { parts.append("\(unreadable) mục không đọc được") }
        if boardsCreated > 0 { parts.append("tạo \(boardsCreated) board mới") }
        var text = parts.joined(separator: ", ")
        if prunedByLimits > 0 {
            text += ". \(prunedByLimits) mục vượt giới hạn hoặc thời gian giữ trong Cài đặt nên đã bị dọn"
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
    var items: [Item]
    var boards: [Board]
}
