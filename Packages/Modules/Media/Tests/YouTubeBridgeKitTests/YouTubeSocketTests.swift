import Foundation
import Testing
@testable import YouTubeBridgeKit

@Suite struct YouTubeSocketTests {
    @Test func theSocketLivesInTheModulesStorageDirectory() {
        let storage = URL(filePath: "/Users/example/Library/Application Support/io.lucasvu.mynotch/Modules/media", directoryHint: .isDirectory)
        #expect(YouTubeSocket.path(inStorageDirectory: storage, uid: 501) == storage.path + "/youtube.sock")
    }

    @Test func aPathThatDoesNotFitFallsBackToATemporaryFolderPerUser() {
        let storage = URL(filePath: "/Users/" + String(repeating: "x", count: 90) + "/Modules/media", directoryHint: .isDirectory)
        #expect(YouTubeSocket.path(inStorageDirectory: storage, uid: 501) == "/tmp/mynotch-501/youtube.sock")
    }

    @Test func aPathOfExactlyOneHundredThreeBytesStillFits() {
        let fileName = "/youtube.sock"
        let folder = "/" + String(repeating: "d", count: 103 - fileName.count - 1)
        let fitting = URL(filePath: folder, directoryHint: .isDirectory)
        #expect(YouTubeSocket.path(inStorageDirectory: fitting, uid: 501).utf8.count == 103)
        #expect(YouTubeSocket.path(inStorageDirectory: fitting, uid: 501) == folder + fileName)
        let tooLong = URL(filePath: folder + "d", directoryHint: .isDirectory)
        #expect(YouTubeSocket.path(inStorageDirectory: tooLong, uid: 501) == "/tmp/mynotch-501/youtube.sock")
    }

    @Test func theDefaultPathIsTheAppsStandardStorageFolderOfTheModule() {
        let support = URL(filePath: "/Users/example/Library/Application Support", directoryHint: .isDirectory)
        #expect(
            YouTubeSocket.defaultPath(applicationSupport: support, uid: 501)
                == "/Users/example/Library/Application Support/io.lucasvu.mynotch/Modules/media/youtube.sock"
        )
    }

    @Test func aSupportFolderThatDoesNotFitFallsBackToTheTemporaryFolderOfTheUser() {
        let support = URL(filePath: "/Users/" + String(repeating: "x", count: 90) + "/Library/Application Support", directoryHint: .isDirectory)
        #expect(YouTubeSocket.defaultPath(applicationSupport: support, uid: 501) == "/tmp/mynotch-501/youtube.sock")
    }

    @Test func theHostsConnectionNeverRaisesSIGPIPEWhenTheAppHasGone() async throws {
        // The host writes to the app's socket from two threads (messages and the replay) and the app may go at any moment.
        let watch = SigpipeWatch()
        let server = FrameServer()
        defer { server.remove() }
        try server.start()
        let fd = try #require(UnixStreamSocket.connect(to: server.path, expectedOwner: geteuid()))
        defer { close(fd) }
        var guarded: Int32 = 0
        var size = socklen_t(MemoryLayout<Int32>.size)
        #expect(getsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &guarded, &size) == 0)
        #expect(guarded == 1)
        await waitUntil { server.connectionCount == 1 }
        server.stop()
        // Writes may still be taken for a moment after the app's end was shut; once it is closed they fail, and must not signal.
        let failed = await waitUntil { !UnixStreamSocket.writeAll(Data("a".utf8), to: fd) }
        #expect(failed)
        #expect(!UnixStreamSocket.writeAll(Data("b".utf8), to: fd))
        #expect(watch.count == 0, "a write to a socket whose peer has gone must not raise SIGPIPE (SO_NOSIGPIPE)")
    }

    @Test func anAddressNeedsThePathToFitSunPath() {
        #expect(UnixSocketAddress.maxPathLength == 103)
        #expect(UnixSocketAddress(path: "/tmp/" + String(repeating: "a", count: 98)) != nil)
        #expect(UnixSocketAddress(path: "/tmp/" + String(repeating: "a", count: 99)) == nil)
    }
}
