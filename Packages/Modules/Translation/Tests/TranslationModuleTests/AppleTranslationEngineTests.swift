import Foundation
import Testing
import Translation
@testable import TranslationModule

final class FakeSession: TranslatingSession {
    let pair: LanguagePair
    /// Thrown by every call when set; otherwise the session echoes the text with its pair.
    var error: (any Error)?
    /// When true, translations wait for `release()`.
    var holds = false
    private(set) var requests: [String] = []
    private(set) var running = 0
    private(set) var mostRunning = 0
    private(set) var isCancelled = false
    private var held: [CheckedContinuation<Void, Never>] = []

    init(pair: LanguagePair) { self.pair = pair }

    var waiting: Int { held.count }

    func translate(_ text: String) async throws -> String {
        requests.append(text)
        running += 1
        mostRunning = max(mostRunning, running)
        defer { running -= 1 }
        if holds { await withCheckedContinuation { held.append($0) } }
        if let error { throw error }
        return "\(text) [\(pair.source.minimalIdentifier)→\(pair.target.minimalIdentifier)]"
    }

    func cancel() { isCancelled = true }

    func release() {
        let continuations = held
        held = []
        continuations.forEach { $0.resume() }
    }
}

final class FakeSessions: TranslationSessionProviding {
    var status: PairStatus = .installed
    /// Applied to the next sessions.
    var error: (any Error)?
    var holds = false
    private(set) var made: [FakeSession] = []

    func status(from source: Locale.Language, to target: Locale.Language) async -> PairStatus { status }

    func makeSession(from source: Locale.Language, to target: Locale.Language) -> any TranslatingSession {
        let session = FakeSession(pair: LanguagePair(source: source, target: target))
        session.error = error
        session.holds = holds
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
    let sessions = FakeSessions()
    let engine: AppleTranslationEngine

    init() { engine = AppleTranslationEngine(sessions: sessions) }

    func translate(_ text: String) -> Task<String, any Error> {
        let engine = engine, vi = vi, en = en
        return Task { try await engine.translate(text, from: vi, to: en) }
    }

    @Test func cachesOneSessionPerPair() async throws {
        #expect(try await engine.translate("xin chào", from: vi, to: en) == "xin chào [vi→en]")
        #expect(try await engine.translate("tạm biệt", from: vi, to: en) == "tạm biệt [vi→en]")
        #expect(try await engine.translate("hello", from: en, to: vi) == "hello [en→vi]")
        #expect(sessions.made.map(\.pair) == [LanguagePair(source: vi, target: en), LanguagePair(source: en, target: vi)])
    }

    @Test func overlappingRequestsRunOneAtATimeAndTheLatestWins() async throws {
        sessions.holds = true
        let first = translate("một")
        await waitUntil { sessions.made.first?.waiting == 1 }
        let session = try #require(sessions.made.first)
        let second = translate("hai")
        for _ in 0..<50 { await Task.yield() }
        #expect(session.requests == ["một"])

        session.release()
        await #expect(throws: TranslationFailure.cancelled) { try await first.value }
        await waitUntil { session.waiting == 1 }
        session.release()
        #expect(try await second.value == "hai [vi→en]")
        #expect(session.requests == ["một", "hai"])
        #expect(session.mostRunning == 1)
        #expect(!session.isCancelled)
    }

    /// A request cancelled while a session works may not stop at once (nothing says the framework honours cancellation); a
    /// preview must not wait behind it.
    @Test func aCancelledRequestThatWillNotStopDoesNotHoldUpTheNextOneOnAnEngineThatAbandonsIt() async throws {
        let engine = AppleTranslationEngine(sessions: sessions, graceForCancelled: .milliseconds(20))
        sessions.holds = true
        let (vi, en) = (vi, en)
        let first = Task { try await engine.translate("một", from: vi, to: en) }
        await waitUntil { sessions.made.first?.waiting == 1 }
        let stuck = try #require(sessions.made.first)
        sessions.holds = false
        let second = Task { try await engine.translate("hai", from: vi, to: en) }
        // The first one is never released, and the second still gets its answer, from a session of its own.
        #expect(try await second.value == "hai [vi→en]")
        #expect(sessions.made.count == 2)
        #expect(sessions.made[1].requests == ["hai"])
        #expect(stuck.waiting == 1)
        stuck.release()
        await #expect(throws: TranslationFailure.cancelled) { try await first.value }
    }

    @Test func theOneAbandonedDoesNotCountAsTheSessionOfThePairAnyMore() async throws {
        let engine = AppleTranslationEngine(sessions: sessions, graceForCancelled: .milliseconds(20))
        sessions.holds = true
        let (vi, en) = (vi, en)
        let first = Task { try await engine.translate("một", from: vi, to: en) }
        await waitUntil { sessions.made.first?.waiting == 1 }
        let stuck = try #require(sessions.made.first)
        sessions.holds = false
        _ = try await engine.translate("hai", from: vi, to: en)
        _ = try await engine.translate("ba", from: vi, to: en)
        // The third reused the second's session; the stuck one saw nothing more.
        #expect(sessions.made.count == 2)
        #expect(sessions.made[1].requests == ["hai", "ba"])
        stuck.release()
        _ = try? await first.value
    }

    @Test func aRequestThatEndsWithinTheGraceStillReusesItsSession() async throws {
        let engine = AppleTranslationEngine(sessions: sessions, graceForCancelled: .seconds(5))
        let (vi, en) = (vi, en)
        _ = try await engine.translate("một", from: vi, to: en)
        _ = try await engine.translate("hai", from: vi, to: en)
        #expect(sessions.made.count == 1)
    }

    @Test func aRequestSupersededWhileWaitingNeverReachesTheSession() async throws {
        sessions.holds = true
        let first = translate("một")
        await waitUntil { sessions.made.first?.waiting == 1 }
        let session = try #require(sessions.made.first)
        let second = translate("hai")
        let third = translate("ba")
        session.release()
        await #expect(throws: TranslationFailure.cancelled) { try await first.value }
        await #expect(throws: TranslationFailure.cancelled) { try await second.value }
        await waitUntil { session.waiting == 1 }
        session.release()
        #expect(try await third.value == "ba [vi→en]")
        #expect(session.requests == ["một", "ba"])
    }

    @Test func cancellingTheCallerCancelsOnlyItsRequest() async throws {
        sessions.holds = true
        let call = translate("một")
        await waitUntil { sessions.made.first?.waiting == 1 }
        let session = try #require(sessions.made.first)
        call.cancel()
        session.release()
        await #expect(throws: TranslationFailure.cancelled) { try await call.value }
        #expect(!session.isCancelled)

        session.holds = false
        #expect(try await engine.translate("hai", from: vi, to: en) == "hai [vi→en]")
        #expect(sessions.made.count == 1)
    }

    @Test func blankTextTranslatesToNothingWithoutASession() async throws {
        #expect(try await engine.translate(" \n", from: vi, to: en) == "")
        #expect(try await engine.translate("", from: vi, to: en) == "")
        #expect(sessions.made.isEmpty)
    }

    @Test func invalidateCancelsTheRunningTranslationAndDropsTheSessions() async throws {
        sessions.holds = true
        let call = translate("một")
        await waitUntil { sessions.made.first?.waiting == 1 }
        let session = try #require(sessions.made.first)
        engine.invalidate()
        #expect(session.isCancelled)
        session.release()
        await #expect(throws: TranslationFailure.cancelled) { try await call.value }

        sessions.holds = false
        #expect(try await engine.translate("hai", from: vi, to: en) == "hai [vi→en]")
        #expect(sessions.made.count == 2)
    }

    @Test func missingLanguagePackIsNotInstalledAndRetriedWithAFreshSession() async throws {
        sessions.error = TranslationError.notInstalled
        await #expect(throws: TranslationFailure.notInstalled) { try await engine.translate("xin chào", from: vi, to: en) }

        sessions.error = nil   // the user installed the pack
        #expect(try await engine.translate("xin chào", from: vi, to: en) == "xin chào [vi→en]")
        #expect(sessions.made.count == 2)
    }

    @Test func unsupportedLanguagesAreUnsupported() async {
        for error in [TranslationError.unsupportedLanguagePairing, .unsupportedSourceLanguage, .unsupportedTargetLanguage] {
            sessions.error = error
            await #expect(throws: TranslationFailure.unsupported) { try await engine.translate("xin chào", from: vi, to: en) }
        }
        #expect(sessions.made.count == 3)
    }

    @Test func aCancelledSessionIsReplaced() async throws {
        sessions.error = TranslationError.alreadyCancelled
        await #expect(throws: TranslationFailure.cancelled) { try await engine.translate("xin chào", from: vi, to: en) }
        sessions.error = nil
        #expect(try await engine.translate("xin chào", from: vi, to: en) == "xin chào [vi→en]")
        #expect(sessions.made.count == 2)
    }

    @Test func otherErrorsFailWithTheirDescriptionAndKeepTheSession() async throws {
        _ = try await engine.translate("xin chào", from: vi, to: en)
        sessions.made[0].error = Boom()
        await #expect(throws: TranslationFailure.failed("Hỏng rồi")) { try await engine.translate("xin chào", from: vi, to: en) }
        sessions.made[0].error = nil
        #expect(try await engine.translate("tạm biệt", from: vi, to: en) == "tạm biệt [vi→en]")
        #expect(sessions.made.count == 1)
    }

    @Test func statusComesFromTheSessions() async {
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

    @Test func mapsCancellation() {
        #expect(TranslationFailure(CancellationError()) == .cancelled)
        #expect(TranslationFailure(TranslationError.alreadyCancelled) == .cancelled)
        #expect(TranslationFailure(TranslationFailure.notInstalled) == .notInstalled)
    }
}

/// Lets main-actor tasks started by the test run until `condition` holds.
private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<200 where !condition() { await Task.yield() }
}
