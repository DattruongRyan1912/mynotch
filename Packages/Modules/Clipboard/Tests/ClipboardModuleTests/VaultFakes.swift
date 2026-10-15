import Foundation
import LocalAuthentication
@testable import ClipboardModule

/// What a fake authentication hands the fake Keychain, which refuses a read without it, as the real one refuses without a user.
final class FakeAuthenticationContext {}

/// A Keychain in memory: nothing here reaches the real one.
final class FakeBoardKeychain: BoardKeyKeychain {
    private(set) var entries: [UUID: Data] = [:]
    private(set) var loadCount = 0
    private(set) var storeCount = 0
    var storeError: ClipboardVaultError?
    var loadError: ClipboardVaultError?

    func store(_ key: Data, for boardID: UUID) throws {
        storeCount += 1
        if let storeError { throw storeError }
        entries[boardID] = key
    }

    func load(for boardID: UUID, authentication: UserAuthentication) throws -> Data {
        loadCount += 1
        if let loadError { throw loadError }
        guard authentication.context is FakeAuthenticationContext else { throw ClipboardVaultError.authenticationFailed }
        guard let key = entries[boardID] else { throw ClipboardVaultError.keyMissing }
        return key
    }

    func remove(for boardID: UUID) throws {
        entries[boardID] = nil
    }
}

/// The user's answer to the Touch ID prompt, as a test sets it.
final class FakeAuthenticator: UserAuthenticating {
    var outcome: ClipboardVaultError?
    var reasons: [String] = []
    /// Awaited before the answer, so a test can keep the prompt open.
    var holdAnswer: (() async -> Void)?

    func authenticate(reason: String) async throws -> UserAuthentication {
        reasons.append(reason)
        await holdAnswer?()
        if let outcome { throw outcome }
        return UserAuthentication(context: FakeAuthenticationContext())
    }
}

/// An `LAContext` whose answers are scripted per policy.
final class FakeLAContext: LocalAuthenticationContext {
    enum Answer {
        case success
        case fail(LAError.Code)
        case unavailable
    }

    var localizedFallbackTitle: String?
    let biometrics: Answer
    let owner: Answer
    private(set) var evaluated: [LAPolicy] = []
    private(set) var reasons: [String] = []

    init(biometrics: Answer = .success, owner: Answer = .success) {
        self.biometrics = biometrics
        self.owner = owner
    }

    private func answer(for policy: LAPolicy) -> Answer {
        policy == .deviceOwnerAuthenticationWithBiometrics ? biometrics : owner
    }

    func canEvaluate(_ policy: LAPolicy) -> Bool {
        if case .unavailable = answer(for: policy) { false } else { true }
    }

    func evaluate(_ policy: LAPolicy, reason: String) async throws {
        evaluated.append(policy)
        reasons.append(reason)
        switch answer(for: policy) {
        case .success: return
        case .fail(let code): throw LAError(code)
        case .unavailable: throw LAError(.biometryNotAvailable)
        }
    }
}
