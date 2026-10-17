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

    @Test func aShortPathIsNamedMnAndEightCharactersUnderTmpAndFitsASocketFile() {
        let folders = ScratchFolders()
        let first = folders.reserveShort()
        let second = folders.reserveShort()
        #expect(first != second)
        #expect(first.deletingLastPathComponent().path == "/tmp")
        #expect(first.lastPathComponent.count == "mn-".count + 8)
        #expect(first.lastPathComponent.hasPrefix("mn-"))
        // The longest name a socket in it has among the helpers' sockets, with room to spare for a longer one.
        #expect((first.path + "/clipboard-mcp.sock").utf8.count <= 103 - 20)
        #expect(!exists(first))
    }

    @Test func removeAllDeletesShortFoldersWithTheirContentsToo() throws {
        let folders = ScratchFolders()
        let folder = folders.reserveShort()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: folder.appending(path: "mcp.sock"))
        folders.removeAll()
        #expect(!exists(folder))
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
