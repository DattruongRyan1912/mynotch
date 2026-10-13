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

    @Test func theHelperAndTheAppAgreeOnTheDefaultPath() {
        let support = URL(filePath: "/Users/example/Library/Application Support", directoryHint: .isDirectory)
        let storage = support.appending(components: "io.lucasvu.mynotch", "Modules", "aiagents", directoryHint: .isDirectory)
        #expect(AgentSocket.defaultPath(applicationSupport: support, uid: 501) == AgentSocket.path(inStorageDirectory: storage, uid: 501))
    }
}
