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
        try replace(locations.installedHost, with: locations.bundledHost)
        try replace(locations.installedExtension, with: locations.bundledExtension)
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

    /// A copy that starts from nothing, so no file of an older version stays behind.
    private func replace(_ destination: URL, with source: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.copyItem(at: source, to: destination)
    }
}
