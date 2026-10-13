import Foundation
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

@Suite struct ModuleStorageTests {
    @Test func pathsAreNamespacedByModuleUnderBothRoots() {
        let root = StorageRoot(applicationSupport: URL(filePath: "/support"), caches: URL(filePath: "/caches"))
        let storage = root.storage(for: "clipboard")
        #expect(storage.directory.path(percentEncoded: false) == "/support/Modules/clipboard/")
        #expect(storage.cachesDirectory.path(percentEncoded: false) == "/caches/Modules/clipboard/")
    }

    @Test func standardRootUsesBundleIDFolders() {
        let root = StorageRoot.standard(bundleID: "io.example.app")
        #expect(root.applicationSupport.pathComponents.suffix(2) == ["Application Support", "io.example.app"])
        #expect(root.caches.pathComponents.suffix(2) == ["Caches", "io.example.app"])
    }

    @Test func ensureDirectoriesCreatesBothOnlyWhenCalledAndIsIdempotent() throws {
        let base = FileManager.default.temporaryDirectory
            .appending(path: "MyNotchTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: base) }
        let root = StorageRoot(applicationSupport: base.appending(path: "support"), caches: base.appending(path: "caches"))
        let storage = root.storage(for: "m")
        #expect(!exists(base))

        try storage.ensureDirectories()
        #expect(isDirectory(storage.directory))
        #expect(isDirectory(storage.cachesDirectory))

        let file = storage.directory.appending(path: "data.json")
        try Data("{}".utf8).write(to: file)
        try storage.ensureDirectories()
        #expect(exists(file))
    }

    @Test func harnessUsesAFreshTemporaryRoot() {
        let first = RegistryHarness([]).storageRoot
        let second = RegistryHarness([]).storageRoot
        let temporary = FileManager.default.temporaryDirectory.path(percentEncoded: false)
        #expect(first.applicationSupport.path(percentEncoded: false).hasPrefix(temporary))
        #expect(first.caches.path(percentEncoded: false).hasPrefix(temporary))
        #expect(first.applicationSupport != second.applicationSupport)
        #expect(!exists(first.applicationSupport))
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
