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

    @Test func anAddressNeedsThePathToFitSunPath() {
        #expect(UnixSocketAddress.maxPathLength == 103)
        #expect(UnixSocketAddress(path: "/tmp/" + String(repeating: "a", count: 98)) != nil)
        #expect(UnixSocketAddress(path: "/tmp/" + String(repeating: "a", count: 99)) == nil)
    }
}
