import Foundation
import LocalSocketKit

extension AgentEventServer.StartError {
    /// Makes `directory` the user's own and closed to everyone else, or throws why that cannot be.
    static func preparePrivateDirectory(_ directory: URL) throws {
        do {
            try PrivateDirectory.prepare(directory)
        } catch PrivateDirectory.Failure.notOwned {
            throw directoryNotOwned
        } catch PrivateDirectory.Failure.system(let code) {
            throw socket(errno: code)
        }
    }
}
