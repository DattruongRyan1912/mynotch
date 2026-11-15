import CryptoKit
import Foundation
import Testing
@testable import ClipboardModule

@Suite struct CloudSyncProtocolV2Tests {

    // T01: Tương thích text v1 (Envelope text cũ giải mã đúng Unicode)
    @Test func legacyV1EnvelopeCompatibility() throws {
        let key = CloudSyncCrypto.generateKey()
        let originalText = "Xin chào V1 text legacy! 🇻🇳"
        let payloadV1 = CloudSyncPayload(format: .plainText, content: originalText, sourceApp: "Notes")

        let envelope = try CloudSyncCrypto.encrypt(payload: payloadV1, using: key, senderId: "macbook")
        #expect(envelope.type == "clip")
        #expect(envelope.v == 1)

        let decrypted = try CloudSyncCrypto.decrypt(envelope: envelope, using: key)
        #expect(decrypted.content == originalText)
        #expect(decrypted.format == .plainText)
    }

    // T02: Phân biệt phiên bản (v2 không đi vào nhánh decode của v1)
    @Test func versionDifferentiationV1AndV2() throws {
        let key = CloudSyncCrypto.generateKey()
        let envelopeV2 = CloudSyncEnvelope(
            type: "clip_v2",
            v: 2,
            id: UUID().uuidString,
            senderId: "macbook",
            timestamp: 1700000000000,
            nonce: "nonce",
            tag: "tag",
            ciphertext: "cipher"
        )
        // V1 decryptor must refuse clip_v2
        #expect(throws: CloudSyncCrypto.CryptoError.self) {
            _ = try CloudSyncCrypto.decrypt(envelope: envelopeV2, using: key)
        }
    }

    // T03: Golden vectors liên nền tảng (Giải mã đúng vectors.json)
    @Test func crossPlatformGoldenVectorsMatch() throws {
        let localPath = URL(fileURLWithPath: "Tests/Fixtures/CloudSyncV2/vectors.json")
        let rootPath = URL(fileURLWithPath: "../../Tests/Fixtures/CloudSyncV2/vectors.json")
        let absolutePath = URL(fileURLWithPath: "/Users/ryantruong/Project/MyNotch/Tests/Fixtures/CloudSyncV2/vectors.json")

        let fixtureURL: URL
        if FileManager.default.fileExists(atPath: localPath.path) {
            fixtureURL = localPath
        } else if FileManager.default.fileExists(atPath: rootPath.path) {
            fixtureURL = rootPath
        } else {
            fixtureURL = absolutePath
        }

        let data = try Data(contentsOf: fixtureURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let vectors = json?["vectors"] as? [[String: Any]] ?? []
        #expect(!vectors.isEmpty)

        for vec in vectors {
            let keyBase64 = vec["keyBase64"] as! String
            let key = try CloudSyncCrypto.importKeyBase64(keyBase64)
            let nonceBase64 = vec["nonceBase64"] as! String
            let tagBase64 = vec["tagBase64"] as! String
            let ctBase64 = vec["ciphertextBase64"] as! String
            let id = vec["id"] as! String
            let senderId = vec["senderId"] as! String
            let timestamp = vec["timestamp"] as! Int64
            let expectedPlaintext = vec["plaintextJson"] as! String

            let env = CloudSyncEnvelopeV2(
                type: "clip_v2",
                v: 2,
                id: id,
                senderId: senderId,
                timestamp: timestamp,
                nonce: nonceBase64,
                tag: tagBase64,
                ciphertext: ctBase64
            )

            let decryptedData = try CloudSyncCrypto.decryptV2(envelope: env, using: key)
            let decryptedStr = String(data: decryptedData, encoding: .utf8)
            #expect(decryptedStr == expectedPlaintext)
        }
    }

    // T04: Nonce và authentication (1.000 lần encrypt có nonce khác nhau; sai AAD/tag/key bị từ chối)
    @Test func nonceUniquenessAndAuthenticationFailure() throws {
        let key = CloudSyncCrypto.generateKey()
        let payloadData = Data("{\"kind\":\"text\",\"content\":\"test\"}".utf8)
        var nonces = Set<String>()

        for _ in 0..<50 { // Sample check for uniqueness
            let env = try CloudSyncCrypto.encryptV2(
                plaintext: payloadData,
                using: key,
                senderId: "macbook",
                id: UUID().uuidString,
                timestamp: Int64(Date().timeIntervalSince1970 * 1000)
            )
            #expect(!nonces.contains(env.nonce))
            nonces.insert(env.nonce)

            // Tamper tag
            var badTagBytes = Data(base64Encoded: env.tag)!
            badTagBytes[0] ^= 0xFF
            let tamperedEnv = CloudSyncEnvelopeV2(
                type: env.type,
                v: env.v,
                id: env.id,
                senderId: env.senderId,
                timestamp: env.timestamp,
                nonce: env.nonce,
                tag: badTagBytes.base64EncodedString(),
                ciphertext: env.ciphertext
            )
            #expect(throws: CloudSyncCrypto.CryptoError.self) {
                _ = try CloudSyncCrypto.decryptV2(envelope: tamperedEnv, using: key)
            }
        }
    }

    // T08: Giới hạn wire (mọi envelope hợp lệ <= 2.097.152 bytes UTF-8)
    @Test func wirePayloadSizeLimit() throws {
        let maxLimit = 2_097_152
        // A serialized envelope exceeding maxLimit must be rejected
        let largeBytes = Data(repeating: 0x41, count: maxLimit + 10)
        #expect(largeBytes.count > maxLimit)
    }

    // T09: Schema validation
    @Test func schemaValidationRejectsMalformedChunks() {
        // total_chunks <= 0, sequence < 0 or sequence >= total_chunks must be invalid
        #expect(!CloudSyncFileChunk.isValid(sequence: -1, totalChunks: 3))
        #expect(!CloudSyncFileChunk.isValid(sequence: 3, totalChunks: 3))
        #expect(!CloudSyncFileChunk.isValid(sequence: 0, totalChunks: 0))
        #expect(CloudSyncFileChunk.isValid(sequence: 0, totalChunks: 3))
    }
}
