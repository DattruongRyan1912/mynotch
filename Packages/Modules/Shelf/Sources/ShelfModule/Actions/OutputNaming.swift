import Foundation

/// File names for results, and writing them without ever replacing a file that is already there.
nonisolated enum OutputNaming {
    /// `ảnh` with suffix `1280` and extension `jpg` is `ảnh-1280.jpg`. Precomposed, so a name that came in
    /// decomposed (as some drop sources and old volumes give them) does not end up half of each.
    static func fileName(stem: String, suffix: String?, ext: String) -> String {
        let name = suffix.map { "\(stem)-\($0)" } ?? stem
        return "\(name).\(ext)".precomposedStringWithCanonicalMapping
    }

    /// Calls `write` with `folder/name`, then `name 2`, `name 3`… for as long as the name is taken, and returns the
    /// URL that was written. `write` must fail rather than replace (`.withoutOverwriting`, `copyItem`), so a file
    /// that shows up between the check and the write is also left alone. A write that fails halfway leaves nothing.
    static func place(stem: String, suffix: String?, ext: String, in folder: URL, write: (URL) throws -> Void) throws -> URL {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw FileActionError.cannotWrite
        }
        let name = fileName(stem: stem, suffix: suffix, ext: ext)
        let base = (name as NSString).deletingPathExtension
        for number in 1...10_000 {
            let candidate = folder.appending(path: number == 1 ? name : "\(base) \(number).\(ext)")
            guard !manager.fileExists(atPath: candidate.path) else { continue }
            do {
                try write(candidate)
                return candidate
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            } catch {
                try? manager.removeItem(at: candidate)
                throw FileActionError.cannotWrite
            }
        }
        throw FileActionError.cannotWrite
    }
}

/// Where the results for a source go: next to it, except for the copies the shelf keeps of promised files.
nonisolated struct OutputFolders: Sendable {
    /// `ShelfStore.promisedDirectory`; nil when the shelf has none.
    var promisedDirectory: URL?

    /// A promised copy lives in a folder that is deleted with its item, which would take a result with it, so a
    /// result for one gets a promised folder of its own (ask again for each result).
    func folder(for source: URL) -> URL {
        let parent = source.deletingLastPathComponent()
        guard let promisedDirectory,
              parent.deletingLastPathComponent().resolvingSymlinksInPath().path == promisedDirectory.resolvingSymlinksInPath().path
        else { return parent }
        return promisedDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }
}
