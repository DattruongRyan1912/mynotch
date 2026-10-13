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
}
