import Foundation
import Testing
@testable import YouTubeBridgeKit

/// The id is fixed by the public key in the extension's manifest, and the native host manifest names it as the only
/// origin allowed to connect. The extension's own tests check the file against the key; this checks the constant.
@Suite struct ExtensionIDTests {
    struct RepositoryError: Error, CustomStringConvertible {
        let description: String
    }

    /// The `Extensions/Chrome/MyNotchYouTube` folder above this file, where the repository keeps it.
    static func extensionFolder(from file: String = #filePath) throws -> URL {
        var folder = URL(filePath: file).deletingLastPathComponent()
        while folder.path != "/" {
            let candidate = folder.appending(path: "Extensions/Chrome/MyNotchYouTube", directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: candidate.appending(path: "manifest.json").path) { return candidate }
            folder.deleteLastPathComponent()
        }
        throw RepositoryError(description: "No Extensions/Chrome/MyNotchYouTube above \(file)")
    }

    @Test func theConstantIsTheIdInTheExtensionsFile() throws {
        let file = try String(contentsOf: Self.extensionFolder().appending(path: "EXTENSION_ID"), encoding: .utf8)
        #expect(YouTubeBridge.extensionID == file.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test func itIsThirtyTwoLettersFromAToP() {
        #expect(YouTubeBridge.extensionID.count == 32)
        #expect(YouTubeBridge.extensionID.utf8.allSatisfy { (97...112).contains($0) })
    }

    @Test func theHostNameIsTheOneTheExtensionConnectsTo() throws {
        let bridge = try String(contentsOf: Self.extensionFolder().appending(path: "bridge.js"), encoding: .utf8)
        #expect(bridge.contains("var HOST_NAME = \"\(YouTubeBridge.hostName)\";"))
        #expect(YouTubeBridge.hostName == "io.lucasvu.mynotch.youtube")
    }
}
