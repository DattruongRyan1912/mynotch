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

    // MARK: - CloudSync V2 (Authenticated with AAD)

    /// Computes the exact canonical AAD for CloudSync V2.
    public static func computeAAD(id: String, senderId: String, timestamp: Int64) -> Data {
        Data("mynotch\nclip_v2\n2\n\(id)\n\(senderId)\n\(timestamp)".utf8)
    }

    /// Encrypts raw plaintext data into a CloudSyncEnvelopeV2 with fresh Nonce and AAD.
    public static func encryptV2(
        plaintext: Data,
        using key: SymmetricKey,
        senderId: String,
        id: String = UUID().uuidString.lowercased(),
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        customNonce: Data? = nil
    ) throws -> CloudSyncEnvelopeV2 {
        let nonce: AES.GCM.Nonce
        if let customNonce {
            nonce = try AES.GCM.Nonce(data: customNonce)
        } else {
            nonce = AES.GCM.Nonce()
        }

        let aad = computeAAD(id: id, senderId: senderId, timestamp: timestamp)
        guard let sealedBox = try? AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: aad) else {
            throw CryptoError.encryptionFailed
        }

        return CloudSyncEnvelopeV2(
            type: "clip_v2",
            v: 2,
            id: id,
            senderId: senderId,
            timestamp: timestamp,
            nonce: Data(sealedBox.nonce).base64EncodedString(),
            tag: sealedBox.tag.base64EncodedString(),
            ciphertext: sealedBox.ciphertext.base64EncodedString()
        )
    }

    /// Decrypts a CloudSyncEnvelopeV2 verifying AAD and returns the decrypted raw plaintext data.
    public static func decryptV2(
        envelope: CloudSyncEnvelopeV2,
        using key: SymmetricKey
    ) throws -> Data {
        guard envelope.type == "clip_v2", envelope.v == 2 else {
            throw CryptoError.invalidEnvelope
        }
        guard let nonceData = Data(base64Encoded: envelope.nonce),
              let tagData = Data(base64Encoded: envelope.tag),
              let ciphertextData = Data(base64Encoded: envelope.ciphertext) else {
            throw CryptoError.invalidEnvelope
        }

        let nonce = try AES.GCM.Nonce(data: nonceData)
        let aad = computeAAD(id: envelope.id, senderId: envelope.senderId, timestamp: envelope.timestamp)

        guard let sealedBox = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertextData, tag: tagData),
              let decryptedData = try? AES.GCM.open(sealedBox, using: key, authenticating: aad) else {
            throw CryptoError.decryptionFailed
        }

        return decryptedData
    }
}
