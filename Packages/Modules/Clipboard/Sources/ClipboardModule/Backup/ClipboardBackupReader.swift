import CryptoKit
import Foundation
import ImageIO

/// What a backup file turned out to hold, ready to merge: the items that are new (their images already stored), the boards by
/// name, and what was left out.
nonisolated struct ClipboardRestorePlan: Sendable {
    struct Board: Sendable, Equatable {
        var name: String
        var systemImage: String
        var color: ClipboardBoardColor
        /// The content hashes of its items, in the file's order, for every readable item of the file, new or not.
        var itemHashes: [String]
    }

    /// A board that has a lock, which comes back sealed as the file holds it: the vault file is stored on restore, nothing of it is read.
    struct LockedBoard: Sendable, Equatable {
        var id: UUID
        var name: String
        var systemImage: String
        var color: ClipboardBoardColor
        var itemCount: Int
    }

    /// New items in the file's order, with new ids.
    var items: [ClipboardItem]
    var boards: [Board]
    /// Locked boards whose vault file is in the archive and is one (of that board, opened by a password).
    var lockedBoards: [LockedBoard] = []
    /// Readable items the history already had, or an earlier item of the file had.
    var duplicates: Int
    var unreadable: Int
    /// For each new image item, the entry of the archive that holds its PNG, by the file name it will be stored under. The
    /// images are not stored while the plan is made (see `ClipboardBackupReader.writeImages`).
    var imageEntries: [String: String] = [:]
}

/// What storing the vault files of a plan did.
nonisolated struct ClipboardVaultWrite: Sendable {
    /// The files this step made, which are the ones to remove again if the restore is not completed.
    var created: [URL] = []
    /// Boards whose file could not be stored: the archive no longer holds what the plan saw, or a vault file is there already.
    var failed: Set<UUID> = []
}

/// What storing the images of a plan did.
nonisolated struct ClipboardImageWrite: Sendable {
    /// The files this step made, which are the ones to remove again if the restore is not completed.
    var created: [URL] = []
    /// File names of images that could not be stored: the archive no longer holds what the plan saw.
    var failed: Set<String> = []
}

/// Reads a `.mynotchclip` file in two steps, both off the main actor. `plan` reads it whole and writes nothing, so the user can
/// be told what a restore would do before it does anything; `writeImages` stores the images of what the user chose to add.
/// The archive is checked whole before any of it is used (see `ZipReader`), everything is rebuilt from the bytes in the file (a
/// hash, a size and an image's file name come from the data, never from what the manifest says), and one item that cannot be
/// read is left out and counted without costing the others.
nonisolated enum ClipboardBackupReader {
    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    /// `knownHashes` are the hashes of the history now, so an item it has is not added. `now` holds back a date from the future.
    /// Throws before anything is read of the items when the manifest lists more than the format allows.
    @concurrent static func plan(
        archiveAt url: URL, knownHashes: Set<String>, now: Date = .now, limits: ZipLimits = ClipboardBackupFormat.limits,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> ClipboardRestorePlan {
        do {
            return try read(url, knownHashes: knownHashes, now: now, limits: limits, progress: progress)
        } catch {
            throw backupError(error, reading: true)
        }
    }

    /// Stores the PNG of each new image item of `plan` in `imagesDirectory`, read again from the archive and checked against the
    /// hash it was planned under (an image the archive no longer holds as it was is reported in `failed`, not written). An
    /// image that is stored already is left as it is. When the step ends in an error or is cancelled, the files it made are
    /// removed again, so a restore that does not happen leaves no image behind.
    @concurrent static func writeImages(
        of plan: ClipboardRestorePlan, from url: URL, to imagesDirectory: URL, limits: ZipLimits = ClipboardBackupFormat.limits,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> ClipboardImageWrite {
        var written = ClipboardImageWrite()
        do {
            let archive = try ZipReader(url: url, limits: limits)
            let entries = plan.imageEntries.sorted { $0.key < $1.key }
            let totalBytes = max(entries.reduce(0) { $0 + (archive.entry(named: $1.value)?.size ?? 0) }, 1)
            var doneBytes = 0
            progress(0)
            for (fileName, entryName) in entries {
                try Task.checkCancellation()
                defer {
                    doneBytes += archive.entry(named: entryName)?.size ?? 0
                    progress(min(Double(doneBytes) / Double(totalBytes), 1))
                }
                let data: Data?
                do {
                    data = try archive.data(named: entryName)
                } catch is ZipError {
                    data = nil
                }
                guard let data, data.sha256Hex + ".png" == fileName else {
                    written.failed.insert(fileName)
                    continue
                }
                let target = imagesDirectory.appending(path: fileName, directoryHint: .notDirectory)
                let existed = FileManager.default.fileExists(atPath: target.path(percentEncoded: false))
                try ClipboardStore.writeImage(data, named: fileName, in: imagesDirectory)
                if !existed { written.created.append(target) }
            }
            return written
        } catch {
            for file in written.created { try? FileManager.default.removeItem(at: file) }
            throw backupError(error, reading: false)
        }
    }

    /// Stores the vault file of each locked board of `plan` that is in `boardIDs`, read again from the archive and checked once more
    /// (a vault of that board, opened by a password). A file already there is never replaced. When the step ends in an error or is
    /// cancelled the files it made are removed again.
    @concurrent static func writeVaults(
        of plan: ClipboardRestorePlan, boardIDs: Set<UUID>, from url: URL, to files: ClipboardVaultFiles,
        limits: ZipLimits = ClipboardBackupFormat.limits
    ) async throws -> ClipboardVaultWrite {
        var written = ClipboardVaultWrite()
        do {
            let boards = plan.lockedBoards.filter { boardIDs.contains($0.id) }
            guard !boards.isEmpty else { return written }
            let archive = try ZipReader(url: url, limits: limits)
            try files.prepare()
            for board in boards {
                try Task.checkCancellation()
                let data: Data?
                do {
                    data = try archive.data(named: ClipboardBackupFormat.vaultName(for: board.id))
                } catch is ZipError {
                    data = nil
                }
                guard let data, let file = try? ClipboardVaultFile.decode(data), file.envelope.boardID == board.id,
                      file.envelope.method == .password, !files.exists(for: board.id) else {
                    written.failed.insert(board.id)
                    continue
                }
                try file.write(to: files.url(for: board.id))
                written.created.append(files.url(for: board.id))
            }
            return written
        } catch {
            for file in written.created { try? FileManager.default.removeItem(at: file) }
            throw backupError(error, reading: false)
        }
    }

    private static func backupError(_ error: any Error, reading: Bool) -> any Error {
        switch error {
        case is CancellationError, is ClipboardBackupError: error
        case let zip as ZipError: ClipboardBackupError(zip)
        default: reading ? ClipboardBackupError.cannotRead(error.localizedDescription) : ClipboardBackupError.cannotWrite(error.localizedDescription)
        }
    }

    private static func read(
        _ url: URL, knownHashes: Set<String>, now: Date, limits: ZipLimits, progress: @Sendable (Double) -> Void
    ) throws -> ClipboardRestorePlan {
        let archive = try ZipReader(url: url, limits: limits)
        guard let manifestEntry = archive.entry(named: ClipboardBackupFormat.manifestName) else { throw ClipboardBackupError.notABackup }
        let manifestData = try archive.data(of: manifestEntry)
        let decoder = ClipboardBackupFormat.makeDecoder()
        let manifest = try manifest(from: manifestData, decoder: decoder)
        try checkCaps(of: manifest)

        let totalBytes = max(archive.entries.reduce(0) { $0 + $1.size }, 1)
        var doneBytes = manifestEntry.size
        var lastReported = -1.0
        func report(force: Bool = false) {
            let fraction = min(Double(doneBytes) / Double(totalBytes), 1)
            if force || fraction - lastReported >= 0.01 {
                lastReported = fraction
                progress(fraction)
            }
        }
        report(force: true)

        var plan = ClipboardRestorePlan(items: [], boards: [], duplicates: 0, unreadable: 0)
        var seen = knownHashes
        var hashByID: [UUID: String] = [:]
        for entry in manifest.items {
            try Task.checkCancellation()
            defer {
                doneBytes += payloadSize(of: entry.id, in: archive)
                report()
            }
            guard let built = try build(entry, from: archive, now: now) else {
                plan.unreadable += 1
                continue
            }
            let hash = ClipboardContent.hash(of: built.content)
            hashByID[entry.id] = hash
            guard seen.insert(hash).inserted else {
                plan.duplicates += 1
                continue
            }
            if let fileName = built.imageFileName {
                plan.imageEntries[fileName] = ClipboardBackupFormat.payloadName(for: entry.id, extension: "png")
            }
            plan.items.append(ClipboardItem(
                id: UUID(), content: built.content, contentHash: hash, copiedAt: min(entry.copiedAt, now),
                sourceBundleID: entry.sourceBundleID, sourceAppName: entry.sourceAppName, codeDetection: built.code,
                // As the file says: a secret, not one, or not known.
                sensitive: entry.sensitive
            ))
        }
        plan.boards = manifest.boards.compactMap { board in
            let name = board.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return ClipboardRestorePlan.Board(
                name: name,
                systemImage: board.icon.flatMap { ClipboardBoardIcon.isValidName($0) ? $0 : nil } ?? ClipboardBoardIcon.defaultName,
                color: board.color.flatMap { ClipboardBoardColor(rawValue: $0) } ?? .accent,
                itemHashes: board.items.compactMap { hashByID[$0] }
            )
        }
        let locked = try lockedBoards(of: manifest, in: archive)
        plan.lockedBoards = locked.boards
        plan.unreadable += locked.unreadable
        report(force: true)
        progress(1)
        return plan
    }

    /// The locked boards of the manifest whose vault file is in the archive and is a vault of that board with a password to open it.
    /// A board is left out and counted when its name is blank, its id was listed before, its file is missing, is not a vault, belongs to
    /// another board, or opens with Touch ID (whose key is not in the file).
    private static func lockedBoards(of manifest: ClipboardBackupManifest, in archive: ZipReader) throws -> (boards: [ClipboardRestorePlan.LockedBoard], unreadable: Int) {
        var boards: [ClipboardRestorePlan.LockedBoard] = []
        var unreadable = 0
        var seen = Set<UUID>()
        for entry in manifest.lockedBoards ?? [] {
            try Task.checkCancellation()
            let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(entry.id).inserted else {
                unreadable += 1
                continue
            }
            let data: Data?
            do {
                data = try archive.data(named: ClipboardBackupFormat.vaultName(for: entry.id))
            } catch is ZipError {
                data = nil
            }
            guard let data, let file = try? ClipboardVaultFile.decode(data), file.envelope.boardID == entry.id,
                  file.envelope.method == .password else {
                unreadable += 1
                continue
            }
            boards.append(ClipboardRestorePlan.LockedBoard(
                id: entry.id, name: name,
                systemImage: entry.icon.flatMap { ClipboardBoardIcon.isValidName($0) ? $0 : nil } ?? ClipboardBoardIcon.defaultName,
                color: entry.color.flatMap { ClipboardBoardColor(rawValue: $0) } ?? .accent, itemCount: file.envelope.itemCount
            ))
        }
        return (boards, unreadable)
    }

    /// The version is looked at before the rest, so a file from a later MyNotch says so even when its shape changed.
    private static func manifest(from data: Data, decoder: JSONDecoder) throws -> ClipboardBackupManifest {
        guard let header = try? decoder.decode(ClipboardBackupManifest.Header.self, from: data) else { throw ClipboardBackupError.malformed }
        guard header.format == ClipboardBackupFormat.formatName else { throw ClipboardBackupError.notABackup }
        guard let version = header.version, version >= 1 else { throw ClipboardBackupError.malformed }
        guard version <= ClipboardBackupFormat.currentVersion else { throw ClipboardBackupError.newerVersion(version) }
        guard let manifest = try? decoder.decode(ClipboardBackupManifest.self, from: data) else { throw ClipboardBackupError.malformed }
        return manifest
    }

    // MARK: One item

    private struct BuiltItem {
        var content: ClipboardContent
        var code: CodeDetection?
        /// The name the PNG will be stored under, for an image.
        var imageFileName: String?
    }

    /// Refuses a manifest that lists more than the format allows, before any of it is used.
    private static func checkCaps(of manifest: ClipboardBackupManifest) throws {
        guard manifest.items.count <= ClipboardBackupFormat.maxItems else { throw ClipboardBackupError.tooManyItems }
        guard manifest.boards.count + (manifest.lockedBoards?.count ?? 0) <= ClipboardBackupFormat.maxBoards else {
            throw ClipboardBackupError.tooManyBoards
        }
        var pins = 0
        for board in manifest.boards {
            guard board.items.count <= ClipboardBackupFormat.maxPinsPerBoard else { throw ClipboardBackupError.tooManyPins }
            pins += board.items.count
        }
        guard pins <= ClipboardBackupFormat.maxPinsTotal else { throw ClipboardBackupError.tooManyPins }
        let limit = ClipboardBackupFormat.maxNameLength
        guard manifest.boards.allSatisfy({ $0.name.count <= limit }), (manifest.lockedBoards ?? []).allSatisfy({ $0.name.count <= limit }),
              manifest.items.allSatisfy({ ($0.sourceAppName?.count ?? 0) <= limit && ($0.sourceBundleID?.count ?? 0) <= limit })
        else { throw ClipboardBackupError.tooLongText }
    }

    /// nil when the item cannot be read: no payload, a payload that is damaged or not what its kind needs, or a kind this
    /// version does not know. Throws only for something wrong with the file as a whole (it cannot be read at all).
    private static func build(_ entry: ClipboardBackupManifest.Item, from archive: ZipReader, now: Date) throws -> BuiltItem? {
        func payload(_ fileExtension: String) throws -> Data? {
            do {
                return try archive.data(named: ClipboardBackupFormat.payloadName(for: entry.id, extension: fileExtension))
            } catch is ZipError {
                return nil
            }
        }
        switch entry.kind {
        case "text":
            guard let text = try payload("txt").flatMap(Self.text(from:)) else { return nil }
            let content = ClipboardContent.text(text)
            return BuiltItem(content: content, code: entry.code ?? ClipboardCodeDetector.detect(content))
        case "richText":
            guard let plain = try payload("txt").flatMap(Self.text(from:)), let rtf = try payload("rtf"),
                  rtf.count <= ClipboardClassifier.maxTextBytes else { return nil }
            let content = ClipboardContent.richText(plain: plain, rtf: rtf)
            return BuiltItem(content: content, code: entry.code ?? ClipboardCodeDetector.detect(content))
        case "link":
            guard let text = entry.link, !text.allSatisfy(\.isWhitespace) else { return nil }
            // A link is only what a capture would take as one (web or mail); anything else the file calls a link is the text it is.
            if let url = ClipboardClassifier.link(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return BuiltItem(content: .link(url))
            }
            guard let plain = Self.text(from: Data(text.utf8)) else { return nil }
            let content = ClipboardContent.text(plain)
            return BuiltItem(content: content, code: ClipboardCodeDetector.detect(content))
        case "color":
            guard let hex = entry.color.flatMap(Self.hex(from:)) else { return nil }
            let original = entry.colorOriginal.flatMap { $0.count <= 200 ? $0 : nil }
            return BuiltItem(content: .color(hex: hex, original: original))
        case "image":
            guard let data = try payload("png"), let size = Self.pngSize(of: data) else { return nil }
            let fileName = data.sha256Hex + ".png"
            let image = ClipboardImage(fileName: fileName, pixelWidth: size.width, pixelHeight: size.height, byteCount: data.count)
            return BuiltItem(content: .image(image), imageFileName: fileName)
        case "files":
            guard let references = entry.files, !references.isEmpty else { return nil }
            var urls: [URL] = []
            for reference in references {
                guard reference.path.hasPrefix("/"), !reference.path.contains("\0") else { return nil }
                urls.append(Self.fileURL(for: reference))
            }
            return BuiltItem(content: .files(urls))
        default:
            return nil
        }
    }

    /// Text a capture would have kept: UTF-8, not blank, not over what a capture takes.
    private static func text(from data: Data) -> String? {
        guard data.count <= ClipboardClassifier.maxTextBytes, let text = String(data: data, encoding: .utf8),
              !text.allSatisfy(\.isWhitespace) else { return nil }
        return text
    }

    /// "#RRGGBB" or "#RRGGBBAA", upper case.
    private static func hex(from text: String) -> String? {
        text.wholeMatch(of: /#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?/) != nil ? text.uppercased() : nil
    }

    /// The size of a PNG from its header, which also tells it is one. The image itself is not decoded here; it is only ever
    /// drawn the way every stored image is, and one that does not draw shows as a blank card.
    private static func pngSize(of data: Data) -> (width: Int, height: Int)? {
        guard data.prefix(pngSignature.count) == pngSignature,
              let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetType(source) as String? == "public.png",
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        return (width, height)
    }

    /// The path the item was copied from when it is still there (so the item keeps the hash it had), otherwise where the
    /// bookmark finds the file, otherwise the path as it was.
    private static func fileURL(for reference: ClipboardBackupManifest.FileReference) -> URL {
        let original = URL(fileURLWithPath: reference.path)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: reference.path) { return original }
        if let data = reference.bookmark {
            var isStale = false
            if let resolved = try? URL(
                resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &isStale
            ), fileManager.fileExists(atPath: resolved.path(percentEncoded: false)) {
                return resolved
            }
        }
        return original
    }

    /// What the item's payloads weigh in the archive, for progress.
    private static func payloadSize(of id: UUID, in archive: ZipReader) -> Int {
        ["txt", "rtf", "png"].reduce(0) { total, fileExtension in
            total + (archive.entry(named: ClipboardBackupFormat.payloadName(for: id, extension: fileExtension))?.size ?? 0)
        }
    }
}
