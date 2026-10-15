import Foundation
import LocalAuthentication
import Security

/// What a successful Touch ID or device-password check hands on, so the Keychain read that follows does not ask a second time.
struct UserAuthentication {
    /// The `LAContext` that was evaluated (nil for a fake).
    let context: AnyObject?
}

/// Asks the user to prove who they are. A protocol so tests never reach the real Touch ID.
protocol UserAuthenticating {
    /// Whether this Mac can ask for Touch ID or the device password at all; changes nothing and shows nothing.
    func canAuthenticate() -> Bool

    /// Touch ID first, and the device password when Touch ID is not there, is locked out or is set aside by the user.
    /// Throws `ClipboardVaultError.cancelled` when the user dismissed it, `.authenticationFailed` for anything else.
    func authenticate(reason: String) async throws -> UserAuthentication
}

/// Keeps the key of a Touch ID board in the Keychain, where only an authenticated user can read it back. A protocol so tests
/// use a fake store and never write to the real Keychain.
protocol BoardKeyKeychain {
    /// Whether this build can keep a key behind Touch ID here: a read-only look at the data-protection Keychain that writes nothing and
    /// shows no prompt. false when the app has no Keychain access group (-34018), or the Keychain answers anything unexpected.
    func isUsable() -> Bool
    func store(_ key: Data, for boardID: UUID) throws
    /// Throws `.keyMissing` when there is none, `.cancelled` or `.authenticationFailed` when the user is not accepted.
    func load(for boardID: UUID, authentication: UserAuthentication) throws -> Data
    /// Succeeds when there is nothing to remove.
    func remove(for boardID: UUID) throws
}

// MARK: LocalAuthentication

/// The part of `LAContext` the check uses, so the order of the two policies can be tested with a fake.
protocol LocalAuthenticationContext: AnyObject {
    var localizedFallbackTitle: String? { get set }
    func canEvaluate(_ policy: LAPolicy) -> Bool
    func evaluate(_ policy: LAPolicy, reason: String) async throws
}

extension LAContext: LocalAuthenticationContext {
    func canEvaluate(_ policy: LAPolicy) -> Bool {
        canEvaluatePolicy(policy, error: nil)
    }

    func evaluate(_ policy: LAPolicy, reason: String) async throws {
        _ = try await evaluatePolicy(policy, localizedReason: reason)
    }
}

/// Touch ID (`.deviceOwnerAuthenticationWithBiometrics`) with the device password behind it (`.deviceOwnerAuthentication`).
/// Each attempt gets a context of its own, since one that has failed is not to be used again.
struct SystemUserAuthenticator: UserAuthenticating {
    var makeContext: () -> any LocalAuthenticationContext = { LAContext() }

    func canAuthenticate() -> Bool {
        makeContext().canEvaluate(.deviceOwnerAuthentication)
    }

    func authenticate(reason: String) async throws -> UserAuthentication {
        let biometrics = makeContext()
        biometrics.localizedFallbackTitle = "Dùng mật khẩu máy"
        if biometrics.canEvaluate(.deviceOwnerAuthenticationWithBiometrics) {
            do {
                try await biometrics.evaluate(.deviceOwnerAuthenticationWithBiometrics, reason: reason)
                return UserAuthentication(context: biometrics)
            } catch {
                // A dismissed prompt is the end of it; anything else (no finger enrolled, locked out, "use password", too many
                // tries) goes on to the device password.
                if Self.isCancellation(error) { throw ClipboardVaultError.cancelled }
            }
        }
        let owner = makeContext()
        guard owner.canEvaluate(.deviceOwnerAuthentication) else { throw ClipboardVaultError.authenticationFailed }
        do {
            try await owner.evaluate(.deviceOwnerAuthentication, reason: reason)
            return UserAuthentication(context: owner)
        } catch {
            throw Self.isCancellation(error) ? ClipboardVaultError.cancelled : ClipboardVaultError.authenticationFailed
        }
    }

    private static func isCancellation(_ error: any Error) -> Bool {
        guard let error = error as? LAError else { return false }
        return [.userCancel, .systemCancel, .appCancel].contains(error.code)
    }
}

// MARK: Keychain

/// Generic passwords in the data-protection Keychain, one per board, readable only after the user is present
/// (`.userPresence`: Touch ID or the device password, which keeps working when a finger is added or removed, unlike
/// `.biometryCurrentSet`, which would make the board unopenable for good) and only on this Mac while it is unlocked. Needs the
/// app to have a Keychain access group; without one the Keychain refuses (-34018) and the user is told to use a password.
struct SystemBoardKeyKeychain: BoardKeyKeychain {
    static let service = "io.lucasvu.mynotch.clipboard.board-key"

    /// Looks for an item that is not there: not found (or found) means the Keychain can be used; -34018 or anything else means it cannot.
    func isUsable() -> Bool {
        var query = Self.query(for: UUID())
        query[kSecMatchLimit] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecItemNotFound || status == errSecSuccess
    }

    func store(_ key: Data, for boardID: UUID) throws {
        try remove(for: boardID)
        var failure: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, &failure
        ) else {
            let code = failure.map { CFErrorGetCode($0.takeRetainedValue()) } ?? CFIndex(errSecParam)
            throw ClipboardVaultError.keychain(Int32(truncatingIfNeeded: code))
        }
        var query = Self.query(for: boardID)
        query[kSecValueData] = key
        query[kSecAttrAccessControl] = access
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw ClipboardVaultError.keychain(status) }
    }

    func load(for boardID: UUID, authentication: UserAuthentication) throws -> Data {
        var query = Self.query(for: boardID)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        if let context = authentication.context as? LAContext { query[kSecUseAuthenticationContext] = context }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw ClipboardVaultError.keyMissing }
            return data
        case errSecItemNotFound: throw ClipboardVaultError.keyMissing
        case errSecUserCanceled: throw ClipboardVaultError.cancelled
        case errSecAuthFailed: throw ClipboardVaultError.authenticationFailed
        default: throw ClipboardVaultError.keychain(status)
        }
    }

    func remove(for boardID: UUID) throws {
        let status = SecItemDelete(Self.query(for: boardID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ClipboardVaultError.keychain(status) }
    }

    private static func query(for boardID: UUID) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: boardID.uuidString,
            kSecUseDataProtectionKeychain: true,
        ]
    }
}
