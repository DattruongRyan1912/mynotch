import Foundation
import Security

/// What is kept about the user's Apple Music sign-in. The raw values are the Keychain account names.
nonisolated enum AppleMusicSecret: String, CaseIterable, Sendable {
    case developerToken = "developer-token"
    case mediaUserToken = "media-user-token"
    case storefront
}

/// Where the sign-in lives. A protocol so tests use an in-memory fake and never touch the real Keychain.
protocol TokenStore {
    func load(_ secret: AppleMusicSecret) -> String?
    /// False when the value could not be kept.
    func save(_ value: String, for secret: AppleMusicSecret) -> Bool
    func remove(_ secret: AppleMusicSecret)
}

/// The Keychain of this Mac: generic passwords of one service, readable only on this device once it has been
/// unlocked after a restart, never synced to iCloud (lookups leave `kSecAttrSynchronizable` out, which matches only
/// items that are not synced). Nothing here logs or reports a value, only a success flag.
struct KeychainTokenStore: TokenStore {
    static let service = "io.lucasvu.mynotch.applemusic"

    func load(_ secret: AppleMusicSecret) -> String? {
        var query = query(for: secret)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ value: String, for secret: AppleMusicSecret) -> Bool {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(for: secret) as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item = query(for: secret)
        item[kSecValueData] = data
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecAttrSynchronizable] = false
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    func remove(_ secret: AppleMusicSecret) {
        SecItemDelete(query(for: secret) as CFDictionary)
    }

    private func query(for secret: AppleMusicSecret) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: secret.rawValue,
        ]
    }
}
