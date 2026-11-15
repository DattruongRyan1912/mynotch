import Foundation
import Testing
import LocalSocketKit
import MyNotchTestSupport

/// A helper sends a request, which can name a tool, a command or what the user copied, only to a listener it can tell is the
/// user's own app. In the folder under `/tmp` that the app falls back to for a long user name, every other user can create the
/// folder first, so who owns it and who can open it is what these tests turn on.
@Suite struct SocketTrustTests {
    let me = geteuid()
    var someoneElse: uid_t { me &+ 1 }

    @Test func aFolderOfTheUserThatNobodyElseCanOpenWithTheirSocketIsTrusted() throws {
        let folder = try SocketFolder()
        try folder.bindSocket()
        #expect(SocketTrust.inspect(socketPath: folder.socketPath) == .trusted)
        #expect(SocketTrust.inspect(socketPath: folder.socketPath, user: me) == .trusted)
    }

    @Test func aFolderOwnedByAnotherUserIsNotTrusted() throws {
        let folder = try SocketFolder()
        try folder.bindSocket()
        // The test cannot make a folder of another user; it asks for the folder as that user would, which is the same check.
        #expect(SocketTrust.inspect(socketPath: folder.socketPath, user: someoneElse) == .untrusted)
    }

    @Test func aFolderOthersCanReadOrWriteIsNotTrustedWhateverItsOwner() throws {
        for bits: mode_t in [0o755, 0o750, 0o770, 0o777, 0o701, 0o707] {
            let folder = try SocketFolder()
            try folder.bindSocket()
            chmod(folder.path, bits)
            #expect(SocketTrust.inspect(socketPath: folder.socketPath) == .untrusted, "mode \(String(bits, radix: 8))")
        }
    }

    @Test func aFolderTheUserCannotEvenEnterIsNotTrustedEither() throws {
        let folder = try SocketFolder()
        try folder.bindSocket()
        chmod(folder.path, 0o500)
        #expect(SocketTrust.inspect(socketPath: folder.socketPath) == .untrusted)
    }

    @Test func aFolderThatIsALinkIsNotTrustedEvenWhenWhatItPointsToIs() throws {
        let target = try SocketFolder()
        try target.bindSocket()
        let link = SocketFolder.reservedPath()
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target.path)
        defer { try? FileManager.default.removeItem(atPath: link) }
        #expect(SocketTrust.inspect(socketPath: link + "/perm.sock") == .untrusted)
    }

    @Test func aMissingFolderOrSocketIsAbsentSoAnAppThatIsNotRunningIsNotMistakenForAnAttack() throws {
        #expect(SocketTrust.inspect(socketPath: SocketFolder.reservedPath() + "/perm.sock") == .absent)
        let folder = try SocketFolder()
        #expect(SocketTrust.inspect(socketPath: folder.socketPath) == .absent)
    }

    @Test func aFolderThatIsAFileIsNotTrustedAndAPathBelowAFileIsAbsent() throws {
        let folder = try SocketFolder()
        let file = folder.path + "/not-a-folder"
        try Data("x".utf8).write(to: URL(filePath: file))
        // A file in place of the folder: it is there, and it is not what the app makes.
        #expect(SocketTrust.inspect(socketPath: file + "/perm.sock") == .untrusted)
        // Nothing can be below a file: the folder is not there at all.
        #expect(SocketTrust.inspect(socketPath: file + "/sub/perm.sock") == .absent)
    }

    @Test func aFileThatIsNotASocketIsNotTrusted() throws {
        let folder = try SocketFolder()
        try Data("x".utf8).write(to: URL(filePath: folder.socketPath))
        #expect(SocketTrust.inspect(socketPath: folder.socketPath) == .untrusted)
        try FileManager.default.removeItem(atPath: folder.socketPath)
        try FileManager.default.createDirectory(atPath: folder.socketPath, withIntermediateDirectories: false)
        #expect(SocketTrust.inspect(socketPath: folder.socketPath) == .untrusted)
    }

    @Test func aLinkInPlaceOfTheSocketIsNotTrusted() throws {
        let folder = try SocketFolder()
        let other = try SocketFolder()
        try other.bindSocket()
        try FileManager.default.createSymbolicLink(atPath: folder.socketPath, withDestinationPath: other.socketPath)
        #expect(SocketTrust.inspect(socketPath: folder.socketPath) == .untrusted)
    }

    @Test func aSocketOfAnotherUserInTheFolderIsNotTrusted() throws {
        let folder = try SocketFolder()
        try folder.bindSocket()
        // The folder check passes for the user it is owned by; the socket is checked against the same user.
        #expect(SocketTrust.inspect(socketPath: folder.socketPath, user: someoneElse) != .trusted)
    }

    // MARK: Peer

    @Test func aPeerIsTheUserWhenItIsAProcessOfThatUser() {
        var pair: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0)
        defer { pair.forEach { close($0) } }
        #expect(SocketTrust.isPeer(pair[0]))
        #expect(SocketTrust.isPeer(pair[0], user: me))
        #expect(!SocketTrust.isPeer(pair[0], user: someoneElse))
    }

    @Test func aDescriptorThatIsNotASocketHasNoPeer() throws {
        #expect(!SocketTrust.isPeer(-1))
        #expect(!SocketTrust.isPeer(-1, user: me))
        let folder = try SocketFolder()
        let file = open(folder.path + "/plain", O_CREAT | O_RDWR, 0o600)
        defer { close(file) }
        #expect(file >= 0)
        #expect(!SocketTrust.isPeer(file))
    }
}
