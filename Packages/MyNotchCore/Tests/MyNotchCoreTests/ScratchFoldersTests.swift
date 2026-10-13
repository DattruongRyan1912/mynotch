import Foundation
import Testing
import MyNotchTestSupport

@Suite struct ScratchFoldersTests {
    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    @Test func reservedPathsAreUniqueUnderTheTemporaryDirectoryWithThePrefixVerifyShSweeps() {
        let folders = ScratchFolders()
        let first = folders.reserve("Shelf")
        let second = folders.reserve("Shelf")
        let unlabelled = folders.reserve()
        #expect(first != second)
        #expect(first.deletingLastPathComponent().standardizedFileURL == FileManager.default.temporaryDirectory.standardizedFileURL)
        #expect(first.lastPathComponent.hasPrefix("MyNotchTests-Shelf-"))
        #expect(unlabelled.lastPathComponent.hasPrefix("MyNotchTests-"))
        #expect(!exists(first))
    }

    @Test func removeAllDeletesEveryReservedFolderWithItsContentsAndForgetsThem() throws {
        let folders = ScratchFolders()
        let first = folders.reserve("A")
        let second = folders.reserve("B")
        try FileManager.default.createDirectory(at: first.appending(path: "nested"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: first.appending(path: "nested/file"))
        // Never created: removing it is not an error.
        _ = second

        folders.removeAll()
        #expect(!exists(first))

        // A path that was swept is no longer tracked, so a folder created there later is left alone.
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: first) }
        folders.removeAll()
        #expect(exists(first))
    }
}
