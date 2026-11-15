import CryptoKit
import Foundation
import Testing
@testable import ClipboardModule

@Suite struct CloudSyncCryptoTests {
    @Test func generateAndExportImportKey() throws {
        let key = CloudSyncCrypto.generateKey()
        let exportedBase64 = CloudSyncCrypto.exportKeyBase64(key)
        #expect(!exportedBase64.isEmpty)

        let importedKey = try CloudSyncCrypto.importKeyBase64(exportedBase64)
        let reExported = CloudSyncCrypto.exportKeyBase64(importedKey)
        #expect(exportedBase64 == reExported)
    }

    @Test func encryptAndDecryptPlainText() throws {
        let key = CloudSyncCrypto.generateKey()
        let originalText = "Xin chào Android từ macOS MyNotch! 🚀"
        let payload = CloudSyncPayload(format: .plainText, content: originalText, sourceApp: "Xcode")

        let envelope = try CloudSyncCrypto.encrypt(payload: payload, using: key, senderId: "macbook")
        #expect(envelope.senderId == "macbook")
        #expect(!envelope.nonce.isEmpty)
        #expect(!envelope.tag.isEmpty)
        #expect(!envelope.ciphertext.isEmpty)

        let decrypted = try CloudSyncCrypto.decrypt(envelope: envelope, using: key)
        #expect(decrypted.content == originalText)
        #expect(decrypted.format == .plainText)
        #expect(decrypted.sourceApp == "Xcode")
    }

    @Test func nonceIsAlwaysUniqueBetweenMessages() throws {
        let key = CloudSyncCrypto.generateKey()
        let payload = CloudSyncPayload(format: .plainText, content: "Test nonces")

        let env1 = try CloudSyncCrypto.encrypt(payload: payload, using: key, senderId: "macbook")
        let env2 = try CloudSyncCrypto.encrypt(payload: payload, using: key, senderId: "macbook")

        // Ensure CSPRNG generates distinct 12-byte nonces to eliminate Nonce Reuse Hazard
        #expect(env1.nonce != env2.nonce)
        #expect(env1.ciphertext != env2.ciphertext)
    }

    @Test func decryptionFailsWithWrongKey() throws {
        let key1 = CloudSyncCrypto.generateKey()
        let key2 = CloudSyncCrypto.generateKey()
        let payload = CloudSyncPayload(format: .plainText, content: "Bí mật")

        let envelope = try CloudSyncCrypto.encrypt(payload: payload, using: key1, senderId: "macbook")

        #expect(throws: CloudSyncCrypto.CryptoError.self) {
            _ = try CloudSyncCrypto.decrypt(envelope: envelope, using: key2)
        }
    }

    @Test func pairingConfigGeneratesValidUriAndQRCode() {
        let config = CloudSyncConfig(
            isEnabled: true,
            channelId: "test-channel-12345",
            authToken: "auth-token-67890",
            relayServerUrl: "wss://relay.mynotch.app/ws"
        )

        let uri = config.pairingUri
        #expect(uri.contains("mynotch://pair"))
        #expect(uri.contains("c=test-channel-12345"))
        #expect(uri.contains("k=auth-token-67890"))

        let qrImage = CloudSyncPairingHelper.generateQRCodeImage(from: uri)
        #expect(qrImage != nil)
    }
}
