import AgentHookKit
import Foundation
import MyNotchCore
import Observation

/// One permission request an agent waits on: what the card shows, and nothing of the conversation. Built from the
/// helper's filtered payload, which has only a tool name and a short summary of its command or file.
nonisolated struct PermissionRequest: Identifiable, Equatable, Sendable {
    /// Random and made here, never taken from the helper: a decision is accepted only for the exact id it names.
    let id: String
    let key: AgentSessionKey
    let cwd: String?
    let tool: String
    /// At most 120 characters: the head of a shell command or a file name.
    let summary: String?

    var source: AgentSource { key.source }
    /// The last component of the working directory.
    var project: String? {
        guard let name = cwd.map({ ($0 as NSString).lastPathComponent }), !name.isEmpty else { return nil }
        return name
    }

    init?(payload: HookPayload, id: String) {
        guard let source = AgentSource(rawValue: payload.source), let tool = payload.tool, !tool.isEmpty else { return nil }
        self.id = id
        key = AgentSessionKey(source: source, sessionID: payload.sessionID)
        cwd = payload.cwd
        self.tool = tool
        summary = payload.summary
    }
}

/// The requests waiting for the user, in the order they came. Each holds the way back to the helper that asked, which
/// is told the answer once, or "ask in the terminal" when the request ends without one. Nothing is kept on disk.
@Observable
final class PermissionQueue {
    /// A little more than the helper's own wait (`PermissionClient.defaultTimeout`): the helper gives up first and
    /// its leaving removes the request; this is only for a helper that hangs without leaving.
    static let lifetime = Duration.seconds(PermissionClient.defaultTimeout) + .seconds(5)

    /// The first is the one on screen.
    private(set) var pending: [PermissionRequest] = []

    @ObservationIgnored private let scheduler: any Scheduler
    @ObservationIgnored private let lifetime: Duration
    @ObservationIgnored private let makeID: () -> String
    @ObservationIgnored private var responders: [String: (PermissionAnswer) -> Void] = [:]
    @ObservationIgnored private var timers: [String: ScheduledAction] = [:]

    init(scheduler: any Scheduler, lifetime: Duration = PermissionQueue.lifetime, makeID: @escaping () -> String = { UUID().uuidString }) {
        self.scheduler = scheduler
        self.lifetime = lifetime
        self.makeID = makeID
    }

    /// Queues a request. `respond` is called at most once. Nil for a request that names no known agent or tool.
    @discardableResult
    func add(_ payload: HookPayload, respond: @escaping (PermissionAnswer) -> Void) -> PermissionRequest? {
        guard let request = PermissionRequest(payload: payload, id: makeID()) else { return nil }
        pending.append(request)
        responders[request.id] = respond
        timers[request.id] = scheduler.schedule(after: lifetime) { [weak self] in self?.end(request.id, answering: .ask) }
        return request
    }

    /// Answers the request with exactly this id. False when there is none, as when it was already answered.
    @discardableResult
    func decide(_ id: String, _ answer: PermissionAnswer) -> Bool {
        end(id, answering: answer)
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
        if let answer { respond?(answer) }
        return true
    }
}
