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

    /// New items in the file's order, with new ids.
    var items: [ClipboardItem]
    var boards: [Board]
    /// Readable items the history already had, or an earlier item of the file had.
    var duplicates: Int
    var unreadable: Int
}

/// Reads a `.mynotchclip` file. Runs off the main actor. The archive is checked whole before any of it is used (see `ZipReader`),
/// everything is rebuilt from the bytes in the file (a hash, a size and an image's file name come from the data, never from
/// what the manifest says), and one item that cannot be read is left out and counted without costing the others.
nonisolated enum ClipboardBackupReader {
    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    /// `knownHashes` are the hashes of the history now, so an item it has is not added (nor is its image written).
    /// `imagesDirectory` is where the store keeps images. `now` holds back a date from the future.
    @concurrent static func plan(
        archiveAt url: URL, knownHashes: Set<String>, imagesDirectory: URL, now: Date = .now,
        limits: ZipLimits = ClipboardBackupFormat.limits, progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> ClipboardRestorePlan {
        do {
            return try read(url, knownHashes: knownHashes, imagesDirectory: imagesDirectory, now: now, limits: limits, progress: progress)
        } catch let error as ZipError {
            throw ClipboardBackupError(error)
        } catch let error as CancellationError {
            throw error
        } catch let error as ClipboardBackupError {
            throw error
        } catch {
            throw ClipboardBackupError.cannotRead(error.localizedDescription)
        }
    }

    private static func read(
        _ url: URL, knownHashes: Set<String>, imagesDirectory: URL, now: Date, limits: ZipLimits, progress: @Sendable (Double) -> Void
    ) throws -> ClipboardRestorePlan {
        let archive = try ZipReader(url: url, limits: limits)
        guard let manifestEntry = archive.entry(named: ClipboardBackupFormat.manifestName) else { throw ClipboardBackupError.notABackup }
        let manifestData = try archive.data(of: manifestEntry)
        let decoder = ClipboardBackupFormat.makeDecoder()
        let manifest = try manifest(from: manifestData, decoder: decoder)

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
            if let image = built.image {
                try ClipboardStore.writeImage(image.data, named: image.fileName, in: imagesDirectory)
            }
            plan.items.append(ClipboardItem(
                id: UUID(), content: built.content, contentHash: hash, copiedAt: min(entry.copiedAt, now),
                sourceBundleID: entry.sourceBundleID, sourceAppName: entry.sourceAppName, codeDetection: built.code,
                sensitive: entry.sensitive == true ? true : nil
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
        report(force: true)
        progress(1)
        return plan
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
        /// The PNG to store under its name, for an image.
        var image: (data: Data, fileName: String)?
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
            guard let text = entry.link, let url = URL(string: text), url.scheme?.isEmpty == false else { return nil }
            return BuiltItem(content: .link(url))
        case "color":
            guard let hex = entry.color.flatMap(Self.hex(from:)) else { return nil }
            let original = entry.colorOriginal.flatMap { $0.count <= 200 ? $0 : nil }
            return BuiltItem(content: .color(hex: hex, original: original))
        case "image":
            guard let data = try payload("png"), let size = Self.pngSize(of: data) else { return nil }
            let fileName = data.sha256Hex + ".png"
            let image = ClipboardImage(fileName: fileName, pixelWidth: size.width, pixelHeight: size.height, byteCount: data.count)
            return BuiltItem(content: .image(image), image: (data, fileName))
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
