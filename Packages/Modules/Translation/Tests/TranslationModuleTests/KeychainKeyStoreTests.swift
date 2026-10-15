import Foundation
import Security
import Testing
@testable import TranslationModule

/// The Keychain wrapper, against a fake that answers like the Keychain: no test touches the real one.
@Suite struct KeychainKeyStoreTests {
    let keychain = FakeKeychain()

    func store() -> KeychainKeyStore { KeychainKeyStore(keychain: keychain) }

    @Test func aKeyIsKeptAndReadBack() {
        #expect(store().save("KEY-123", for: .googleKey))
        #expect(store().load(.googleKey) == "KEY-123")
    }

    @Test func eachEngineHasItsOwnItem() {
        _ = store().save("google", for: .googleKey)
        _ = store().save("microsoft", for: .microsoftKey)
        _ = store().save("openai", for: .openAIKey)
        #expect(store().load(.googleKey) == "google")
        #expect(store().load(.microsoftKey) == "microsoft")
        #expect(store().load(.openAIKey) == "openai")
        store().remove(.microsoftKey)
        #expect(store().load(.microsoftKey) == nil)
        #expect(store().load(.googleKey) == "google")
    }

    @Test func nothingIsStoredYetSoNothingIsFound() {
        #expect(store().load(.googleKey) == nil)
    }

    @Test func savingAgainReplacesTheKeyInPlace() {
        _ = store().save("old", for: .openAIKey)
        #expect(store().save("new", for: .openAIKey))
        #expect(store().load(.openAIKey) == "new")
        #expect(keychain.addCount == 1)
        #expect(keychain.stored.count == 1)
    }

    @Test func theItemIsAGenericPasswordOfTheTranslationServiceThatStaysOnThisMac() throws {
        _ = store().save("KEY", for: .googleKey)
        let item = try #require(keychain.added.first)
        #expect(KeychainKeyStore.service == "io.lucasvu.mynotch.translation")
        #expect(item[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(item[kSecAttrService as String] as? String == "io.lucasvu.mynotch.translation")
        #expect(item[kSecAttrAccount as String] as? String == "google-api-key")
        #expect(item[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect(item[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(item[kSecValueData as String] as? Data == Data("KEY".utf8))
    }

    @Test func theAccountNamesAreStable() {
        #expect(TranslationSecret.allCases.map(\.rawValue) == ["google-api-key", "microsoft-key", "openai-key"])
    }

    @Test func aKeychainThatRefusesIsReportedAndKeepsNothing() {
        keychain.failsToAdd = errSecInteractionNotAllowed
        #expect(!store().save("KEY", for: .googleKey))
        #expect(store().load(.googleKey) == nil)
    }

    @Test func removingWhatIsNotThereIsHarmless() {
        store().remove(.googleKey)
        #expect(store().load(.googleKey) == nil)
    }
}
