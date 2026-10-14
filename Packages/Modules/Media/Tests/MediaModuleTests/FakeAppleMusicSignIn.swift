import Foundation
@testable import MediaModule

/// Stands in for the sign-in window, so no test opens a web view or touches web data.
final class FakeAppleMusicSignIn: AppleMusicSignIn {
    private(set) var openCount = 0
    private(set) var closeCount = 0
    private(set) var removeCount = 0
    private var connect: ((AppleMusicCredentials) async -> Bool)?

    func open(connect: @escaping (AppleMusicCredentials) async -> Bool) {
        openCount += 1
        self.connect = connect
    }

    func close() {
        closeCount += 1
        connect = nil
    }

    func removeWebsiteData() async {
        removeCount += 1
    }

    /// The user signed in and the window found these; whether the app accepted them.
    func found(_ credentials: AppleMusicCredentials) async -> Bool {
        await connect?(credentials) ?? false
    }
}
