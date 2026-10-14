import AgentHookKit
import Foundation
import MyNotchCore
import Observation

/// One permission request an agent waits on: what the card shows, and nothing of the conversation. Built from the
/// helper's filtered payload, which has the tool name, a short summary for the list of sessions and the detail of what
/// is asked: the whole command, the whole path, the URL, the arguments or the files of a patch.
nonisolated struct PermissionRequest: Identifiable, Equatable, Sendable {
    /// Random and made here, never taken from the helper: a decision is accepted only for the exact id it names.
    let id: String
    let key: AgentSessionKey
    let cwd: String?
    let tool: String
    /// At most 120 characters: the head of a shell command or a file name. For the list of sessions, not for the card.
    let summary: String?
    /// What the card shows as the thing to approve. Nil from a helper that predates it.
    let detail: PermissionDetail?

    var source: AgentSource { key.source }
    /// True when everything the request asks for is there to be shown: nothing was cut, and the helper knew the tool.
    var isWhole: Bool {
        guard let detail else { return false }
        return detail.isComplete && detail.hiddenLines == 0 && !detail.text.isEmpty
    }
    /// True when the tool name and the text are only printable ASCII and line feeds, after cleaning. Anything else (an
    /// accent, a script the font draws wide or in pieces, an emoji, a character that looks like another) is not something
    /// the card can promise to show as it is, so it is answered in the terminal, where the agent's prompt shows it.
    var isPlain: Bool {
        guard let detail else { return false }
        return Self.isPlain(tool) && Self.isPlain(detail.text)
    }
    /// True when the request may be allowed from the notch at all: whole, and plain. Whether all of its text fits the card
    /// that shows it is the layout's to say, and the card offers "Cho phép" only when it does.
    var canAllow: Bool { isWhole && isPlain }

    private static func isPlain(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { ($0.value >= 0x20 && $0.value <= 0x7E) || $0 == "\n" }
    }

    /// The last component of the working directory.
    var project: String? {
        guard let name = cwd.map({ ($0 as NSString).lastPathComponent }), !name.isEmpty else { return nil }
        return name
    }

    init?(payload: HookPayload, id: String) {
        guard let source = AgentSource(rawValue: payload.source), let tool = payload.tool, !tool.isEmpty else { return nil }
        self.id = id
        key = AgentSessionKey(source: source, sessionID: payload.sessionID)
        // Everything that is shown is cleaned here too, whatever sent it: the helper cleans, and an older one does not.
        cwd = payload.cwd.map(HookText.cleanLine)
        self.tool = HookText.cleanLine(tool)
        summary = payload.summary.map(HookText.cleanLine)
        detail = payload.detail.map { PermissionDetail(text: HookText.clean($0.text), hiddenLines: $0.hiddenLines, isComplete: $0.isComplete) }
    }
}

/// The requests waiting for the user, in the order they came. Each holds the way back to the helper that asked, which
/// is told the answer once, or "ask in the terminal" when the request ends without one. Nothing is kept on disk.
@Observable
final class PermissionQueue {
    /// A little more than the helper's own wait (`PermissionClient.defaultTimeout`): the helper gives up first and
    /// its leaving removes the request; this is only for a helper that hangs without leaving.
    static let lifetime = Duration.seconds(PermissionClient.defaultTimeout) + .seconds(5)
    /// How long a card that has just come up takes no answer. The system's double-click interval is half a second, so a
    /// second click of a double click, or a click that began on the card that was there before, is over by then; it is
    /// also under the time it takes to read a command, so it is hardly felt.
    static let armingDelay = Duration.milliseconds(600)

    /// The first is the one on screen.
    private(set) var pending: [PermissionRequest] = []
    /// The id of the card on screen once its delay is over; nil while it waits. Only this request takes an answer.
    private(set) var armedID: String?

    @ObservationIgnored private let scheduler: any Scheduler
    @ObservationIgnored private let lifetime: Duration
    @ObservationIgnored private let makeID: () -> String
    @ObservationIgnored private var responders: [String: (PermissionAnswer) -> Void] = [:]
    @ObservationIgnored private var timers: [String: ScheduledAction] = [:]
    @ObservationIgnored private let armingDelay: Duration
    /// The request whose card is on screen, and the delay it is waiting out.
    @ObservationIgnored private var headID: String?
    @ObservationIgnored private var armingTimer: ScheduledAction?

    init(
        scheduler: any Scheduler, lifetime: Duration = PermissionQueue.lifetime, armingDelay: Duration = PermissionQueue.armingDelay,
        makeID: @escaping () -> String = { UUID().uuidString }
    ) {
        self.scheduler = scheduler
        self.lifetime = lifetime
        self.armingDelay = armingDelay
        self.makeID = makeID
    }

    /// Queues a request. `respond` is called at most once. Nil for a request that names no known agent or tool.
    @discardableResult
    func add(_ payload: HookPayload, respond: @escaping (PermissionAnswer) -> Void) -> PermissionRequest? {
        guard let request = PermissionRequest(payload: payload, id: makeID()) else { return nil }
        pending.append(request)
        responders[request.id] = respond
        timers[request.id] = scheduler.schedule(after: lifetime) { [weak self] in self?.end(request.id, answering: .ask) }
        headMayHaveChanged()
        return request
    }

    /// The user's answer to the request with exactly this id. False, and nothing happens, when there is none, as when it
    /// was already answered; when it is not the card on screen or that card has not waited out its delay yet; and when the
    /// answer is allow for a request that is not shown whole.
    @discardableResult
    func decide(_ id: String, _ answer: PermissionAnswer) -> Bool {
        guard armedID == id, let request = pending.first(where: { $0.id == id }) else { return false }
        guard answer != .allow || request.canAllow else { return false }
        return end(id, answering: answer)
    }

    /// The helper left (the user answered in the terminal, or the agent was stopped): nobody is left to tell.
    func withdraw(_ id: String) {
        end(id, answering: nil)
    }

    /// The session went on without the notch: it ran the tool, ended its turn or ended. Its requests are over, and a
    /// helper that still waits is told to let the agent ask. With `tool`, only the requests for that tool.
    func settle(_ key: AgentSessionKey, tool: String? = nil) {
        for request in pending where request.key == key && (tool == nil || request.tool == tool) {
            end(request.id, answering: .ask)
        }
    }

    /// Ends every request, for when the app stops listening.
    func cancelAll() {
        for request in pending { end(request.id, answering: .ask) }
    }

    @discardableResult
    private func end(_ id: String, answering answer: PermissionAnswer?) -> Bool {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return false }
        pending.remove(at: index)
        timers.removeValue(forKey: id)?.cancel()
        let respond = responders.removeValue(forKey: id)
        headMayHaveChanged()
        if let answer { respond?(answer) }
        return true
    }

    /// A card that comes up, whether it is the first or the one that moved up when the one before it went, takes no answer
    /// until its delay is over.
    private func headMayHaveChanged() {
        let head = pending.first?.id
        guard head != headID else { return }
        headID = head
        armedID = nil
        armingTimer?.cancel()
        armingTimer = nil
        guard let head else { return }
        armingTimer = scheduler.schedule(after: armingDelay) { [weak self] in
            guard let self, headID == head else { return }
            armedID = head
            armingTimer = nil
        }
    }
}
