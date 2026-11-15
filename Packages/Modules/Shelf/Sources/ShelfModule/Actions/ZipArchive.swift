import Foundation

/// A point of `ZipArchive.make` a caller can watch, and cancel at.
nonisolated enum ZipStep: Equatable, Sendable {
    /// This many files have been copied into the staging folder.
    case staged(Int)
    /// The system has made the zip; it is not delivered yet.
    case zipped
    /// The zip has been copied next to its source.
    case placed
}

/// Zips with the system's own archiver (`NSFileCoordinator` with `.forUploading`), so nothing is shelled out.
///
/// That archiver cannot be interrupted (a cancel during it is only seen once it returns: zipping 480 MB of
/// incompressible files took half a minute and `NSFileCoordinator.cancel()` did not shorten it) and it fails on any
/// folder that holds a symbolic link. So cancelling is checked before each file is staged and again before the
/// zip is delivered, and links are taken out of what is zipped and added to the finished archive by `ZipLinks`.
nonisolated enum ZipArchive {
    struct Made {
        let file: URL
        /// Links that could not be stored in the archive (it is too big to extend); the rest is in it.
        let unstoredLinks: [URL]
    }

    /// One zip of `sources`, next to the first, named after the source when there is one and "Lưu trữ" when there are
    /// several. Whatever the sources, the zip holds one top-level folder named like the zip. The sources are never
    /// changed and no link is followed. Throws `CancellationError`, with nothing written, when the task is cancelled.
    /// `stagingRoot` is where files are copied to before they are zipped; the copy is removed on every way out.
    static func make(
        from sources: [URL], folders: OutputFolders, stagingRoot: URL = FileManager.default.temporaryDirectory,
        observe: (ZipStep) -> Void = { _ in },
        storeLinks: ([ZipLink], URL) throws -> Void = { try ZipLinks.append($0, to: $1) }
    ) throws -> Made {
        guard let first = sources.first else { throw FileActionError.zipFailed }
        guard sources.allSatisfy(exists) else { throw FileActionError.missing }
        let manager = FileManager.default
        let isFolder = sources.count == 1 && kind(of: first) == .folder
        let name = sources.count == 1 ? (isFolder ? first.lastPathComponent : first.deletingPathExtension().lastPathComponent) : "Lưu trữ"

        let staging = stagingRoot.appending(path: "MyNotch-zip-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? manager.removeItem(at: staging) }

        // A lone folder without links is zipped where it is. Anything else is copied (links left out and noted) into a
        // folder named like the zip, because the system zips folders and nothing else.
        var links: [ZipLink] = []
        let root: URL
        if isFolder, try !containsLink(first) {
            root = first
        } else {
            root = staging.appending(path: name, directoryHint: .isDirectory)
            do { try manager.createDirectory(at: root, withIntermediateDirectories: true) } catch { throw FileActionError.zipFailed }
            var count = 0
            func copied() {
                count += 1
                observe(.staged(count))
            }
            if isFolder {
                try copy(first, to: root, relative: nil, archiveRoot: name, links: &links, copied: copied)
            } else {
                var used: Set<String> = []
                for source in sources {
                    let target = unique(source.lastPathComponent, among: &used)
                    try copy(source, to: root.appending(path: target), relative: target, archiveRoot: name, links: &links, copied: copied)
                }
            }
        }
        try Task.checkCancellation()

        var coordinationError: NSError?
        var outcome: Result<Made, any Error> = .failure(FileActionError.zipFailed)
        NSFileCoordinator().coordinate(readingItemAt: root, options: .forUploading, error: &coordinationError) { zipped in
            outcome = Result {
                observe(.zipped)
                try Task.checkCancellation()
                var archive = zipped
                var unstored: [URL] = []
                if !links.isEmpty {
                    // The system's zip is not ours to edit, so the links go into a copy.
                    let work = staging.appending(path: "\(name).zip")
                    do { try manager.copyItem(at: zipped, to: work) } catch { throw FileActionError.cannotWrite }
                    do {
                        try storeLinks(links, work)
                        archive = work
                    } catch ZipLinks.Failure.unsupported {
                        unstored = links.map(\.source)
                    }
                }
                try Task.checkCancellation()
                let file = try OutputNaming.place(stem: name, suffix: nil, ext: "zip", in: folders.folder(for: first)) {
                    try manager.copyItem(at: archive, to: $0)
                }
                observe(.placed)
                // A cancel that came during the copy: the zip is taken back, so the report says what happened.
                if Task.isCancelled {
                    try? manager.removeItem(at: file)
                    throw CancellationError()
                }
                return Made(file: file, unstoredLinks: unstored)
            }
        }
        if coordinationError != nil { throw FileActionError.zipFailed }
        return try outcome.get()
    }

    /// Whether something is there, links included: a link whose target is gone is still a thing to zip.
    static func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    private enum Kind { case file, folder, link, other }

    private static func kind(of url: URL) -> Kind {
        switch (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType {
        case .typeSymbolicLink: .link
        case .typeDirectory: .folder
        case .typeRegular: .file
        default: .other
        }
    }

    private static func containsLink(_ folder: URL) throws -> Bool {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { throw FileActionError.zipFailed }
        for case let url as URL in walker {
            try Task.checkCancellation()
            if kind(of: url) == .link { return true }
        }
        return false
    }

    /// Copies `source` to `target`, checking for a cancel before each file. A link is not copied: it is noted in
    /// `links`, with the place it will have in the archive (`relative` is its path under the archive's folder).
    private static func copy(
        _ source: URL, to target: URL, relative: String?, archiveRoot: String, links: inout [ZipLink], copied: () -> Void
    ) throws {
        try Task.checkCancellation()
        let manager = FileManager.default
        do {
            switch kind(of: source) {
            case .link:
                guard let relative else { return }
                links.append(ZipLink(path: "\(archiveRoot)/\(relative)", target: try manager.destinationOfSymbolicLink(atPath: source.path), source: source))
            case .folder:
                try manager.createDirectory(at: target, withIntermediateDirectories: true)
                for child in try manager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                    try copy(
                        child, to: target.appending(path: child.lastPathComponent), relative: [relative, child.lastPathComponent].compactMap { $0 }.joined(separator: "/"),
                        archiveRoot: archiveRoot, links: &links, copied: copied
                    )
                }
                // The folder keeps the mode it was made with and not the source's: the system's zip stores no folder
                // entries, so the source's mode would not reach the archive, and a read-only copy could not be removed.
            case .file:
                try manager.copyItem(at: source, to: target)
                copied()
            case .other:
                // A socket or a device has no content to zip.
                break
            }
        } catch let error as CancellationError {
            throw error
        } catch let error as FileActionError {
            throw error
        } catch {
            throw FileActionError.zipFailed
        }
    }

    /// `name`, or `name 2`… when another source in the folder already took it.
    private static func unique(_ name: String, among used: inout Set<String>) -> String {
        let ext = (name as NSString).pathExtension, stem = (name as NSString).deletingPathExtension
        var candidate = name, number = 1
        while !used.insert(candidate.precomposedStringWithCanonicalMapping.lowercased()).inserted {
            number += 1
            candidate = ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)"
        }
        return candidate
    }
}
