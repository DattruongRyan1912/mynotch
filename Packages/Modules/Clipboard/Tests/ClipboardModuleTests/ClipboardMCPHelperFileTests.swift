import Foundation
import MyNotchTestSupport
import Testing
@testable import ClipboardModule

/// Putting the helper where the agents' configuration points to, which stays when the app moves or is replaced.
@Suite struct ClipboardMCPHelperFileTests {
    let root = ScratchFolders.shared.reserve("helper")

    func makeSource(executable: Bool = true, content: String = "#!/bin/sh\nexit 0\n") throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appending(path: "bundled/mynotch-clipboard-mcp")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: source)
        chmod(source.path, executable ? 0o755 : 0o644)
        return source
    }

    @Test func theHelperIsCopiedAndStaysExecutable() throws {
        let source = try makeSource()
        let destination = root.appending(path: "storage/bin/mynotch-clipboard-mcp")
        try ClipboardMCPHelperFile.install(from: source, to: destination)
        #expect(FileManager.default.isExecutableFile(atPath: destination.path))
        #expect(try Data(contentsOf: destination) == Data(contentsOf: source))
    }

    @Test func aCopyThatIsThereIsReplacedByTheNewOne() throws {
        let destination = root.appending(path: "storage/bin/mynotch-clipboard-mcp")
        try ClipboardMCPHelperFile.install(from: try makeSource(content: "#!/bin/sh\necho old\n"), to: destination)
        try ClipboardMCPHelperFile.install(from: try makeSource(content: "#!/bin/sh\necho new\n"), to: destination)
        #expect(try String(contentsOf: destination, encoding: .utf8).contains("new"))
    }

    @Test func aHelperThatIsMissingOrNotExecutableIsAnErrorAndLeavesTheOldCopyAlone() throws {
        let destination = root.appending(path: "storage/bin/mynotch-clipboard-mcp")
        try ClipboardMCPHelperFile.install(from: try makeSource(content: "#!/bin/sh\necho kept\n"), to: destination)
        #expect(throws: ClipboardMCPHelperFile.Unavailable.self) {
            try ClipboardMCPHelperFile.install(from: root.appending(path: "nowhere"), to: destination)
        }
        let notExecutable = try makeSource(executable: false)
        #expect(throws: ClipboardMCPHelperFile.Unavailable.self) { try ClipboardMCPHelperFile.install(from: notExecutable, to: destination) }
        #expect(try String(contentsOf: destination, encoding: .utf8).contains("kept"))
    }

    @Test func theErrorSaysWhichFileWasMissing() {
        let error = ClipboardMCPHelperFile.Unavailable(path: "/x/y")
        #expect(error.errorDescription == "Không có mynotch-clipboard-mcp chạy được tại /x/y.")
    }
}
