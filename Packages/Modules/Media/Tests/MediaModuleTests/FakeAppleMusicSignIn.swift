import Foundation
@testable import MediaModule

/// Stands in for the sign-in window, so no test opens a web view or touches web data.
final class FakeAppleMusicSignIn: AppleMusicSignIn {
    private(set) var openCount = 0
    private(set) var closeCount = 0
    private(set) var removeCount = 0
    private var connect: ((AppleMusicCredentials) async -> Bool)?
    private var closed: (() async -> Void)?

    var isOpen: Bool { connect != nil }

    func open(connect: @escaping (AppleMusicCredentials) async -> Bool, closed: @escaping () async -> Void) {
        openCount += 1
        self.connect = connect
        self.closed = closed
    }

    /// The module closes the window; like the real one, it then reports that it is gone.
    func close() {
        closeCount += 1
        let closed = closed
        connect = nil
        self.closed = nil
        if let closed { Task { await closed() } }
    }

    func removeWebsiteData() async {
        removeCount += 1
    }

    /// The user signed in and the window found these; whether the app accepted them.
    func found(_ credentials: AppleMusicCredentials) async -> Bool {
        await connect?(credentials) ?? false
    }

    /// The user closes the window, or it closes itself after `found`.
    func windowClosed() async {
        let closed = closed
        connect = nil
        self.closed = nil
        await closed?()
    }
}
