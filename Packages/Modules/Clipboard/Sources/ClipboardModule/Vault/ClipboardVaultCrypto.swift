import CommonCrypto
import CryptoKit
import Foundation

/// The cryptography of a locked board, as pure functions. A random 256-bit board key encrypts the items with AES-GCM
/// (CryptoKit); that key is either wrapped by a key derived from the user's password (PBKDF2-HMAC-SHA256 through CommonCrypto,
/// since CryptoKit has no password hashing) or kept in the Keychain behind Touch ID. Every sealed blob is bound to its board
/// and, for the items, to the item count the file shows, so a blob cannot be moved to another board or given another label.
/// Nothing here logs or prints a key, a password or a decrypted byte.
nonisolated enum ClipboardVaultCrypto {
    /// How many rounds of PBKDF2 a derivation takes, and the fewest a file may claim.
    struct Derivation: Sendable, Equatable {
        var iterations: Int
        /// A file that claims fewer rounds is refused: it was not made by this app or has been edited.
        var minimumIterations: Int

        /// More than any file is refused as well, so an edited count cannot hang the app.
        static let maximumIterations = 10_000_000
        /// OWASP's figure for PBKDF2-HMAC-SHA256.
        static let standard = Derivation(iterations: 600_000, minimumIterations: 600_000)
    }

    /// What a password derivation made and what is stored of it.
    struct PasswordWrapping: Sendable {
        var key: SymmetricKey
        var derivation: ClipboardVaultEnvelope.Derivation
        var wrappedKey: Data
    }

    static let saltLength = 32
    static let keyLength = 32

    static func randomKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    static func randomSalt() -> Data {
        Data((0..<saltLength).map { _ in UInt8.random(in: .min ... .max) })
    }

    /// PBKDF2-HMAC-SHA256 of the password (in canonical composed form, so the same letters typed in a different Unicode form
    /// are the same password), 32 bytes. Slow on purpose: call it off the main actor.
    static func deriveKey(password: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        var passwordBytes = Array(password.precomposedStringWithCanonicalMapping.utf8)
        defer { passwordBytes.withUnsafeMutableBytes { _ = memset_s($0.baseAddress, $0.count, 0, $0.count) } }
        guard !passwordBytes.isEmpty, iterations > 0, iterations <= Int(UInt32.max) else { throw ClipboardVaultError.wrongPassword }
        var derived = [UInt8](repeating: 0, count: keyLength)
        defer { derived.withUnsafeMutableBytes { _ = memset_s($0.baseAddress, $0.count, 0, $0.count) } }
        let status = passwordBytes.withUnsafeBufferPointer { password in
            salt.withUnsafeBytes { salt in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    password.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: Int8.self) }, password.count,
                    salt.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                    &derived, derived.count
                )
            }
        }
        guard status == kCCSuccess else { throw ClipboardVaultError.cannotWrite("key derivation") }
        return SymmetricKey(data: derived)
    }

    // MARK: Sealing

    /// AES-GCM with a fresh random 96-bit nonce; the result is nonce, ciphertext and tag in one blob.
    static func seal(_ plaintext: Data, using key: SymmetricKey, boardID: UUID, itemCount: Int) throws -> Data {
        try combined(plaintext, using: key, authenticating: payloadContext(boardID: boardID, itemCount: itemCount))
    }

    /// Throws `.damaged` for anything that does not pass the check: a flipped bit, a short blob, the wrong key, another board.
    static func open(_ sealed: Data, using key: SymmetricKey, boardID: UUID, itemCount: Int) throws -> Data {
        do {
            return try openCombined(sealed, using: key, authenticating: payloadContext(boardID: boardID, itemCount: itemCount))
        } catch {
            throw ClipboardVaultError.damaged
        }
    }

    // MARK: The board key and a password

    /// A new random board key, wrapped by a key from `password` and a new random salt. Slow: off the main actor.
    static func wrapNewKey(password: String, boardID: UUID, using derivation: Derivation) throws -> PasswordWrapping {
        let salt = randomSalt()
        let wrapper = try deriveKey(password: password, salt: salt, iterations: derivation.iterations)
        let key = randomKey()
        let wrapped = try key.withUnsafeBytes {
            try combined(Data($0), using: wrapper, authenticating: keyContext(boardID: boardID))
        }
        return PasswordWrapping(
            key: key, derivation: ClipboardVaultEnvelope.Derivation(iterations: derivation.iterations, salt: salt), wrappedKey: wrapped
        )
    }

    /// `.damaged` for a file whose parameters this app would never have written (too few or too many rounds, a short salt),
    /// before any work; `.wrongPassword` when the password does not open the key. Slow: off the main actor.
    static func unwrapKey(
        password: String, derivation: ClipboardVaultEnvelope.Derivation, wrappedKey: Data, boardID: UUID, policy: Derivation
    ) throws -> SymmetricKey {
        guard derivation.iterations >= policy.minimumIterations, derivation.iterations <= Derivation.maximumIterations,
              derivation.salt.count >= saltLength / 2 else { throw ClipboardVaultError.damaged }
        let wrapper = try deriveKey(password: password, salt: derivation.salt, iterations: derivation.iterations)
        do {
            let opened = try openCombined(wrappedKey, using: wrapper, authenticating: keyContext(boardID: boardID))
            guard opened.count == keyLength else { throw ClipboardVaultError.wrongPassword }
            return SymmetricKey(data: opened)
        } catch {
            throw ClipboardVaultError.wrongPassword
        }
    }

    // MARK: Private

    private static func combined(_ plaintext: Data, using key: SymmetricKey, authenticating context: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(plaintext, using: key, authenticating: context).combined else {
            throw ClipboardVaultError.cannotWrite("encryption")
        }
        return combined
    }

    private static func openCombined(_ sealed: Data, using key: SymmetricKey, authenticating context: Data) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key, authenticating: context)
    }

    private static func payloadContext(boardID: UUID, itemCount: Int) -> Data {
        Data("mynotch.clipboard.vault.v1|items|\(boardID.uuidString)|\(itemCount)".utf8)
    }

    private static func keyContext(boardID: UUID) -> Data {
        Data("mynotch.clipboard.vault.v1|key|\(boardID.uuidString)".utf8)
    }
}
