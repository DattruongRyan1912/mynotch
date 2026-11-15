import Foundation
import Synchronization
import Testing
@testable import PerformanceModule

/// The reply, the error handler and the timeout can all fire for one call; the first one decides and the others are ignored (a
/// second resume of a continuation crashes the app).
@Suite struct XPCReplyTests {
    struct Failure: Error, Equatable {}

    @Test func aReplyIsReturned() async throws {
        let value: Int = try await XPCReply.run(timeout: .seconds(5)) { reply in reply(.success(42)) }
        #expect(value == 42)
    }

    @Test func anErrorIsThrown() async {
        await #expect(throws: Failure.self) {
            let _: Int = try await XPCReply.run(timeout: .seconds(5)) { reply in reply(.failure(Failure())) }
        }
    }

    @Test func aReplyAndThenAnErrorIsTheReply() async throws {
        let value: Int = try await XPCReply.run(timeout: .seconds(5)) { reply in
            reply(.success(1))
            reply(.failure(Failure()))
            reply(.success(2))
        }
        #expect(value == 1)
    }

    @Test func anErrorAndThenAReplyIsTheError() async {
        await #expect(throws: Failure.self) {
            let _: Int = try await XPCReply.run(timeout: .seconds(5)) { reply in
                reply(.failure(Failure()))
                reply(.success(1))
            }
        }
    }

    @Test func silenceIsATimeout() async {
        await #expect(throws: FanHelperError.timeout) {
            let _: Int = try await XPCReply.run(timeout: .milliseconds(50)) { _ in }
        }
    }

    @Test func aReplyThatComesAfterTheTimeoutIsIgnored() async throws {
        nonisolated(unsafe) var late: (@Sendable (Result<Int, any Error>) -> Void)?
        await #expect(throws: FanHelperError.timeout) {
            let _: Int = try await XPCReply.run(timeout: .milliseconds(30)) { reply in late = reply }
        }
        late?(.success(7))
        late?(.failure(Failure()))
        try await Task.sleep(for: .milliseconds(50))
    }

    @Test func aReplyCancelsTheTimerSoItNeverFiresIntoTheNextCall() async throws {
        let value: Int = try await XPCReply.run(timeout: .milliseconds(40)) { reply in reply(.success(5)) }
        #expect(value == 5)
        try await Task.sleep(for: .milliseconds(120))
    }

    @Test func manyCallsAnsweringFromSeveralThreadsAtOnceEachResumeOnce() async throws {
        var total = 0
        for index in 0..<50 {
            total += try await XPCReply.run(timeout: .seconds(5)) { (reply: @escaping @Sendable (Result<Int, any Error>) -> Void) in
                for _ in 0..<3 {
                    DispatchQueue.global().async { reply(.success(index)) }
                }
            }
        }
        #expect(total == (0..<50).reduce(0, +))
    }
}
