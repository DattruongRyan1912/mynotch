import CryptoKit
import Foundation
import Testing
@testable import ClipboardModule

/// The cryptography of a locked board: key derivation from a password, wrapping of the board key, and AES-GCM sealing.
/// Everything here uses made-up passwords and keys; nothing is printed.
@Suite struct ClipboardVaultCryptoTests {
    /// A few thousand rounds instead of 600,000, so the suite stays quick; `standard` is checked once, by its parameters.
    static let fast = ClipboardVaultCrypto.Derivation(iterations: 1_000, minimumIterations: 1_000)
    static let boardID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    static func bytes(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }

    // MARK: Key derivation

    @Test func theStandardParametersAreStrongEnough() {
        let standard = ClipboardVaultCrypto.Derivation.standard
        #expect(standard.iterations >= 600_000)
        #expect(standard.minimumIterations >= 600_000)
        #expect(standard.minimumIterations <= standard.iterations)
        #expect(ClipboardVaultCrypto.saltLength >= 16)
        #expect(ClipboardVaultCrypto.Derivation.maximumIterations >= standard.iterations)
    }

    @Test(arguments: [
        (1, "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b"),
        (2, "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43"),
        (4096, "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a"),
    ])
    func derivationMatchesPBKDF2HMACSHA256KnownAnswers(iterations: Int, expected: String) throws {
        let key = try ClipboardVaultCrypto.deriveKey(password: "password", salt: Data("salt".utf8), iterations: iterations)
        #expect(Self.bytes(key).map { String(format: "%02x", $0) }.joined() == expected)
    }

    @Test func theDerivedKeyIsAFullAES256Key() throws {
        let key = try ClipboardVaultCrypto.deriveKey(password: "mật khẩu dài", salt: Data(repeating: 7, count: 16), iterations: 10)
        #expect(Self.bytes(key).count == 32)
    }

    @Test func derivationDependsOnEveryInput() throws {
        let salt = Data(repeating: 1, count: 16)
        let base = Self.bytes(try ClipboardVaultCrypto.deriveKey(password: "mật khẩu 1", salt: salt, iterations: 50))
        // Compared as plain answers, so a failure never prints a key.
        func same(_ key: SymmetricKey) -> Bool { Self.bytes(key) == base }
        #expect(same(try ClipboardVaultCrypto.deriveKey(password: "mật khẩu 1", salt: salt, iterations: 50)))
        #expect(!same(try ClipboardVaultCrypto.deriveKey(password: "mật khẩu 2", salt: salt, iterations: 50)))
        #expect(!same(try ClipboardVaultCrypto.deriveKey(password: "mật khẩu 1", salt: Data(repeating: 2, count: 16), iterations: 50)))
        #expect(!same(try ClipboardVaultCrypto.deriveKey(password: "mật khẩu 1", salt: salt, iterations: 51)))
    }

    @Test func aPasswordTypedWithComposedOrDecomposedLettersIsTheSame() throws {
        let composed = "Việt Nam 2026"
        let decomposed = composed.decomposedStringWithCanonicalMapping
        #expect(composed.unicodeScalars.count != decomposed.unicodeScalars.count)
        let salt = Data(repeating: 3, count: 16)
        let first = Self.bytes(try ClipboardVaultCrypto.deriveKey(password: composed, salt: salt, iterations: 20))
        let second = Self.bytes(try ClipboardVaultCrypto.deriveKey(password: decomposed, salt: salt, iterations: 20))
        let equal = first == second
        #expect(equal)
    }

    @Test func anEmptyPasswordIsRefused() {
        #expect(throws: ClipboardVaultError.wrongPassword) {
            try ClipboardVaultCrypto.deriveKey(password: "", salt: Data(repeating: 1, count: 16), iterations: 10)
        }
    }

    @Test func saltsAreRandomAndLongEnough() {
        let salts = (0..<20).map { _ in ClipboardVaultCrypto.randomSalt() }
        #expect(Set(salts).count == 20)
        #expect(salts.allSatisfy { $0.count == ClipboardVaultCrypto.saltLength })
    }

    @Test func theStandardDerivationRunsAtItsFullCost() throws {
        // Once, for real: the number of rounds is the whole defence of a password, so it is not left to the fast tests.
        let clock = ContinuousClock()
        var key: SymmetricKey?
        let elapsed = try clock.measure {
            key = try ClipboardVaultCrypto.deriveKey(
                password: "một mật khẩu", salt: ClipboardVaultCrypto.randomSalt(), iterations: ClipboardVaultCrypto.Derivation.standard.iterations
            )
        }
        #expect(key != nil)
        // 600,000 rounds of HMAC-SHA256 cannot take a millisecond; a derivation that skipped them would.
        #expect(elapsed > .milliseconds(20))
    }

    // MARK: Sealing

    @Test func aSealedPayloadOpensToTheSameBytes() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data("nội dung bí mật, 12345 — £€".utf8)
        let sealed = try ClipboardVaultCrypto.seal(plaintext, using: key, boardID: Self.boardID, itemCount: 3)
        #expect(try ClipboardVaultCrypto.open(sealed, using: key, boardID: Self.boardID, itemCount: 3) == plaintext)
    }

    @Test func aSealedPayloadHoldsNoPlaintext() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data(String(repeating: "mật-khẩu-của-tôi ", count: 50).utf8)
        let sealed = try ClipboardVaultCrypto.seal(plaintext, using: key, boardID: Self.boardID, itemCount: 1)
        #expect(sealed.range(of: Data("mật-khẩu".utf8)) == nil)
        #expect(sealed.count == plaintext.count + 12 + 16)
    }

    @Test func eachSealUsesANewRandomNonce() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data("cùng một nội dung".utf8)
        let sealed = try (0..<50).map { _ in try ClipboardVaultCrypto.seal(plaintext, using: key, boardID: Self.boardID, itemCount: 1) }
        #expect(Set(sealed.map { $0.prefix(12) }).count == 50)
        #expect(Set(sealed).count == 50)
    }

    @Test func aFlippedBitAnywhereIsDetected() throws {
        let key = SymmetricKey(size: .bits256)
        let sealed = try ClipboardVaultCrypto.seal(Data("0123456789abcdef0123".utf8), using: key, boardID: Self.boardID, itemCount: 1)
        // The nonce, the ciphertext and the tag: every byte is covered.
        for index in sealed.indices {
            var damaged = sealed
            damaged[index] ^= 0x01
            #expect(throws: ClipboardVaultError.damaged) {
                try ClipboardVaultCrypto.open(damaged, using: key, boardID: Self.boardID, itemCount: 1)
            }
        }
    }

    @Test func aTruncatedOrExtendedPayloadIsDetected() throws {
        let key = SymmetricKey(size: .bits256)
        let sealed = try ClipboardVaultCrypto.seal(Data("0123456789".utf8), using: key, boardID: Self.boardID, itemCount: 1)
        for damaged in [sealed.dropLast(), sealed.dropFirst(), sealed + Data([0]), Data(), Data(sealed.prefix(20))] {
            #expect(throws: ClipboardVaultError.damaged) {
                try ClipboardVaultCrypto.open(Data(damaged), using: key, boardID: Self.boardID, itemCount: 1)
            }
        }
    }

    @Test func aWrongKeyDoesNotOpenIt() throws {
        let sealed = try ClipboardVaultCrypto.seal(Data("x".utf8), using: SymmetricKey(size: .bits256), boardID: Self.boardID, itemCount: 1)
        #expect(throws: ClipboardVaultError.damaged) {
            try ClipboardVaultCrypto.open(sealed, using: SymmetricKey(size: .bits256), boardID: Self.boardID, itemCount: 1)
        }
    }

    @Test func aPayloadCannotBeMovedToAnotherBoardOrGiveAnotherCount() throws {
        let key = SymmetricKey(size: .bits256)
        let sealed = try ClipboardVaultCrypto.seal(Data("x".utf8), using: key, boardID: Self.boardID, itemCount: 4)
        #expect(throws: ClipboardVaultError.damaged) {
            try ClipboardVaultCrypto.open(sealed, using: key, boardID: UUID(), itemCount: 4)
        }
        // The count in the file is shown while locked; a file edited to show another one no longer opens.
        #expect(throws: ClipboardVaultError.damaged) {
            try ClipboardVaultCrypto.open(sealed, using: key, boardID: Self.boardID, itemCount: 5)
        }
    }

    // MARK: Wrapping the board key

    @Test func aBoardKeyIsWrappedAndUnwrappedByThePassword() throws {
        let wrapping = try ClipboardVaultCrypto.wrapNewKey(password: "đúng mật khẩu", boardID: Self.boardID, using: Self.fast)
        #expect(wrapping.derivation.iterations == 1_000)
        #expect(wrapping.derivation.salt.count == ClipboardVaultCrypto.saltLength)
        // The wrapped key is the key under another key: 12 + 32 + 16 bytes, and not the key itself.
        #expect(wrapping.wrappedKey.count == 60)
        #expect(wrapping.wrappedKey.range(of: Self.bytes(wrapping.key)) == nil)

        let opened = try ClipboardVaultCrypto.unwrapKey(
            password: "đúng mật khẩu", derivation: wrapping.derivation, wrappedKey: wrapping.wrappedKey, boardID: Self.boardID, policy: Self.fast
        )
        let same = Self.bytes(opened) == Self.bytes(wrapping.key)
        #expect(same)
    }

    @Test func eachBoardGetsItsOwnRandomKeyAndSalt() throws {
        let first = try ClipboardVaultCrypto.wrapNewKey(password: "cùng mật khẩu", boardID: Self.boardID, using: Self.fast)
        let second = try ClipboardVaultCrypto.wrapNewKey(password: "cùng mật khẩu", boardID: Self.boardID, using: Self.fast)
        let differ = Self.bytes(first.key) != Self.bytes(second.key)
        #expect(differ)
        #expect(first.derivation.salt != second.derivation.salt)
        #expect(first.wrappedKey != second.wrappedKey)
    }

    @Test func aWrongPasswordIsToldApart() throws {
        let wrapping = try ClipboardVaultCrypto.wrapNewKey(password: "đúng mật khẩu", boardID: Self.boardID, using: Self.fast)
        #expect(throws: ClipboardVaultError.wrongPassword) {
            try ClipboardVaultCrypto.unwrapKey(
                password: "sai mật khẩu", derivation: wrapping.derivation, wrappedKey: wrapping.wrappedKey, boardID: Self.boardID, policy: Self.fast
            )
        }
    }

    @Test func aWrappedKeyCannotBeUsedForAnotherBoard() throws {
        let wrapping = try ClipboardVaultCrypto.wrapNewKey(password: "đúng mật khẩu", boardID: Self.boardID, using: Self.fast)
        #expect(throws: ClipboardVaultError.wrongPassword) {
            try ClipboardVaultCrypto.unwrapKey(
                password: "đúng mật khẩu", derivation: wrapping.derivation, wrappedKey: wrapping.wrappedKey, boardID: UUID(), policy: Self.fast
            )
        }
    }

    @Test func aDamagedWrappedKeyReadsAsAWrongPassword() throws {
        let wrapping = try ClipboardVaultCrypto.wrapNewKey(password: "đúng mật khẩu", boardID: Self.boardID, using: Self.fast)
        var damaged = wrapping.wrappedKey
        damaged[20] ^= 0xFF
        #expect(throws: ClipboardVaultError.wrongPassword) {
            try ClipboardVaultCrypto.unwrapKey(
                password: "đúng mật khẩu", derivation: wrapping.derivation, wrappedKey: damaged, boardID: Self.boardID, policy: Self.fast
            )
        }
    }

    @Test func aFileClaimingTooFewOrTooManyRoundsIsRefusedBeforeAnyWork() throws {
        let wrapping = try ClipboardVaultCrypto.wrapNewKey(password: "đúng mật khẩu", boardID: Self.boardID, using: Self.fast)
        for rounds in [0, 1, 999, ClipboardVaultCrypto.Derivation.maximumIterations + 1, Int.max] {
            var derivation = wrapping.derivation
            derivation.iterations = rounds
            #expect(throws: ClipboardVaultError.damaged) {
                try ClipboardVaultCrypto.unwrapKey(
                    password: "đúng mật khẩu", derivation: derivation, wrappedKey: wrapping.wrappedKey, boardID: Self.boardID, policy: Self.fast
                )
            }
        }
    }

    @Test func aSaltThatIsTooShortIsRefused() throws {
        let wrapping = try ClipboardVaultCrypto.wrapNewKey(password: "đúng mật khẩu", boardID: Self.boardID, using: Self.fast)
        var derivation = wrapping.derivation
        derivation.salt = Data(repeating: 1, count: 4)
        #expect(throws: ClipboardVaultError.damaged) {
            try ClipboardVaultCrypto.unwrapKey(
                password: "đúng mật khẩu", derivation: derivation, wrappedKey: wrapping.wrappedKey, boardID: Self.boardID, policy: Self.fast
            )
        }
    }

    @Test func aStrongerFileThanThisAppWritesIsStillOpened() throws {
        let stronger = ClipboardVaultCrypto.Derivation(iterations: 2_000, minimumIterations: 1_000)
        let wrapping = try ClipboardVaultCrypto.wrapNewKey(password: "đúng mật khẩu", boardID: Self.boardID, using: stronger)
        let opened = try ClipboardVaultCrypto.unwrapKey(
            password: "đúng mật khẩu", derivation: wrapping.derivation, wrappedKey: wrapping.wrappedKey, boardID: Self.boardID, policy: Self.fast
        )
        let same = Self.bytes(opened) == Self.bytes(wrapping.key)
        #expect(same)
    }

    @Test func aBoardKeyIsRandom() {
        let keys = (0..<20).map { _ in Self.bytes(ClipboardVaultCrypto.randomKey()) }
        #expect(Set(keys).count == 20)
        #expect(keys.allSatisfy { $0.count == 32 })
    }

    // MARK: Password rules

    @Test func aPasswordNeedsEightCharacters() {
        #expect(ClipboardVaultPolicy.minimumPasswordLength == 8)
        #expect(!ClipboardVaultPolicy.isAcceptable("1234567"))
        #expect(ClipboardVaultPolicy.isAcceptable("12345678"))
        // Characters, not bytes: eight Vietnamese letters are enough even though they take more bytes.
        #expect(ClipboardVaultPolicy.isAcceptable("ưưưưưưưư"))
        #expect(!ClipboardVaultPolicy.isAcceptable("ưưưưưưư"))
        #expect(!ClipboardVaultPolicy.isAcceptable("        "))
    }
}
