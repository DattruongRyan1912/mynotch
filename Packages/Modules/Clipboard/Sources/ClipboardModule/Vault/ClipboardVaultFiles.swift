import Foundation

/// The folder of vault files, `vault/<board id>.vault` in the module's storage.
nonisolated struct ClipboardVaultFiles: Sendable {
    let directory: URL

    func url(for boardID: UUID) -> URL {
        directory.appending(path: "\(boardID.uuidString).\(ClipboardVaultFile.fileExtension)", directoryHint: .notDirectory)
    }

    func exists(for boardID: UUID) -> Bool {
        FileManager.default.fileExists(atPath: url(for: boardID).path(percentEncoded: false))
    }

    /// Makes the folder, closed to everyone but the user, whether it was there or not.
    func prepare() throws {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path(percentEncoded: false))
        } catch {
            throw ClipboardVaultError.cannotWrite(error.localizedDescription)
        }
    }

    /// What the vault files say of themselves, for the boards they belong to. A file whose header names another board than its own
    /// name does is not trusted, and one with no header is not listed.
    func summaries() -> [ClipboardVaultFile.Summary] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        return names.compactMap { name -> ClipboardVaultFile.Summary? in
            guard let match = name.wholeMatch(of: /([0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})\.vault/),
                  let boardID = UUID(uuidString: String(match.1)),
                  let summary = ClipboardVaultFile.summary(at: directory.appending(path: name)), summary.boardID == boardID else { return nil }
            return summary
        }
    }

    func remove(for boardID: UUID) throws {
        do {
            try FileManager.default.removeItem(at: url(for: boardID))
        } catch CocoaError.fileNoSuchFile {
            // Nothing to remove.
        } catch {
            throw ClipboardVaultError.cannotWrite(error.localizedDescription)
        }
    }

    /// Keeps a file that cannot be read as a vault out of the way of a new one, without destroying it.
    func moveAside(for boardID: UUID) {
        guard exists(for: boardID) else { return }
        let aside = directory.appending(path: "\(boardID.uuidString).vault.unreadable-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.moveItem(at: url(for: boardID), to: aside)
    }
}
