import Foundation
import LocalSocketKit
import MyNotchTestSupport
import Testing
@testable import YouTubeBridgeKit

/// What the host looks at before it connects, and that it connects to nothing else. Captions can hold what the user is
/// watching, and the folder under `/tmp` that the app falls back to for a long user name can be made by anyone first, so a
/// socket is spoken to only when its folder and its file are the user's own (see `SocketTrust.inspect`, which the helpers of the
/// agents and the clipboard also ask before they connect).
@Suite struct UnixStreamSocketTrustTests {
    let me = geteuid()
    var someoneElse: uid_t { me &+ 1 }

    /// The folder as the app makes it, with the socket file the app listens on in it (`listening: false` for a folder alone).
    func folder(mode: mode_t = 0o700, listening: Bool = true) throws -> SocketFolder {
        let folder = try SocketFolder(socketName: YouTubeSocket.fileName, mode: mode)
        if listening { try folder.bindSocket() }
        return folder
    }

    /// Closes the connection of a successful `open`, so that a test does not leave a descriptor.
    func opened(_ result: Result<Int32, UnixStreamSocket.ConnectFailure>) -> Int32? {
        guard case .success(let fd) = result else { return nil }
        close(fd)
        return fd
    }

    // MARK: trusted

    @Test func aFolderOfTheUserAndAListeningSocketInItIsConnectedTo() throws {
        let folder = try folder()
        let result = UnixStreamSocket.open(to: folder.socketPath, expectedOwner: me)
        #expect(opened(result) != nil, "\(result)")
    }

    @Test func aSocketFileNobodyListensOnAnyMoreIsRefusedNotUntrusted() throws {
        // The app that crashed leaves its socket file: it is the user's, so the host tries and is refused, as before.
        let folder = try folder()
        folder.stopListening()
        #expect(UnixStreamSocket.open(to: folder.socketPath, expectedOwner: me) == .failure(.refused))
    }

    // MARK: absent

    @Test func aFolderThatIsNotThereIsNoSocketLikeAnAppThatIsNotRunning() {
        let path = SocketFolder.reservedPath() + "/" + YouTubeSocket.fileName
        #expect(UnixStreamSocket.open(to: path, expectedOwner: me) == .failure(.noSocket))
    }

    @Test func aFolderWithoutTheSocketFileIsNoSocketToo() throws {
        let folder = try folder(listening: false)
        #expect(UnixStreamSocket.open(to: folder.socketPath, expectedOwner: me) == .failure(.noSocket))
    }

    // MARK: untrusted

    @Test(arguments: [0o755, 0o750, 0o770, 0o777, 0o701, 0o707] as [mode_t])
    func aFolderOthersCanOpenIsNotConnectedToWhateverIsListeningInIt(mode: mode_t) throws {
        let folder = try folder(mode: mode)
        let result = UnixStreamSocket.open(to: folder.socketPath, expectedOwner: me)
        #expect(result == .failure(.untrusted), "mode \(String(mode, radix: 8)): \(result)")
    }

    @Test func aFolderThatIsALinkIsNotConnectedToEvenWhenWhatItPointsToIsTheRightFolder() throws {
        let target = try folder()
        let link = SocketFolder.reservedPath()
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target.path)
        defer { try? FileManager.default.removeItem(atPath: link) }
        let result = UnixStreamSocket.open(to: link + "/" + YouTubeSocket.fileName, expectedOwner: me)
        #expect(result == .failure(.untrusted), "\(result)")
    }

    @Test func aFolderOfAnotherUserIsNotConnectedTo() throws {
        let folder = try folder()
        // The test cannot make a folder of another user; it asks for one as that user would, which is the same check. The
        // folder fails first, so the socket file's owner is not told apart here (`SocketTrustTests` in LocalSocketKit has it).
        let result = UnixStreamSocket.open(to: folder.socketPath, expectedOwner: someoneElse)
        #expect(result == .failure(.untrusted), "\(result)")
    }

    @Test func aFileThatIsNotASocketIsNotConnectedTo() throws {
        let folder = try folder(listening: false)
        try Data("x".utf8).write(to: URL(filePath: folder.socketPath))
        let result = UnixStreamSocket.open(to: folder.socketPath, expectedOwner: me)
        #expect(result == .failure(.untrusted), "\(result)")
    }

    @Test func aLinkInPlaceOfTheSocketFileIsNotConnectedTo() throws {
        let folder = try folder(listening: false)
        let other = try SocketFolder(socketName: "other.sock")
        try other.bindSocket()
        try FileManager.default.createSymbolicLink(atPath: folder.socketPath, withDestinationPath: other.socketPath)
        let result = UnixStreamSocket.open(to: folder.socketPath, expectedOwner: me)
        #expect(result == .failure(.untrusted), "\(result)")
    }

    // MARK: after connecting

    @Test func aProcessOfAnotherUserBehindTheRightFilesIsHungUpOn() throws {
        let folder = try folder()
        // Files of the user and a peer that is not: the case of a process that took over the socket's place; the host has
        // connected and looks at who it is before anything is sent.
        let result = UnixStreamSocket.open(to: folder.socketPath, fileOwner: me, peerUser: someoneElse)
        #expect(result == .failure(.otherUser), "\(result)")
    }

    @Test func theReasonsAreFixedWordsThatNameNoPathOrUser() {
        let failures: [UnixStreamSocket.ConnectFailure] = [.pathTooLong, .untrusted, .otherUser, .noSocket, .refused, .busy, .failed(errno: 13)]
        #expect(failures.map(\.reason) == ["path-too-long", "untrusted", "other-user", "no-socket", "refused", "busy", "error-13"])
    }
}
