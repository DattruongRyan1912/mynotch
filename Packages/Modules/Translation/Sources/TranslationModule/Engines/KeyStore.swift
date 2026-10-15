import Foundation
import Security

/// A key the user typed in. The raw values are the Keychain account names.
nonisolated enum TranslationSecret: String, CaseIterable, Sendable {
    case googleKey = "google-api-key"
    case microsoftKey = "microsoft-key"
    case openAIKey = "openai-key"
}

/// Where the keys live: never in the settings, only here. A protocol so tests use an in-memory fake and never touch
/// the real Keychain.
nonisolated protocol KeyStore: Sendable {
    func load(_ secret: TranslationSecret) -> String?
    /// Whether a key is saved, without reading it: the Settings rows only need to know that.
    func contains(_ secret: TranslationSecret) -> Bool
    /// False when the key could not be kept.
    func save(_ value: String, for secret: TranslationSecret) -> Bool
    /// False when the key could not be deleted and is still there; true also when there was none.
    func remove(_ secret: TranslationSecret) -> Bool
}

/// The Keychain calls the store makes, so tests can answer them without the Keychain.
nonisolated protocol KeychainAccess: Sendable {
    func copy(_ query: [CFString: Any]) -> (status: OSStatus, data: Data?)
    /// Whether the query finds an item; the query asks for attributes only, so no secret is read.
    func exists(_ query: [CFString: Any]) -> OSStatus
    func add(_ item: [CFString: Any]) -> OSStatus
    func update(_ query: [CFString: Any], with attributes: [CFString: Any]) -> OSStatus
    func delete(_ query: [CFString: Any]) -> OSStatus
}

nonisolated struct SystemKeychain: KeychainAccess {
    func copy(_ query: [CFString: Any]) -> (status: OSStatus, data: Data?) {
        var query = query
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, status == errSecSuccess ? result as? Data : nil)
    }

    func exists(_ query: [CFString: Any]) -> OSStatus {
        var result: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &result)
    }

    func add(_ item: [CFString: Any]) -> OSStatus {
        SecItemAdd(item as CFDictionary, nil)
    }

    func update(_ query: [CFString: Any], with attributes: [CFString: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func delete(_ query: [CFString: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

/// The Keychain of this Mac: generic passwords of one service, marked for this device only and never synced to iCloud
/// (lookups leave `kSecAttrSynchronizable` out, which matches only items that are not synced). On the login keychain
/// the item's access list, not that mark, is what keeps other apps out. Nothing here logs or reports a value, only a
/// success flag.
nonisolated struct KeychainKeyStore: KeyStore {
    static let service = "io.lucasvu.mynotch.translation"

    var keychain: any KeychainAccess = SystemKeychain()

    func load(_ secret: TranslationSecret) -> String? {
        let (status, data) = keychain.copy(query(for: secret))
        guard status == errSecSuccess, let data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ value: String, for secret: TranslationSecret) -> Bool {
        let data = Data(value.utf8)
        let status = keychain.update(query(for: secret), with: [kSecValueData: data])
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item = query(for: secret)
        item[kSecValueData] = data
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecAttrSynchronizable] = false
        return keychain.add(item) == errSecSuccess
    }

    func contains(_ secret: TranslationSecret) -> Bool {
        var query = query(for: secret)
        query[kSecReturnAttributes] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        return keychain.exists(query) == errSecSuccess
    }

    func remove(_ secret: TranslationSecret) -> Bool {
        let status = keychain.delete(query(for: secret))
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private func query(for secret: TranslationSecret) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: secret.rawValue,
        ]
    }
}

/// The Keychain can be slow to answer (a locked keychain, a first access), so these run off the main actor.
nonisolated extension KeyStore {
    /// The saved key, trimmed; nil when there is none or it is blank.
    @concurrent func savedKey(_ secret: TranslationSecret) async -> String? {
        guard let key = load(secret)?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return nil }
        return key
    }

    @concurrent func keep(_ key: String, as secret: TranslationSecret) async -> Bool {
        save(key, for: secret)
    }

    @concurrent func hasSavedKey(_ secret: TranslationSecret) async -> Bool {
        contains(secret)
    }

    @concurrent func discard(_ secret: TranslationSecret) async -> Bool {
        remove(secret)
    }
}
