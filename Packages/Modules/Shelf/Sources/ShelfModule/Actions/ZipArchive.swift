import Foundation

/// Zips with the system's own archiver (`NSFileCoordinator` with `.forUploading`), so nothing is shelled out.
nonisolated enum ZipArchive {
    /// One zip of `sources`, next to the first, named after the source when there is one and "Lưu trữ" when there are
    /// several. Whatever the sources, the zip holds one top-level folder named like the zip. The sources are never
    /// changed. Throws `CancellationError` before any file is written when the task was cancelled.
    static func make(from sources: [URL], folders: OutputFolders) throws -> URL {
        guard let first = sources.first else { throw FileActionError.zipFailed }
        let manager = FileManager.default
        guard sources.allSatisfy({ manager.fileExists(atPath: $0.path) }) else { throw FileActionError.missing }
        let isFolder = sources.count == 1 && (try? first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let name = sources.count == 1 ? (isFolder ? first.lastPathComponent : first.deletingPathExtension().lastPathComponent) : "Lưu trữ"

        // A lone folder is zipped where it is. A file has no folder to zip, so it goes into one, and so do several.
        let staging = manager.temporaryDirectory.appending(path: "MyNotch-zip-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? manager.removeItem(at: staging) }
        let root: URL
        if isFolder {
            root = first
        } else {
            root = staging.appending(path: name, directoryHint: .isDirectory)
            try stage(sources, into: root)
        }
        try Task.checkCancellation()

        var coordinationError: NSError?
        var outcome: Result<URL, any Error> = .failure(FileActionError.zipFailed)
        NSFileCoordinator().coordinate(readingItemAt: root, options: .forUploading, error: &coordinationError) { zipped in
            outcome = Result {
                try OutputNaming.place(stem: name, suffix: nil, ext: "zip", in: folders.folder(for: first)) { try manager.copyItem(at: zipped, to: $0) }
            }
        }
        if coordinationError != nil { throw FileActionError.zipFailed }
        return try outcome.get()
    }

    /// Copies each source into `root` under its name, or `name 2`… when two sources share one.
    private static func stage(_ sources: [URL], into root: URL) throws {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            for source in sources {
                try Task.checkCancellation()
                let ext = source.pathExtension
                let stem = source.deletingPathExtension().lastPathComponent
                var number = 1
                var target = root.appending(path: source.lastPathComponent)
                while manager.fileExists(atPath: target.path) {
                    number += 1
                    target = root.appending(path: ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)")
                }
                try manager.copyItem(at: source, to: target)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw FileActionError.zipFailed
        }
    }
}
