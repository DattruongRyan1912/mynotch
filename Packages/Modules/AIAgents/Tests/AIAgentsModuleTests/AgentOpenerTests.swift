import Foundation
import MyNotchTestSupport
import Testing
@testable import AIAgentsModule

/// Which working directories may be opened. The path comes from a transcript, so it is checked before it
/// reaches Terminal: opening a file there would run it.
@Suite struct AgentOpenerTests {
    let sandbox = ScratchFolders.shared.reserve("AgentOpener")

    init() throws {
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }

    @Test func anExistingFolderIsOpenable() {
        #expect(AgentOpener.directory(for: sandbox.path)?.path == sandbox.path)
        #expect(AgentOpener.directory(for: sandbox.path + "/")?.path == sandbox.path)
    }

    @Test func aFileIsNot() throws {
        let file = sandbox.appending(path: "tool.sh")
        try Data("#!/bin/sh\n".utf8).write(to: file)
        #expect(AgentOpener.directory(for: file.path) == nil)
    }

    @Test func aMissingFolderIsNot() {
        #expect(AgentOpener.directory(for: sandbox.appending(path: "gone").path) == nil)
    }

    @Test func onlyAnAbsolutePathCounts() {
        #expect(AgentOpener.directory(for: nil) == nil)
        #expect(AgentOpener.directory(for: "") == nil)
        #expect(AgentOpener.directory(for: "Projects/demo") == nil)
        #expect(AgentOpener.directory(for: "~") == nil)
    }
}
