import Foundation
import Testing
@testable import AIAgentsModule

/// Works on scripts written into a temporary directory; none of them is run.
@Suite struct HookHelperTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "HookHelperTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    var source: URL { directory.appending(path: "bundle/mynotch-hook") }
    var destination: URL { directory.appending(path: "support/bin/mynotch-hook") }

    func writeSource(_ text: String, mode: Int = 0o755) throws {
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: source)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: source.path)
    }

    @Test func theHelperIsCopiedToAStablePathAndStaysExecutable() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeSource("first")
        try HookHelper.install(from: source, to: destination)
        #expect(try String(contentsOf: destination, encoding: .utf8) == "first")
        #expect(FileManager.default.isExecutableFile(atPath: destination.path))
    }

    @Test func aNewerHelperReplacesTheOldCopy() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeSource("first")
        try HookHelper.install(from: source, to: destination)
        try writeSource("second")
        try HookHelper.install(from: source, to: destination)
        #expect(try String(contentsOf: destination, encoding: .utf8) == "second")
        #expect(FileManager.default.isExecutableFile(atPath: destination.path))
    }

    @Test func aMissingOrNotExecutableHelperIsRefusedAndLeavesTheOldCopyAlone() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(throws: HookHelper.Unavailable.self) { try HookHelper.install(from: source, to: destination) }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        try writeSource("first")
        try HookHelper.install(from: source, to: destination)
        try writeSource("second", mode: 0o644)
        #expect(throws: HookHelper.Unavailable.self) { try HookHelper.install(from: source, to: destination) }
        #expect(try String(contentsOf: destination, encoding: .utf8) == "first")
    }

    @Test func theRefusalNamesTheFile() {
        let message = HookHelper.Unavailable(path: "/app/mynotch-hook").localizedDescription
        #expect(message.contains("/app/mynotch-hook"))
    }
}
