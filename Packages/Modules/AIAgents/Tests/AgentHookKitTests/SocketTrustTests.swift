import Foundation
import Testing
@testable import AgentHookKit

/// The helper sends a request, which names the tool and the command, only to a listener it can tell is the user's own app.
/// In the folder under `/tmp` that the app falls back to for a long user name, every other user can create the folder
/// first, so who owns it and who can open it is what these tests turn on.
@Suite struct SocketTrustTests {
    /// A folder under /tmp (short, so a socket path fits) that is removed with the test.
    final class Folder {
        let path = "/tmp/mn-\(UUID().uuidString.prefix(8))"
        var socketPath: String { path + "/perm.sock" }
        private var listener: Int32 = -1

        init(mode: mode_t = 0o700) throws {
            try FileManager.default.createDirectory(
                atPath: path, withIntermediateDirectories: true, attributes: [.posixPermissions: Int(mode)]
            )
        }

        /// A listening socket file in it.
        func bindSocket(named name: String = "perm.sock") throws {
            listener = socket(AF_UNIX, SOCK_STREAM, 0)
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array((path + "/" + name).utf8) + [0]) }
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard bound == 0, listen(listener, 1) == 0 else { throw CocoaError(.fileWriteUnknown) }
        }

        /// Closes the socket and leaves its file, as a crashed app does.
        func stopListening() {
            if listener >= 0 { close(listener) }
            listener = -1
        }

        deinit {
            if listener >= 0 { close(listener) }
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    let me = geteuid()
    var someoneElse: uid_t { me &+ 1 }

    @Test func aFolderOfTheUserThatNobodyElseCanOpenWithTheirSocketIsTrusted() throws {
        let folder = try Folder()
        try folder.bindSocket()
        #expect(SocketTrust.inspect(socketPath: folder.socketPath) == .trusted)
        #expect(SocketTrust.inspect(socketPath: folder.socketPath, user: me) == .trusted)
    }

    @Test func aFolderOwnedByAnotherUserIsNotTrusted() throws {
        let folder = try Folder()
        try folder.bindSocket()
        // The test cannot make a folder of another user; it asks for the folder as that user would, which is the same check.
        #expect(SocketTrust.inspect(socketPath: folder.socketPath, user: someoneElse) == .untrusted)
    }

    @Test func aFolderOthersCanReadOrWriteIsNotTrustedWhateverTheirOwner() throws {
        for mode: mode_t in [0o755, 0o750, 0o770, 0o777, 0o701, 0o707] {
            let folder = try Folder()
            try folder.bindSocket()
            chmod(folder.path, mode)
            #expect(SocketTrust.inspect(socketPath: folder.socketPath) == .untrusted, "mode \(String(mode, radix: 8))")
        }
    }

    @Test func aFolderThatIsALinkIsNotTrustedEvenWhenWhatItPointsToIs() throws {
        let target = try Folder()
        try target.bindSocket()
        let link = "/tmp/mn-\(UUID().uuidString.prefix(8))"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target.path)
        defer { try? FileManager.default.removeItem(atPath: link) }
        #expect(SocketTrust.inspect(socketPath: link + "/perm.sock") == .untrusted)
    }

    @Test func aMissingFolderOrSocketIsAbsentAndNotUntrustedSoAnAppThatIsNotRunningIsNotMistakenForAnAttack() throws {
        #expect(SocketTrust.inspect(socketPath: "/tmp/mn-\(UUID().uuidString.prefix(8))/perm.sock") == .absent)
        let folder = try Folder()
        #expect(SocketTrust.inspect(socketPath: folder.socketPath) == .absent)
    }

    @Test func aFileThatIsNotASocketIsNotTrusted() throws {
        let folder = try Folder()
        try Data("x".utf8).write(to: URL(filePath: folder.socketPath))
        #expect(SocketTrust.inspect(socketPath: folder.socketPath) == .untrusted)
        let nested = try Folder()
        try FileManager.default.createDirectory(atPath: nested.socketPath, withIntermediateDirectories: false)
        #expect(SocketTrust.inspect(socketPath: nested.socketPath) == .untrusted)
    }

    @Test func aSocketOfAnotherUserInTheFolderIsNotTrusted() throws {
        let folder = try Folder()
        try folder.bindSocket()
        // The folder check passes for the user it is owned by; the socket is checked against the same user.
        #expect(SocketTrust.inspect(socketPath: folder.socketPath, user: someoneElse) != .trusted)
    }

    // MARK: Peer

    @Test func aPeerIsTheUserWhenItIsAProcessOfThatUser() {
        var pair: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0)
        defer { pair.forEach { close($0) } }
        #expect(SocketTrust.isPeer(pair[0], user: me))
        #expect(!SocketTrust.isPeer(pair[0], user: someoneElse))
    }

    @Test func aDescriptorThatIsNotASocketHasNoPeer() {
        #expect(!SocketTrust.isPeer(-1, user: me))
    }
}
