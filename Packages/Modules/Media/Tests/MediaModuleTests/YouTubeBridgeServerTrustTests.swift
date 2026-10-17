import Foundation
import LocalSocketKit
import MyNotchTestSupport
import Testing
@testable import MediaModule
@testable import YouTubeBridgeKit

/// The host connects only to a socket whose folder is the user's own and closed to others (`SocketTrust.inspect`); these tests
/// pin that the folder the app's server makes is exactly one that the host accepts, so the two cannot drift apart: a host that
/// refused the app's own folder would keep every caption from the notch.
@Suite final class YouTubeBridgeServerTrustTests {
    /// Unix socket paths are limited to 104 bytes, so the folder is short and outside the sandboxed temp dir.
    let directory = ScratchFolders.shared.reserveShort()
    var path: String { directory.appending(path: YouTubeSocket.fileName).path }

    deinit { try? FileManager.default.removeItem(at: directory) }

    private func makeServer(at socketPath: String? = nil) -> YouTubeBridgeServer {
        YouTubeBridgeServer(socketPath: socketPath ?? path) { _ in }
    }

    @Test func aFolderTheServerMakesIsOneTheHostTrusts() throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        #expect(SocketTrust.inspect(socketPath: path) == .trusted)
        let fd = try #require(UnixStreamSocket.connect(to: path, expectedOwner: geteuid()))
        close(fd)
    }

    @Test func aFolderThatWasOpenToOthersIsClosedByTheServerAndThenTrusted() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        chmod(directory.path, 0o755)
        #expect(SocketTrust.inspect(socketPath: path) == .untrusted, "a folder open to others is not one the host accepts")
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        #expect(SocketTrust.inspect(socketPath: path) == .trusted)
    }

    /// The fallback `/tmp/mynotch-<uid>/youtube.sock` has a folder the server makes below one that is there: the same code
    /// makes it, and the host asks about it the same way.
    @Test func aFolderBelowAFolderThatIsNotThereYetIsTrustedToo() throws {
        let nested = directory.appending(path: "mynotch-\(getuid())", directoryHint: .isDirectory).appending(path: YouTubeSocket.fileName).path
        let server = makeServer(at: nested)
        try server.start()
        defer { server.stop() }
        #expect(SocketTrust.inspect(socketPath: nested) == .trusted)
    }

    @Test func aStaleFileInTheSocketsPlaceIsReplacedByASocketTheHostTrusts() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: URL(filePath: path))
        #expect(SocketTrust.inspect(socketPath: path) != .trusted)
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        #expect(SocketTrust.inspect(socketPath: path) == .trusted)
    }

    @Test func aStoppedServerLeavesNoSocketForTheHostToFind() throws {
        let server = makeServer()
        try server.start()
        server.stop()
        #expect(SocketTrust.inspect(socketPath: path) == .absent)
        #expect(UnixStreamSocket.open(to: path, expectedOwner: geteuid()) == .failure(.noSocket))
    }
}
