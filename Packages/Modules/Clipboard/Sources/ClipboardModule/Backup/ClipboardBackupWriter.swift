import Foundation

/// Writes the history as a `.mynotchclip` file. Runs off the main actor, takes one item at a time (so a large history is
/// never in memory whole), and writes next to the destination under a temporary name that becomes the destination only when
/// everything is written: a cancelled or failed export leaves nothing, and an older file stays as it was.
nonisolated enum ClipboardBackupWriter {
    /// Rough size of an item with no payload in the manifest, so progress moves for links and colours too.
    private static let itemWeight = 1024

    /// How many text items a backup of `scope` would hold that were saved before MyNotch tracked which copies apps mark as
    /// secrets (`sensitive` is neither true nor false), so there is no telling whether one is a password. Text only, since that
    /// is what a password is. Whatever the options say, these are in the file.
    static func legacyTextCount(in history: ClipboardHistory, scope: ClipboardBackupOptions.Scope) -> Int {
        let pinned = scope == .pinnedOnly ? Set(history.boards.flatMap(\.itemIDs)) : []
        return history.items.count { item in
            item.sensitive == nil && item.content.kind == .text && (scope == .allHistory || pinned.contains(item.id))
        }
    }

    /// `imageURLs` maps an image's file name to where its PNG is. `limits` are what the file must satisfy to be read back
    /// (the format's own, unless a test says otherwise); what would not fit is left out and counted. `progress` is called
    /// with 0 to 1, in order, from the background.
    @concurrent static func write(
        history: ClipboardHistory, options: ClipboardBackupOptions, imageURLs: [String: URL], to destination: URL,
        now: Date = .now, limits: ZipLimits = ClipboardBackupFormat.limits, progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> ClipboardBackupExportSummary {
        let folder = destination.deletingLastPathComponent()
        let temporary = folder.appending(path: ".\(destination.lastPathComponent).partial-\(UUID().uuidString)")
        do {
            let summary = try build(
                history: history, options: options, imageURLs: imageURLs, to: temporary, now: now, limits: limits, progress: progress
            )
            try publish(temporary, as: destination)
            progress(1)
            return summary
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw Self.backupError(error)
        }
    }

    private static func backupError(_ error: any Error) -> any Error {
        switch error {
        case is CancellationError, is ClipboardBackupError: error
        case let zip as ZipError: ClipboardBackupError(zip)
        default: ClipboardBackupError.cannotWrite(error.localizedDescription)
        }
    }

    /// The temporary file replaces the destination in one step.
    private static func publish(_ temporary: URL, as destination: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            // The new file's mode, not the old file's: an older backup somebody else could read must not make this one readable.
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary, options: .usingNewMetadataOnly)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
    }

    // MARK: Building

    private static func build(
        history: ClipboardHistory, options: ClipboardBackupOptions, imageURLs: [String: URL], to url: URL, now: Date, limits: ZipLimits,
        progress: @Sendable (Double) -> Void
    ) throws -> ClipboardBackupExportSummary {
        var summary = ClipboardBackupExportSummary()
        let pinned = Set(history.boards.flatMap(\.itemIDs))
        var candidates = history.items.filter { options.scope == .allHistory || pinned.contains($0.id) }
        if options.skipSensitive {
            let all = candidates.count
            candidates.removeAll(where: \.isSensitive)
            summary.skippedSensitive = all - candidates.count
        }
        let entries = candidates.map { ($0, manifestEntry(for: $0)) }
        let candidateIDs = Set(candidates.map(\.id))
        let boards = history.boards.map { board in
            (board, ClipboardBackupManifest.Board(
                name: Self.clamped(board.name), icon: board.systemImage, color: board.color == .accent ? nil : board.color.rawValue,
                items: board.itemIDs.filter(candidateIDs.contains)
            ))
        }

        // The manifest counts toward the total a reader accepts. Describing every candidate is the most it can grow to, so the
        // payloads get what is left of the total and the finished file can never be over it.
        let widest = try encodeManifest(
            entries.map(\.1), boards: boards.map(\.1), options: options, now: now
        )
        guard widest.count <= ClipboardBackupFormat.maxItemBytes, widest.count <= limits.total else { throw ClipboardBackupError.tooLarge }
        var spaceLeft = limits.total - widest.count

        let totalWeight = max(candidates.reduce(0) { $0 + estimatedBytes(of: $1) + itemWeight }, 1)
        var doneWeight = 0
        var lastReported = -1.0
        func report(force: Bool = false) {
            let fraction = min(Double(doneWeight) / Double(totalWeight), 1)
            if force || fraction - lastReported >= 0.01 {
                lastReported = fraction
                progress(fraction)
            }
        }
        report(force: true)

        let archive = try ZipWriter(url: url)
        var included: [ClipboardBackupManifest.Item] = []
        var includedIDs = Set<UUID>()
        for (item, entry) in entries {
            try Task.checkCancellation()
            switch try writePayloads(of: item, to: archive, imageURLs: imageURLs, limits: limits, spaceLeft: spaceLeft) {
            case .written(let bytes):
                included.append(entry)
                includedIDs.insert(item.id)
                spaceLeft -= bytes
                if item.content.kind == .file { summary.fileItemCount += 1 }
            case .tooLarge: summary.skippedTooLarge += 1
            case .unreadable: summary.skippedUnreadable += 1
            }
            doneWeight += estimatedBytes(of: item) + itemWeight
            report()
        }
        summary.itemCount = included.count
        summary.boardCount = boards.count

        let finished = boards.map { _, board in
            ClipboardBackupManifest.Board(name: board.name, icon: board.icon, color: board.color, items: board.items.filter(includedIDs.contains))
        }
        try archive.add(
            name: ClipboardBackupFormat.manifestName, data: try encodeManifest(included, boards: finished, options: options, now: now)
        )
        try archive.finish()
        return summary
    }

    private static func encodeManifest(
        _ items: [ClipboardBackupManifest.Item], boards: [ClipboardBackupManifest.Board], options: ClipboardBackupOptions, now: Date
    ) throws -> Data {
        try ClipboardBackupFormat.makeEncoder().encode(ClipboardBackupManifest(
            format: ClipboardBackupFormat.formatName, version: ClipboardBackupFormat.currentVersion, createdAt: now,
            scope: options.scope.rawValue, includesSensitive: !options.skipSensitive, items: items, boards: boards
        ))
    }

    /// What the manifest says of an item: everything but the payloads of text, rich text and images, which have entries of
    /// their own.
    private static func manifestEntry(for item: ClipboardItem) -> ClipboardBackupManifest.Item {
        var entry = ClipboardBackupManifest.Item(
            id: item.id, kind: "", copiedAt: item.copiedAt, sourceBundleID: item.sourceBundleID.map(Self.clamped),
            sourceAppName: item.sourceAppName.map(Self.clamped),
            code: item.codeDetection, sensitive: item.sensitive
        )
        switch item.content {
        case .text: entry.kind = "text"
        case .richText: entry.kind = "richText"
        case .image: entry.kind = "image"
        case .link(let url):
            entry.kind = "link"
            entry.link = url.absoluteString
        case .color(let hex, let original):
            entry.kind = "color"
            entry.color = hex
            entry.colorOriginal = original
        case .files(let urls):
            entry.kind = "files"
            entry.files = urls.map { url in
                ClipboardBackupManifest.FileReference(path: url.path(percentEncoded: false), bookmark: bookmark(of: url))
            }
        }
        return entry
    }

    private enum PayloadOutcome {
        case written(bytes: Int)
        case tooLarge
        case unreadable
    }

    /// Writes the payloads of one item, unless one is over the limit for an entry or the archive has no room left for them.
    private static func writePayloads(
        of item: ClipboardItem, to archive: ZipWriter, imageURLs: [String: URL], limits: ZipLimits, spaceLeft: Int
    ) throws -> PayloadOutcome {
        var payloads: [(name: String, data: Data, compress: Bool)] = []
        switch item.content {
        case .text(let text):
            payloads = [(ClipboardBackupFormat.payloadName(for: item.id, extension: "txt"), Data(text.utf8), true)]
        case .richText(let plain, let rtf):
            payloads = [
                (ClipboardBackupFormat.payloadName(for: item.id, extension: "txt"), Data(plain.utf8), true),
                (ClipboardBackupFormat.payloadName(for: item.id, extension: "rtf"), rtf, true),
            ]
        case .image(let image):
            guard let url = imageURLs[image.fileName], let size = fileSize(of: url) else { return .unreadable }
            guard size <= limits.perEntry, size <= spaceLeft else { return .tooLarge }
            guard let data = try? Data(contentsOf: url), data.count == size else { return .unreadable }
            // A PNG is compressed already; trying again costs time and saves nothing.
            payloads = [(ClipboardBackupFormat.payloadName(for: item.id, extension: "png"), data, false)]
        case .link, .color, .files:
            break
        }
        let total = payloads.reduce(0) { $0 + $1.data.count }
        guard payloads.allSatisfy({ $0.data.count <= limits.perEntry }), total <= spaceLeft else { return .tooLarge }
        for payload in payloads {
            try archive.add(name: payload.name, data: payload.data, compress: payload.compress)
        }
        return .written(bytes: total)
    }

    /// A name longer than a reader accepts (nothing in MyNotch stops one) is cut, so the file it is in can be read back.
    private static func clamped(_ name: String) -> String {
        String(name.prefix(ClipboardBackupFormat.maxNameLength))
    }

    private static func estimatedBytes(of item: ClipboardItem) -> Int {
        switch item.content {
        case .text(let text): text.utf8.count
        case .richText(let plain, let rtf): plain.utf8.count + rtf.count
        case .image(let image): image.byteCount
        case .link, .color, .files: 0
        }
    }

    private static func fileSize(of url: URL) -> Int? {
        try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }

    /// nil when the file is not there (the path alone is kept) or cannot be bookmarked.
    private static func bookmark(of url: URL) -> Data? {
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        return try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
}
