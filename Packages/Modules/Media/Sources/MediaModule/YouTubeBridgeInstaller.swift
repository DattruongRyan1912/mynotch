import Foundation
import YouTubeBridgeKit

/// Puts the pieces of the Chrome bridge where Chrome and the user find them, and takes them away again. Pure over
/// the URLs it is given: the real ones are only named by `Locations.system`, and tests use temporary folders.
struct YouTubeBridgeInstaller {
    struct Unavailable: LocalizedError, Equatable {
        var path: String

        var errorDescription: String? { "Không tìm thấy \(path) trong app, cần để cài cầu nối." }
    }

    struct Locations: Equatable {
        /// `Contents/MacOS/mynotch-youtube-host` of the app, which moves and is replaced on update.
        var bundledHost: URL
        /// `Contents/Resources/ChromeExtension` of the app.
        var bundledExtension: URL
        /// A path that stays, which the host manifest names.
        var installedHost: URL
        /// Where the user loads the unpacked extension from.
        var installedExtension: URL
        /// Chrome's folder of native messaging host manifests.
        var nativeMessagingHosts: URL

        var manifest: URL { nativeMessagingHosts.appending(path: "\(YouTubeBridge.hostName).json") }

        /// The real places: the host and the extension copy in the app's own folders (`<support>/<bundle id>/...`), the
        /// manifest in Chrome's.
        /// - Parameters:
        ///   - storageDirectory: the Media module's storage, `<support>/<bundle id>/Modules/media`.
        ///   - applicationSupport: `~/Library/Application Support`, which is also where Chrome keeps its profile.
        static func system(
            storageDirectory: URL, applicationSupport: URL = .applicationSupportDirectory, bundle: URL = Bundle.main.bundleURL
        ) -> Locations {
            Locations(
                bundledHost: bundle.appending(path: "Contents/MacOS/mynotch-youtube-host"),
                bundledExtension: bundle.appending(path: "Contents/Resources/ChromeExtension", directoryHint: .isDirectory),
                installedHost: storageDirectory.appending(path: "bin/mynotch-youtube-host"),
                installedExtension: storageDirectory.deletingLastPathComponent().deletingLastPathComponent()
                    .appending(path: "ChromeExtension", directoryHint: .isDirectory),
                nativeMessagingHosts: applicationSupport.appending(path: "Google/Chrome/NativeMessagingHosts", directoryHint: .isDirectory)
            )
        }
    }

    var locations: Locations
    var extensionID = YouTubeBridge.extensionID

    /// The host and the manifest are what Chrome needs; the extension copy is what the user loads.
    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: locations.manifest.path)
            && FileManager.default.isExecutableFile(atPath: locations.installedHost.path)
    }

    /// Copies the host and the extension out of the app and writes the manifest that lets the extension start the
    /// host. Safe to run again: an older copy is replaced. Throws before changing anything when the app does not hold
    /// a runnable host or an extension.
    func install() throws {
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: locations.bundledHost.path) else {
            throw Unavailable(path: locations.bundledHost.path)
        }
        guard fileManager.fileExists(atPath: locations.bundledExtension.appending(path: "manifest.json").path) else {
            throw Unavailable(path: locations.bundledExtension.path)
        }
        try place(locations.installedHost, withCopyOf: locations.bundledHost)
        try place(locations.installedExtension, withCopyOf: locations.bundledExtension)
        try fileManager.createDirectory(at: locations.nativeMessagingHosts, withIntermediateDirectories: true)
        try manifestData().write(to: locations.manifest, options: .atomic)
    }

    /// Removes what `install` made, and only that: the manifest, the host and the extension copy. Whatever else is in
    /// those folders, Chrome's above all, stays. What is not there is not an error.
    func remove() throws {
        let fileManager = FileManager.default
        for url in [locations.manifest, locations.installedHost, locations.installedExtension]
            where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// What Chrome reads: the host's name, where its binary is, and the one extension allowed to start it.
    func manifestData() throws -> Data {
        let manifest: [String: Any] = [
            "name": YouTubeBridge.hostName,
            "description": "MyNotch YouTube captions bridge",
            "path": locations.installedHost.path,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(extensionID)/"],
        ]
        return try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    // MARK: keeping what is installed up to date

    /// What `updateIfNeeded` changed. Versions are digits and dots only, so they are safe to log.
    struct Update: Equatable {
        /// The version of the extension copy that was there; nil when it had none that could be read.
        var installedVersion: String?
        /// The version of the extension in the app, which the copy has now.
        var bundledVersion: String
        var refreshedExtension: Bool
        var refreshedHost: Bool
    }

    /// The bridge was put in place by the user before: the extension copy and Chrome's manifest for the host are both there. A missing
    /// host does not count against it (it is what a refresh restores); nothing at all, or only some of the two, is no install of ours.
    var wasInstalled: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: locations.manifest.path)
            && FileManager.default.fileExists(atPath: locations.installedExtension.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Brings an installation the user made up to the app: the extension copy when the app's is newer (or the copy has no readable version),
    /// the host when its binary is not the app's. Nothing is installed for a user who never installed the bridge, an older or equal app
    /// never replaces the extension (an app that goes back leaves what the user loaded in Chrome alone), and Chrome's manifest is never
    /// written, so what is allowed to start the host stays what the user set up. Each piece is copied beside its place and swapped in, so
    /// a copy that fails changes nothing and the old one stays.
    /// - Returns: what was changed; nil when nothing was.
    func updateIfNeeded() throws -> Update? {
        guard wasInstalled, let bundledVersion = Self.version(ofExtensionIn: locations.bundledExtension) else { return nil }
        let installedVersion = Self.version(ofExtensionIn: locations.installedExtension)
        let extensionIsOld = installedVersion.map { Self.isNewer(bundledVersion, than: $0) } ?? true
        let hostIsOld = FileManager.default.isExecutableFile(atPath: locations.bundledHost.path)
            && !Self.haveSameContents(locations.bundledHost, locations.installedHost)
        guard extensionIsOld || hostIsOld else { return nil }
        if hostIsOld { try place(locations.installedHost, withCopyOf: locations.bundledHost) }
        if extensionIsOld { try place(locations.installedExtension, withCopyOf: locations.bundledExtension) }
        return Update(installedVersion: installedVersion, bundledVersion: bundledVersion, refreshedExtension: extensionIsOld, refreshedHost: hostIsOld)
    }

    /// The `version` of the `manifest.json` in an extension folder, as Chrome writes versions: one to four whole numbers with dots.
    /// nil for anything else, so a version that is read is also one that can be logged.
    static func version(ofExtensionIn folder: URL) -> String? {
        guard let data = try? Data(contentsOf: folder.appending(path: "manifest.json")), data.count <= 1_000_000,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["version"] as? String, numbers(in: version) != nil
        else { return nil }
        return version
    }

    /// Whether `version` is later than `other`, number by number (0.10 is later than 0.9; a missing number is 0). False when either is not a version.
    static func isNewer(_ version: String, than other: String) -> Bool {
        guard var left = numbers(in: version), var right = numbers(in: other) else { return false }
        while left.count < right.count { left.append(0) }
        while right.count < left.count { right.append(0) }
        return right.lexicographicallyPrecedes(left)
    }

    private static func numbers(in version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard (1...9).contains(part.count), part.allSatisfy({ ("0"..."9").contains($0) }), let number = Int(part) else { return nil }
            numbers.append(number)
        }
        return numbers
    }

    /// Whether both files are there and say the same: sizes first, which settles most, then the bytes.
    private static func haveSameContents(_ first: URL, _ second: URL) -> Bool {
        let fileManager = FileManager.default
        func size(_ url: URL) -> Int? { (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? Int }
        guard let left = size(first), let right = size(second), left == right else { return false }
        return fileManager.contentsEqual(atPath: first.path, andPath: second.path)
    }

    /// Puts a copy of `source` at `destination` in one step: the copy is made beside the destination (same volume, hidden name), and only
    /// when it is whole does it take the old one's place, so a reader (Chrome, a running host) sees the old one or the new one, and a copy
    /// that fails leaves the old one as it was and nothing behind. The new item's own attributes are kept: the host stays executable.
    private func place(_ destination: URL, withCopyOf source: URL) throws {
        let fileManager = FileManager.default
        let folder = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        // What an earlier run that was cut short left beside it.
        let prefix = ".\(destination.lastPathComponent).update-"
        for name in (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? [] where name.hasPrefix(prefix) {
            try? fileManager.removeItem(at: folder.appending(path: name))
        }
        let copy = folder.appending(path: prefix + UUID().uuidString)
        do {
            try fileManager.copyItem(at: source, to: copy)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: copy, options: .usingNewMetadataOnly)
            } else {
                try fileManager.moveItem(at: copy, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: copy)
            throw error
        }
    }
}
