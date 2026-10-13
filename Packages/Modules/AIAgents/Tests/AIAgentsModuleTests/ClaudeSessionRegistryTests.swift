import Darwin
import Foundation
import Testing
@testable import AIAgentsModule

@Suite struct ClaudeSessionRegistryTests {
    @Test func parsesARegistryEntry() {
        let data = Data(#"{"pid":4242,"sessionId":"11111111-2222-4333-8444-555555555555","cwd":"/Users/example/Projects/demo","startedAt":1791878400000,"name":"ZEBRAPLACEHOLDER","status":"busy","statusUpdatedAt":"2026-10-13T08:00:05.000Z","kind":"interactive","entrypoint":"cli","version":"2.0.0"}"#.utf8)
        let info = ClaudeSessionRegistry.parse(data: data)
        #expect(info == ClaudeSessionInfo(
            pid: 4242,
            sessionID: "11111111-2222-4333-8444-555555555555",
            cwd: "/Users/example/Projects/demo",
            status: .busy,
            startedAt: Date(timeIntervalSince1970: 1_791_878_400),
            statusUpdatedAt: utc("2026-10-13T08:00:05Z")
        ))
        #expect(!String(describing: info).contains("ZEBRAPLACEHOLDER"))
    }

    @Test func optionalFieldsMayBeMissingOrUnknown() {
        let data = Data(#"{"pid":7,"sessionId":"s","status":"thinking","startedAt":"2026-10-13T08:00:00Z"}"#.utf8)
        #expect(ClaudeSessionRegistry.parse(data: data) == ClaudeSessionInfo(
            pid: 7, sessionID: "s", cwd: nil, status: nil, startedAt: utc("2026-10-13T08:00:00Z"), statusUpdatedAt: nil
        ))
        let idle = Data(#"{"pid":7,"sessionId":"s","status":"idle"}"#.utf8)
        #expect(ClaudeSessionRegistry.parse(data: idle)?.status == .idle)
    }

    @Test func entriesWithoutAProcessOrSessionAreRejected() {
        let entries = [
            "", "not json", "[]", #"{"sessionId":"s"}"#, #"{"pid":12}"#, #"{"pid":0,"sessionId":"s"}"#,
            #"{"pid":-3,"sessionId":"s"}"#, #"{"pid":"12","sessionId":"s"}"#, #"{"pid":12,"sessionId":""}"#,
        ]
        for entry in entries {
            #expect(ClaudeSessionRegistry.parse(data: Data(entry.utf8)) == nil, "\(entry)")
        }
    }

    @Test func livenessFollowsTheProcessTable() {
        #expect(ClaudeSessionRegistry.isAlive(pid: getpid()))
        #expect(!ClaudeSessionRegistry.isAlive(pid: 999_999))
        #expect(!ClaudeSessionRegistry.isAlive(pid: 0))
        #expect(!ClaudeSessionRegistry.isAlive(pid: -1))
    }
}
