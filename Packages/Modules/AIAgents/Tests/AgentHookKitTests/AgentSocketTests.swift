import Foundation
import Testing
@testable import AgentHookKit

@Suite struct AgentSocketTests {
    @Test func theSocketLivesInTheModulesStorageDirectory() {
        let storage = URL(filePath: "/Users/example/Library/Application Support/io.lucasvu.mynotch/Modules/aiagents", directoryHint: .isDirectory)
        #expect(AgentSocket.path(inStorageDirectory: storage, uid: 501) == storage.path + "/agent.sock")
    }

    @Test func aPathThatDoesNotFitFallsBackToATemporaryFolderPerUser() {
        let storage = URL(filePath: "/Users/" + String(repeating: "x", count: 90) + "/Modules/aiagents", directoryHint: .isDirectory)
        #expect(AgentSocket.path(inStorageDirectory: storage, uid: 501) == "/tmp/mynotch-501/agent.sock")
    }

    /// The literal layout of the app's storage; that the app really uses it is checked in `AgentSocketSyncTests` of the module's tests.
    @Test func theDefaultPathIsTheAppsStandardStorageFolderOfTheModule() {
        let support = URL(filePath: "/Users/example/Library/Application Support", directoryHint: .isDirectory)
        #expect(
            AgentSocket.defaultPath(applicationSupport: support, uid: 501)
                == "/Users/example/Library/Application Support/io.lucasvu.mynotch/Modules/aiagents/agent.sock"
        )
    }

    @Test func aSupportFolderThatDoesNotFitFallsBackToTheTemporaryFolderOfTheUser() {
        let support = URL(filePath: "/Users/" + String(repeating: "x", count: 90) + "/Library/Application Support", directoryHint: .isDirectory)
        #expect(AgentSocket.defaultPath(applicationSupport: support, uid: 501) == "/tmp/mynotch-501/agent.sock")
    }

    @Test func thePermissionSocketSitsBesideTheDatagramSocket() {
        #expect(AgentSocket.permissionPath(besides: "/a/b/agent.sock") == "/a/b/perm.sock")
        #expect(AgentSocket.permissionPath(besides: "/tmp/mynotch-501/agent.sock") == "/tmp/mynotch-501/perm.sock")
    }

    /// The helper picks the second path from the first, so it must fit wherever the first does.
    @Test func thePermissionSocketFitsWhereTheDatagramSocketDoes() throws {
        let folder = "/" + String(repeating: "x", count: SocketAddress.maxPathLength - "/agent.sock".utf8.count - 1)
        let datagram = folder + "/" + AgentSocket.fileName
        #expect(SocketAddress(path: datagram) != nil)
        #expect(SocketAddress(path: AgentSocket.permissionPath(besides: datagram)) != nil)
    }
}
