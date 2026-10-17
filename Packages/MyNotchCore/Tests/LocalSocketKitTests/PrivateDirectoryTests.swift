import Foundation
import Testing
import LocalSocketKit
import MyNotchTestSupport

/// The folder the app's sockets live in. `/tmp/mynotch-<uid>` sits in a folder every user can write to, so someone else may have
/// made it first, or made it a link.
@Suite struct PrivateDirectoryTests {
    let me = geteuid()
    var someoneElse: uid_t { me &+ 1 }

    private func url(_ path: String) -> URL { URL(filePath: path, directoryHint: .isDirectory) }

    @Test func makesTheFolderAndItsParentsClosedToEveryoneElse() throws {
        let root = SocketFolder.reservedPath()
        let directory = url(root + "/a/b")
        try PrivateDirectory.prepare(directory)
        #expect(mode(of: directory.path) == 0o700)
        #expect(SocketTrust.inspect(socketPath: directory.path + "/x.sock") == .absent)
    }

    @Test func aFolderThatIsOpenToOthersIsClosedAgain() throws {
        for bits in [0o755, 0o777, 0o770, 0o750] as [mode_t] {
            let folder = try SocketFolder(mode: bits)
            try PrivateDirectory.prepare(url(folder.path))
            #expect(mode(of: folder.path) == 0o700, "mode \(String(bits, radix: 8))")
        }
    }

    @Test func aFolderThatIsAlreadyRightIsLeftWithItsContents() throws {
        let folder = try SocketFolder()
        try folder.bindSocket()
        try PrivateDirectory.prepare(url(folder.path))
        #expect(mode(of: folder.path) == 0o700)
        #expect(SocketTrust.inspect(socketPath: folder.socketPath) == .trusted)
    }

    /// The test cannot make a folder of another user; it asks for the folder as that user would, which is the same check. It
    /// comes before anything is changed in it.
    @Test func aFolderOfAnotherUserIsRefusedAndLeftAsItWas() throws {
        let folder = try SocketFolder(mode: 0o755)
        #expect(throws: PrivateDirectory.Failure.notOwned) { try PrivateDirectory.prepare(url(folder.path), user: someoneElse) }
        #expect(mode(of: folder.path) == 0o755)
    }

    @Test(.enabled(if: geteuid() != 0)) func theSystemsOwnFolderIsRefused() {
        #expect(throws: PrivateDirectory.Failure.notOwned) { try PrivateDirectory.prepare(url("/Library")) }
    }

    @Test func aLinkInPlaceOfTheFolderIsRefusedEvenWhenItPointsToAFolderOfTheUser() throws {
        let target = try SocketFolder(mode: 0o755)
        let link = SocketFolder.reservedPath()
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target.path)
        defer { try? FileManager.default.removeItem(atPath: link) }
        #expect(throws: PrivateDirectory.Failure.notOwned) { try PrivateDirectory.prepare(url(link)) }
        // What it points to is not changed either.
        #expect(mode(of: target.path) == 0o755)
    }

    @Test(.enabled(if: geteuid() != 0)) func aLinkToAFolderOfAnotherUserIsRefusedToo() throws {
        let link = SocketFolder.reservedPath()
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: "/Library")
        defer { try? FileManager.default.removeItem(atPath: link) }
        #expect(throws: PrivateDirectory.Failure.notOwned) { try PrivateDirectory.prepare(url(link)) }
    }

    @Test func aFileInPlaceOfTheFolderIsRefused() throws {
        let folder = try SocketFolder()
        let file = folder.path + "/file"
        try Data("x".utf8).write(to: URL(filePath: file))
        #expect(throws: PrivateDirectory.Failure.notOwned) { try PrivateDirectory.prepare(url(file)) }
    }

    @Test(.enabled(if: geteuid() != 0)) func aFolderThatCannotBeMadeIsReportedWithItsErrno() throws {
        let parent = try SocketFolder(mode: 0o500)
        #expect(throws: PrivateDirectory.Failure.system(errno: EACCES)) { try PrivateDirectory.prepare(url(parent.path + "/inside")) }
    }

    @Test func aParentThatIsAFileIsAnErrorOfTheFileSystemAndNotAFolderOfSomeoneElse() throws {
        let folder = try SocketFolder()
        let file = folder.path + "/file"
        try Data("x".utf8).write(to: URL(filePath: file))
        do {
            try PrivateDirectory.prepare(url(file + "/inside"))
            Issue.record("a folder cannot be made below a file")
        } catch let failure as PrivateDirectory.Failure {
            Issue.record("expected an error of the file system, got \(failure)")
        } catch {}
    }
}
