import Foundation
import Testing
@testable import ClipboardMCPKit

/// The helper sends a request, which can name what the user copied, only to a listener it can tell is the user's own app.
/// In the folder under `/tmp` that the app falls back to for a long user name, every other user can create the folder
/// first, so who owns it and who can open it is what these tests turn on.
@Suite struct ClipboardMCPSocketTests {
    let me = geteuid()
    var someoneElse: uid_t { me &+ 1 }

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
        #expect(MCPSocketAddress(path: ClipboardMCPSocket.path(inStorageDirectory: long, uid: 501)) != nil)
    }

    @Test func theFallbackNeverSharesAFileNameWithTheAgentSockets() {
        #expect(!["agent.sock", "perm.sock"].contains(URL(filePath: ClipboardMCPSocket.fallbackPath(uid: 1)).lastPathComponent))
    }

    @Test func anAddressHoldsAPathUpToTheLimitAndRefusesOneByteMore() {
        let fits = String(repeating: "a", count: MCPSocketAddress.maxPathLength)
        #expect(MCPSocketAddress(path: fits) != nil)
        #expect(MCPSocketAddress(path: fits + "a") == nil)
    }

    // MARK: Who is there

    @Test func aFolderOfTheUserThatNobodyElseCanOpenWithTheirSocketIsTrusted() throws {
        let folder = try SocketFolder()
        try folder.bindSocket()
        #expect(MCPSocketTrust.inspect(socketPath: folder.socketPath) == .trusted)
        #expect(MCPSocketTrust.inspect(socketPath: folder.socketPath, user: me) == .trusted)
    }

    @Test func aFolderOwnedByAnotherUserIsNotTrusted() throws {
        let folder = try SocketFolder()
        try folder.bindSocket()
        // The test cannot make a folder of another user; it asks for the folder as that user would, which is the same check.
        #expect(MCPSocketTrust.inspect(socketPath: folder.socketPath, user: someoneElse) == .untrusted)
    }

    @Test func aFolderOthersCanReadOrWriteIsNotTrustedWhateverItsOwner() throws {
        for mode: mode_t in [0o755, 0o750, 0o770, 0o777, 0o701, 0o707] {
            let folder = try SocketFolder()
            try folder.bindSocket()
            chmod(folder.path, mode)
            #expect(MCPSocketTrust.inspect(socketPath: folder.socketPath) == .untrusted, "mode \(String(mode, radix: 8))")
        }
    }

    @Test func aFolderThatIsALinkIsNotTrustedEvenWhenWhatItPointsToIs() throws {
        let target = try SocketFolder()
        try target.bindSocket()
        let link = "/tmp/mn-\(UUID().uuidString.prefix(8))"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target.path)
        defer { try? FileManager.default.removeItem(atPath: link) }
        #expect(MCPSocketTrust.inspect(socketPath: link + "/mcp.sock") == .untrusted)
    }

    @Test func aMissingFolderOrSocketIsAbsentSoAnAppThatIsNotRunningIsNotMistakenForAnAttack() throws {
        #expect(MCPSocketTrust.inspect(socketPath: "/tmp/mn-\(UUID().uuidString.prefix(8))/mcp.sock") == .absent)
        let folder = try SocketFolder()
        #expect(MCPSocketTrust.inspect(socketPath: folder.socketPath) == .absent)
    }

    @Test func aFileThatIsNotASocketIsNotTrusted() throws {
        let folder = try SocketFolder()
        try Data("x".utf8).write(to: URL(filePath: folder.socketPath))
        #expect(MCPSocketTrust.inspect(socketPath: folder.socketPath) == .untrusted)
        try FileManager.default.removeItem(atPath: folder.socketPath)
        try FileManager.default.createDirectory(atPath: folder.socketPath, withIntermediateDirectories: false)
        #expect(MCPSocketTrust.inspect(socketPath: folder.socketPath) == .untrusted)
    }

    @Test func aConnectedPeerIsTheUserOrNot() {
        var fds: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
        defer { close(fds[0]); close(fds[1]) }
        #expect(MCPSocketTrust.isPeer(fds[0]))
        #expect(MCPSocketTrust.isPeer(fds[0], user: me))
        #expect(!MCPSocketTrust.isPeer(fds[0], user: someoneElse))
        #expect(!MCPSocketTrust.isPeer(-1))
    }
}
