import Foundation
import LocalSocketKit
import Testing
@testable import ClipboardMCPKit

/// Where the helper and the app meet. Who is trusted at that place is `LocalSocketKit`'s, and tested there.
@Suite struct ClipboardMCPSocketTests {
    // MARK: Where the socket is

    @Test func theSocketIsInTheModulesFolderUnderTheAppsApplicationSupport() {
        let support = URL(filePath: "/Users/a/Library/Application Support", directoryHint: .isDirectory)
        #expect(ClipboardMCPSocket.defaultPath(applicationSupport: support, uid: 501)
            == "/Users/a/Library/Application Support/io.lucasvu.mynotch/Modules/clipboard/mcp.sock")
        #expect(ClipboardMCPSocket.path(inStorageDirectory: URL(filePath: "/x/clipboard", directoryHint: .isDirectory), uid: 501) == "/x/clipboard/mcp.sock")
    }

    @Test func aPathThatDoesNotFitFallsBackToAFolderUnderTmpNamedForTheUser() {
        let long = URL(filePath: "/" + String(repeating: "d", count: 120), directoryHint: .isDirectory)
        #expect(ClipboardMCPSocket.path(inStorageDirectory: long, uid: 501) == "/tmp/mynotch-501/clipboard-mcp.sock")
        #expect(SocketAddress(path: ClipboardMCPSocket.path(inStorageDirectory: long, uid: 501)) != nil)
    }

    @Test func theFallbackNeverSharesAFileNameWithTheAgentSockets() {
        #expect(!["agent.sock", "perm.sock"].contains(URL(filePath: ClipboardMCPSocket.fallbackPath(uid: 1)).lastPathComponent))
    }
}
