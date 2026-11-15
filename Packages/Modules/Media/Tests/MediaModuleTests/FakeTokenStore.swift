import Foundation
@testable import MediaModule

/// Stands in for the Keychain, so no test ever reads or writes it: values live in this object only.
final class FakeTokenStore: TokenStore {
    private(set) var values: [AppleMusicSecret: String] = [:]
    private(set) var saveCount = 0
    private(set) var loadCount = 0
    /// Makes every save fail, like a locked or unavailable Keychain.
    var failsToSave = false

    init(_ values: [AppleMusicSecret: String] = [:]) {
        self.values = values
    }

    /// A store holding a complete, fake sign-in.
    static func connected(storefront: String = "vn") -> FakeTokenStore {
        FakeTokenStore([.developerToken: "dev-token-fake", .mediaUserToken: "user-token-fake", .storefront: storefront])
    }

    /// Fills the store with a complete, fake sign-in.
    func signIn(storefront: String = "vn") {
        values = [.developerToken: "dev-token-fake", .mediaUserToken: "user-token-fake", .storefront: storefront]
    }

    func load(_ secret: AppleMusicSecret) -> String? {
        loadCount += 1
        return values[secret]
    }

    func save(_ value: String, for secret: AppleMusicSecret) -> Bool {
        saveCount += 1
        guard !failsToSave else { return false }
        values[secret] = value
        return true
    }

    func remove(_ secret: AppleMusicSecret) {
        values[secret] = nil
    }
}
