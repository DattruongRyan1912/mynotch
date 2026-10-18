import Foundation

/// A regular file found while measuring a folder.
nonisolated struct StorageFile: Sendable, Equatable {
    let url: URL
    let bytes: Int64
    let modified: Date
}

/// Measuring and emptying folders, off the main thread. Only regular files count, and a link is never followed: a link
/// inside a folder is removed itself and never what it points at, and a folder that is itself a link is left alone.
nonisolated public enum StorageFolder {
    /// Total size of the files under `folder`; 0 when it does not exist.
    @concurrent public static func bytes(in folder: URL) async -> Int64 {
        scan(folder).reduce(0) { $0 + $1.bytes }
    }

    /// Deletes everything inside `folder` and keeps the folder, which a running module may still write into without creating it
    /// again. Returns the bytes freed.
    @concurrent public static func removeContents(of folder: URL) async -> Int64 {
        empty(folder)
    }

    @concurrent static func files(in folder: URL) async -> [StorageFile] {
        scan(folder)
    }

    /// Deletes the given files, which `files(in:)` found, and returns the bytes of those it could delete.
    @concurrent static func remove(_ files: [StorageFile]) async -> Int64 {
        var freed: Int64 = 0
        for file in files where (try? FileManager.default.removeItem(at: plain(file.url))) != nil { freed += file.bytes }
        return freed
    }

    /// A trailing slash makes the system follow a link when it opens the path, so every path used here has none.
    private static func plain(_ url: URL) -> URL {
        var path = url.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return URL(filePath: path, directoryHint: .notDirectory)
    }

    private static func fileType(_ url: URL) -> FileAttributeType? {
        try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.type] as? FileAttributeType
    }

    /// A real folder, not a link to one.
    private static func isFolder(_ url: URL) -> Bool { fileType(url) == .typeDirectory }

    private static func scan(_ folder: URL) -> [StorageFile] {
        let folder = plain(folder)
        guard isFolder(folder) else { return [] }
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let walker = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }
        ) else { return [] }
        var files: [StorageFile] = []
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            // A date that cannot be read counts as new: the age rule never takes the file, the size rule takes it last.
            files.append(StorageFile(
                url: url, bytes: Int64(values.fileSize ?? 0), modified: values.contentModificationDate ?? .distantFuture
            ))
        }
        return files
    }

    private static func empty(_ folder: URL) -> Int64 {
        let folder = plain(folder)
        guard isFolder(folder),
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) else { return 0 }
        var freed: Int64 = 0
        for name in names {
            let item = folder.appending(path: name, directoryHint: .notDirectory)
            let size = size(of: item)
            if (try? FileManager.default.removeItem(at: item)) != nil { freed += size }
        }
        return freed
    }

    private static func size(of item: URL) -> Int64 {
        switch fileType(item) {
        case .typeRegular:
            let attributes = try? FileManager.default.attributesOfItem(atPath: item.path(percentEncoded: false))
            return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        case .typeDirectory:
            return scan(item).reduce(0) { $0 + $1.bytes }
        default:
            return 0
        }
    }
}
