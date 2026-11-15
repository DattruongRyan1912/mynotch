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
        #expect(store().remove(.microsoftKey))
        #expect(store().load(.microsoftKey) == nil)
        #expect(store().load(.googleKey) == "google")
    }

    @Test func nothingIsStoredYetSoNothingIsFound() {
        #expect(store().load(.googleKey) == nil)
        #expect(!store().contains(.googleKey))
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

    @Test func removingWhatIsNotThereIsHarmlessAndSucceeds() {
        #expect(store().remove(.googleKey))
        #expect(store().load(.googleKey) == nil)
    }

    @Test func removingAKeyDeletesTheItemAndSucceeds() {
        _ = store().save("KEY", for: .googleKey)
        #expect(store().remove(.googleKey))
        #expect(keychain.stored.isEmpty)
        #expect(store().load(.googleKey) == nil)
    }

    /// A refused delete (a locked keychain, a denied prompt) leaves the key where it was, and says so.
    @Test(arguments: [errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled])
    func aDeleteThatIsRefusedIsReportedAndTheKeyStays(_ status: OSStatus) {
        _ = store().save("KEY", for: .googleKey)
        keychain.failsToDelete = status
        #expect(!store().remove(.googleKey))
        #expect(store().load(.googleKey) == "KEY")
    }

    @Test func savedKeysAreFoundWithoutReadingTheirValues() {
        _ = store().save("KEY", for: .googleKey)
        #expect(store().contains(.googleKey))
        #expect(!store().contains(.microsoftKey))
        #expect(keychain.copyCount == 0)
        #expect(keychain.existenceQueries.count == 2)
        for query in keychain.existenceQueries {
            #expect(query[kSecReturnData as String] == nil)
            #expect(query[kSecReturnAttributes as String] as? Bool == true)
            #expect(query[kSecAttrService as String] as? String == "io.lucasvu.mynotch.translation")
        }
    }

    @Test func aKeychainThatCannotAnswerHasNoKeyToShow() {
        _ = store().save("KEY", for: .googleKey)
        keychain.failsToAnswer = errSecInteractionNotAllowed
        #expect(!store().contains(.googleKey))
    }
}
