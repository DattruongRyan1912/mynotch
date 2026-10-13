import Foundation
import Testing
@preconcurrency import Translation
@testable import TranslationModule

final class FakeSession: TranslatingSession {
    /// Thrown by every call when set; otherwise the session echoes the text with its pair.
    var error: (any Error)?
    let pair: LanguagePair

    init(pair: LanguagePair) { self.pair = pair }

    func translate(_ text: String) async throws -> String {
        if let error { throw error }
        return "\(text) [\(pair.source.minimalIdentifier)→\(pair.target.minimalIdentifier)]"
    }
}

final class FakeSessions: TranslationSessionProviding {
    var status: PairStatus = .installed
    /// Error the next sessions throw.
    var error: (any Error)?
    private(set) var made: [FakeSession] = []

    func status(from source: Locale.Language, to target: Locale.Language) async -> PairStatus { status }

    func makeSession(from source: Locale.Language, to target: Locale.Language) -> any TranslatingSession {
        let session = FakeSession(pair: LanguagePair(source: source, target: target))
        session.error = error
        made.append(session)
        return session
    }
}

struct Boom: LocalizedError {
    var errorDescription: String? { "Hỏng rồi" }
}

@Suite struct AppleTranslationEngineTests {
    let vi = Locale.Language(identifier: "vi")
    let en = Locale.Language(identifier: "en")

    @Test func cachesOneSessionPerPair() async throws {
        let sessions = FakeSessions()
        let engine = AppleTranslationEngine(sessions: sessions)
        #expect(try await engine.translate("xin chào", from: vi, to: en) == "xin chào [vi→en]")
        #expect(try await engine.translate("tạm biệt", from: vi, to: en) == "tạm biệt [vi→en]")
        #expect(try await engine.translate("hello", from: en, to: vi) == "hello [en→vi]")
        #expect(sessions.made.map(\.pair) == [LanguagePair(source: vi, target: en), LanguagePair(source: en, target: vi)])
    }

    @Test func missingLanguagePackIsNotInstalledAndRetriedWithAFreshSession() async throws {
        let sessions = FakeSessions()
        sessions.error = TranslationError.notInstalled
        let engine = AppleTranslationEngine(sessions: sessions)
        await #expect(throws: TranslationFailure.notInstalled) { try await engine.translate("xin chào", from: vi, to: en) }

        sessions.error = nil   // the user installed the pack
        #expect(try await engine.translate("xin chào", from: vi, to: en) == "xin chào [vi→en]")
        #expect(sessions.made.count == 2)
    }

    @Test func unsupportedLanguagesAreUnsupported() async {
        let sessions = FakeSessions()
        let engine = AppleTranslationEngine(sessions: sessions)
        for error in [TranslationError.unsupportedLanguagePairing, .unsupportedSourceLanguage, .unsupportedTargetLanguage] {
            sessions.error = error
            await #expect(throws: TranslationFailure.unsupported) { try await engine.translate("xin chào", from: vi, to: en) }
        }
        #expect(sessions.made.count == 3)
    }

    @Test func otherErrorsFailWithTheirDescriptionAndKeepTheSession() async throws {
        let sessions = FakeSessions()
        let engine = AppleTranslationEngine(sessions: sessions)
        _ = try await engine.translate("xin chào", from: vi, to: en)
        sessions.made[0].error = Boom()
        await #expect(throws: TranslationFailure.failed("Hỏng rồi")) { try await engine.translate("xin chào", from: vi, to: en) }
        #expect(sessions.made.count == 1)
    }

    @Test func statusComesFromTheSessions() async {
        let sessions = FakeSessions()
        let engine = AppleTranslationEngine(sessions: sessions)
        sessions.status = .supported
        #expect(await engine.status(from: vi, to: en) == .supported)
        sessions.status = .unsupported
        #expect(await engine.status(from: vi, to: en) == .unsupported)
    }

    @Test func mapsLanguageAvailabilityStatus() {
        #expect(PairStatus(LanguageAvailability.Status.installed) == .installed)
        #expect(PairStatus(LanguageAvailability.Status.supported) == .supported)
        #expect(PairStatus(LanguageAvailability.Status.unsupported) == .unsupported)
    }
}
