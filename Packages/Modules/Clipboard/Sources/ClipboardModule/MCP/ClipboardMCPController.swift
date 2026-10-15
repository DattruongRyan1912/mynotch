import ClipboardMCPKit
import Foundation

/// Answers what the helper asks, under the rules that are not about the history itself: off is off, calls come at a limited
/// rate, and every call that reached the history is logged. The server hands it each request line on the main actor.
final class ClipboardMCPController {
    private let state: ClipboardMCPState
    private let history: () -> ClipboardHistory
    private let index: ClipboardSearchIndex
    /// What each item looks like to the filter for secrets, kept so the history is read once and not at every call.
    private let secrets = ClipboardMCPSecretFilter.Cache()
    private let lockedBoardIDs: () -> Set<UUID>
    private let isEnabled: () -> Bool
    private let now: () -> Date
    private let uptime: () -> Double
    private var limiter = ClipboardMCPRateLimiter()

    /// - Parameters:
    ///   - isEnabled: asked on every call, so turning the feature off stops the next call even on a connection already open.
    ///   - lockedBoardIDs: the boards the user keeps locked, whose items an agent never sees.
    ///   - uptime: monotonic seconds, for the rate limit.
    init(
        state: ClipboardMCPState, history: @escaping () -> ClipboardHistory, index: ClipboardSearchIndex,
        lockedBoardIDs: @escaping () -> Set<UUID>, isEnabled: @escaping () -> Bool, now: @escaping () -> Date, uptime: @escaping () -> Double
    ) {
        self.state = state
        self.history = history
        self.index = index
        self.lockedBoardIDs = lockedBoardIDs
        self.isEnabled = isEnabled
        self.now = now
        self.uptime = uptime
    }

    func answer(_ line: Data) -> ClipboardMCPWireReply {
        guard isEnabled() else {
            return .failure(.disabled, "Sharing the clipboard history with AI agents is turned off in MyNotch.")
        }
        // Before the request is read, so a flood of requests that are not even valid costs the same as any other.
        let tool = Self.tool(in: line)
        guard limiter.allow(at: uptime()) else {
            state.record(tool: tool ?? "unknown", outcome: .rateLimited(count: 1), at: now())
            return .failure(.rateLimited, "Too many calls: at most \(ClipboardMCPLimits.maxCallsPerSecond) calls per second. Wait a moment and try again.")
        }
        switch ClipboardMCPWire.decodeRequest(line) {
        case .unreadable:
            return .failure(.invalidArguments, "The request could not be read.")
        case .rejected(let reason, let message):
            return .failure(reason, message)
        case .request(let request):
            let answer = ClipboardMCPAnswerer.answer(
                request, history: history(), index: index, secrets: secrets, lockedBoardIDs: lockedBoardIDs(), now: now()
            )
            state.record(tool: request.tool, outcome: .answered(count: answer.resultCount, hidden: answer.hiddenCount), at: now())
            return answer.reply
        }
    }

    /// The tool a line names, for the log, when it is one of the two this server has.
    private static func tool(in line: Data) -> String? {
        guard line.count <= ClipboardMCPWire.maxRequestLength, case .string(let name)? = (try? JSON(decoding: line))?["tool"],
              [ClipboardMCPRequest.searchTool, ClipboardMCPRequest.itemTool].contains(name)
        else { return nil }
        return name
    }
}
