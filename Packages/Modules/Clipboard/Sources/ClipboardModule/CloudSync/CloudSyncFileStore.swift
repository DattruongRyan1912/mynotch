import Foundation

public struct CloudSyncFileStore: Sendable {
    public let baseDirectory: URL

    public init(baseDirectory: URL? = nil) {
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.baseDirectory = downloads.appendingPathComponent("MyNotch Sync", isDirectory: true)
        }
    }

    /// Checks whether an existing filesystem item at [url] is a symbolic link.
    public static func isSymlink(_ url: URL) -> Bool {
        do {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            return values.isSymbolicLink == true
        } catch {
            return false
        }
    }

    /// Verifies that [child] is strictly contained within [parent] with directory boundary checks.
    public static func isContained(child: URL, parent: URL) -> Bool {
        let parentStandardized = parent.resolvingSymlinksInPath().standardizedFileURL.path
        let parentBoundary = parentStandardized.hasSuffix("/") ? parentStandardized : parentStandardized + "/"
        let childStandardized = child.resolvingSymlinksInPath().standardizedFileURL.path
        return childStandardized == parentStandardized || childStandardized.hasPrefix(parentBoundary)
    }

    /// Validates whether a file name is safe from path traversal and invalid characters.
    public static func isSafeFileName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        if name == "." || name == ".." { return false }
        if name.contains("/") || name.contains("\\") || name.contains("\0") { return false }
        if name.contains("..") { return false }
        if name.hasPrefix(".") { return false }
        if name.utf8.count > 255 { return false }
        return true
    }

    /// Saves received file data safely under `<baseDirectory>/<transferId>/<fileName>`.
    @discardableResult
    public func saveReceivedFile(data: Data, fileName: String, transferId: String) throws -> URL {
        guard Self.isSafeFileName(fileName) else {
            throw CloudSyncFileTransferError.unsafeFileName(fileName)
        }
        guard Self.isSafeFileName(transferId) else {
            throw CloudSyncFileTransferError.unsafeFileName(transferId)
        }

        let baseResolved = baseDirectory.resolvingSymlinksInPath()
        let folder = baseResolved.appendingPathComponent(transferId, isDirectory: true)
        guard Self.isContained(child: folder, parent: baseResolved) else {
            throw CloudSyncFileTransferError.unsafeFileName(transferId)
        }
        let dirAttrs: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: dirAttrs)
        try? FileManager.default.setAttributes(dirAttrs, ofItemAtPath: folder.path)

        let originalURL = folder.appendingPathComponent(fileName, isDirectory: false)
        if Self.isSymlink(originalURL) {
            throw CloudSyncFileTransferError.unsafeFileName(fileName)
        }

        var targetURL = originalURL
        guard Self.isContained(child: targetURL, parent: folder) else {
            throw CloudSyncFileTransferError.unsafeFileName(fileName)
        }

        // Avoid accidental overwriting by appending counter if file already exists
        var counter = 1
        while FileManager.default.fileExists(atPath: targetURL.path) {
            let ext = originalURL.pathExtension
            let nameWithoutExt = originalURL.deletingPathExtension().lastPathComponent
            let uniqueName = "\(nameWithoutExt) (\(counter))\(ext.isEmpty ? "" : ".\(ext)")"
            guard Self.isSafeFileName(uniqueName) else {
                throw CloudSyncFileTransferError.unsafeFileName(uniqueName)
            }
            let candidateURL = folder.appendingPathComponent(uniqueName, isDirectory: false)
            if Self.isSymlink(candidateURL) {
                throw CloudSyncFileTransferError.unsafeFileName(uniqueName)
            }
            guard Self.isContained(child: candidateURL, parent: folder) else {
                throw CloudSyncFileTransferError.unsafeFileName(uniqueName)
            }
            targetURL = candidateURL
            counter += 1
        }

        try data.write(to: targetURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: targetURL.path)
        return targetURL
    }
}
