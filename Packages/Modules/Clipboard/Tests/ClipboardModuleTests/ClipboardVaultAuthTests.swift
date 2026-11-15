import Foundation
import LocalAuthentication
import Testing
@testable import ClipboardModule

/// Touch ID with the device password behind it, through fakes: no test reaches the real LocalAuthentication or the Keychain.
@Suite struct ClipboardVaultAuthTests {
    /// The contexts a authenticator asked for, in order.
    final class Contexts {
        var made: [FakeLAContext] = []
        let scripts: [FakeLAContext]

        init(_ scripts: [FakeLAContext]) {
            self.scripts = scripts
        }

        func next() -> FakeLAContext {
            let context = scripts[min(made.count, scripts.count - 1)]
            made.append(context)
            return context
        }
    }

    func authenticator(_ contexts: Contexts) -> SystemUserAuthenticator {
        SystemUserAuthenticator(makeContext: { contexts.next() })
    }

    @Test func touchIDIsAskedFirstAndAloneWhenItWorks() async throws {
        let touch = FakeLAContext(biometrics: .success)
        let contexts = Contexts([touch])
        let result = try await authenticator(contexts).authenticate(reason: "Mở khoá bảng")

        #expect(touch.evaluated == [.deviceOwnerAuthenticationWithBiometrics])
        #expect(touch.reasons == ["Mở khoá bảng"])
        #expect(contexts.made.count == 1)
        #expect(result.context === touch)
        // The fallback button of the Touch ID dialog is shown, so the user can choose the device password.
        #expect(touch.localizedFallbackTitle?.isEmpty == false)
    }

    @Test func theDevicePasswordIsUsedWhenThereIsNoTouchID() async throws {
        let first = FakeLAContext(biometrics: .unavailable)
        let second = FakeLAContext(owner: .success)
        let contexts = Contexts([first, second])
        let result = try await authenticator(contexts).authenticate(reason: "x")

        #expect(first.evaluated.isEmpty)
        #expect(second.evaluated == [.deviceOwnerAuthentication])
        #expect(result.context === second)
    }

    @Test(arguments: [LAError.Code.userFallback, .biometryLockout, .biometryNotEnrolled, .authenticationFailed, .biometryNotAvailable])
    func theDevicePasswordFollowsWhenTouchIDDoesNotSucceed(code: LAError.Code) async throws {
        let first = FakeLAContext(biometrics: .fail(code))
        let second = FakeLAContext(owner: .success)
        let contexts = Contexts([first, second])
        let result = try await authenticator(contexts).authenticate(reason: "x")

        #expect(first.evaluated == [.deviceOwnerAuthenticationWithBiometrics])
        #expect(second.evaluated == [.deviceOwnerAuthentication])
        // A context that has failed is not used again.
        #expect(first !== second)
        #expect(result.context === second)
    }

    @Test(arguments: [LAError.Code.userCancel, .systemCancel, .appCancel])
    func dismissingTouchIDEndsItWithoutAskingForThePassword(code: LAError.Code) async {
        let first = FakeLAContext(biometrics: .fail(code))
        let second = FakeLAContext(owner: .success)
        let contexts = Contexts([first, second])

        await #expect(throws: ClipboardVaultError.cancelled) { _ = try await authenticator(contexts).authenticate(reason: "x") }
        #expect(second.evaluated.isEmpty)
        #expect(contexts.made.count == 1)
    }

    @Test func dismissingTheDevicePasswordIsACancel() async {
        let contexts = Contexts([FakeLAContext(biometrics: .unavailable), FakeLAContext(owner: .fail(.userCancel))])
        await #expect(throws: ClipboardVaultError.cancelled) { _ = try await authenticator(contexts).authenticate(reason: "x") }
    }

    @Test func aRefusedDevicePasswordIsAFailure() async {
        let contexts = Contexts([FakeLAContext(biometrics: .fail(.userFallback)), FakeLAContext(owner: .fail(.authenticationFailed))])
        await #expect(throws: ClipboardVaultError.authenticationFailed) { _ = try await authenticator(contexts).authenticate(reason: "x") }
    }

    @Test func nothingToAskWithIsAFailure() async {
        let contexts = Contexts([FakeLAContext(biometrics: .unavailable, owner: .unavailable)])
        await #expect(throws: ClipboardVaultError.authenticationFailed) { _ = try await authenticator(contexts).authenticate(reason: "x") }
    }

    // MARK: The fake Keychain stands for the real one

    @Test func theFakeKeychainKeepsAKeyOnlyForAnAuthenticatedUser() async throws {
        let keychain = FakeBoardKeychain()
        let board = UUID()
        try keychain.store(Data([1, 2, 3]), for: board)

        #expect(throws: ClipboardVaultError.authenticationFailed) {
            _ = try keychain.load(for: board, authentication: UserAuthentication(context: nil))
        }
        let authentication = try await FakeAuthenticator().authenticate(reason: "x")
        #expect(try keychain.load(for: board, authentication: authentication) == Data([1, 2, 3]))
        try keychain.remove(for: board)
        #expect(throws: ClipboardVaultError.keyMissing) { _ = try keychain.load(for: board, authentication: authentication) }
    }
}
