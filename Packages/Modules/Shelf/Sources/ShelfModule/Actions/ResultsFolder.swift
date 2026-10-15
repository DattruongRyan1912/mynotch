import Foundation

/// A result that has no card on the shelf, and why. Its file is where `url` says.
nonisolated struct UnshelvedResult: Equatable, Sendable {
    enum Reason: Equatable, Sendable {
        /// The shelf had no free place; results never push other cards off.
        case shelfFull
        /// The card could not be made (the file's bookmark failed).
        case cardFailed
        /// The module stopped, or stopped and started again, while the action ran.
        case shelfStopped
        /// It is in the shelf's promised storage and could not be moved out: the next launch sweeps it.
        case stranded
    }

    let url: URL
    let reason: Reason
}

/// Where a result goes when it has no card and no folder of its own to be found in.
///
/// A result is written next to its source. For a file that was dragged in as a promise (Photos, Mail, Safari) that is
/// a folder of the shelf's promised storage, which is deleted once no card points at it, so a result without a card
/// would be lost at the next launch. Those are moved to a folder the user can open instead.
nonisolated enum ResultsFolder {
    /// `~/Downloads/MyNotch`. Made when the first result is moved there.
    static var standard: URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads", directoryHint: .isDirectory)
        return downloads.appending(path: "MyNotch", directoryHint: .isDirectory)
    }

    /// Moves every result that is in promised storage into `folder` (never replacing a file there) and removes the
    /// folder it was written in. The others are returned as they were; one that cannot be moved is marked `stranded`.
    static func rescue(_ results: [UnshelvedResult], folders: OutputFolders, into folder: URL) -> [UnshelvedResult] {
        let manager = FileManager.default
        return results.map { result in
            guard folders.holdsPromised(result.url) else { return result }
            do {
                let moved = try OutputNaming.place(
                    stem: result.url.deletingPathExtension().lastPathComponent, suffix: nil, ext: result.url.pathExtension, in: folder
                ) { try manager.moveItem(at: result.url, to: $0) }
                // Each result has a folder of its own, which is empty now.
                let own = result.url.deletingLastPathComponent()
                if (try? manager.contentsOfDirectory(atPath: own.path))?.isEmpty == true { try? manager.removeItem(at: own) }
                return UnshelvedResult(url: moved, reason: result.reason)
            } catch {
                return UnshelvedResult(url: result.url, reason: .stranded)
            }
        }
    }
}
