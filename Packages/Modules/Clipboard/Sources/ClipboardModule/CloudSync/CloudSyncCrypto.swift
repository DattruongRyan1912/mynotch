import CryptoKit
import Foundation

/// End-to-End Encryption (E2EE) helper using AES-256-GCM.
public enum CloudSyncCrypto {
    public enum CryptoError: Error, LocalizedError {
        case invalidKey
        case encryptionFailed
        case decryptionFailed
        case invalidEnvelope

        public var errorDescription: String? {
            switch self {
            case .invalidKey: return "Khóa mã hóa không hợp lệ (cần 32 bytes AES-256)"
            case .encryptionFailed: return "Mã hóa nội dung thất bại"
            case .decryptionFailed: return "Giải mã thất bại (sai khóa hoặc dữ liệu bị thay đổi)"
            case .invalidEnvelope: return "Dữ liệu gói tin không hợp lệ"
            }
        }
    }

    /// Generates a fresh random 256-bit AES symmetric key.
    public static func generateKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    /// Exports a symmetric key as a Base64 string.
    public static func exportKeyBase64(_ key: SymmetricKey) -> String {
        key.withUnsafeBytes { Data($0).base64EncodedString() }
    }

    /// Imports a symmetric key from a Base64 string.
    public static func importKeyBase64(_ base64: String) throws -> SymmetricKey {
        guard let data = Data(base64Encoded: base64), data.count == 32 else {
            throw CryptoError.invalidKey
        }
        return SymmetricKey(data: data)
    }

    /// Encrypts a payload into an E2EE CloudSyncEnvelope with a fresh CSPRNG Nonce.
    public static func encrypt(
        payload: CloudSyncPayload,
        using key: SymmetricKey,
        senderId: String
    ) throws -> CloudSyncEnvelope {
        let encoder = JSONEncoder()
        let plaintextData = try encoder.encode(payload)

        // Generate fresh 12-byte CSPRNG Nonce for every message (prevent Nonce Reuse Hazard)
        let nonce = AES.GCM.Nonce()

        guard let sealedBox = try? AES.GCM.seal(plaintextData, using: key, nonce: nonce) else {
            throw CryptoError.encryptionFailed
        }

        let nonceBase64 = Data(sealedBox.nonce).base64EncodedString()
        let tagBase64 = sealedBox.tag.base64EncodedString()
        let ciphertextBase64 = sealedBox.ciphertext.base64EncodedString()

        return CloudSyncEnvelope(
            senderId: senderId,
            nonce: nonceBase64,
            tag: tagBase64,
            ciphertext: ciphertextBase64
        )
    }

    /// Decrypts an incoming CloudSyncEnvelope back into a CloudSyncPayload.
    public static func decrypt(
        envelope: CloudSyncEnvelope,
        using key: SymmetricKey
    ) throws -> CloudSyncPayload {
        guard let nonceData = Data(base64Encoded: envelope.nonce),
              let tagData = Data(base64Encoded: envelope.tag),
              let ciphertextData = Data(base64Encoded: envelope.ciphertext) else {
            throw CryptoError.invalidEnvelope
        }

        let nonce = try AES.GCM.Nonce(data: nonceData)
        guard let sealedBox = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertextData, tag: tagData),
              let decryptedData = try? AES.GCM.open(sealedBox, using: key) else {
            throw CryptoError.decryptionFailed
        }

        let decoder = JSONDecoder()
        return try decoder.decode(CloudSyncPayload.self, from: decryptedData)
    }
}
