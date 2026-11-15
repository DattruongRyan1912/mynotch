import Foundation
import Testing
@testable import FanHelperKit

@Suite struct CodeIdentityTests {
    @Test func theBuildIDOfASignedFileIsItsCodeDirectoryHash() throws {
        let id = try #require(CodeIdentity.buildID(ofFileAt: URL(fileURLWithPath: "/bin/ls")))
        #expect(id.count == 40)
        #expect(id.allSatisfy { "0123456789abcdef".contains($0) })
    }

    @Test func aFileThatDoesNotExistHasNoBuildID() {
        #expect(CodeIdentity.buildID(ofFileAt: URL(fileURLWithPath: "/nonexistent/helper")) == nil)
    }

    @Test func aFileThatIsNotSignedHasNoBuildID() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "unsigned-\(UUID().uuidString).txt")
        try Data("not code".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(CodeIdentity.buildID(ofFileAt: url) == nil)
    }

    /// The helper reports the running image's hash and the app computes the bundled file's: for the same file they must agree, or
    /// every launch would look like an update.
    @Test func theRunningProcessAndItsFileOnDiskAgree() throws {
        let running = try #require(CodeIdentity.runningBuildID())
        let executable = try #require(Bundle.main.executableURL)
        let file = try #require(CodeIdentity.buildID(ofFileAt: executable))
        #expect(running == file)
    }
}
