import Darwin
import Foundation
import Synchronization
import os

/// Where the bridge's diagnostics go: the unified log (subsystem `io.lucasvu.mynotch`, category `youtube-bridge`, level
/// notice), or, in tests, a list. The host and the app write the same kind of line, so one category tells the whole
/// story of a caption from Chrome to the notch.
///
/// A line holds only fixed codes, counts, durations and the extension's own diagnostic events (which are checked
/// against a closed grammar first): never a title, a URL, a video id, caption text or a path. That is why the whole
/// line is written as public.
public struct YouTubeBridgeLog: Sendable {
    /// The app's bundle identifier, as `Log.subsystem` of the app's modules.
    public static let subsystem = "io.lucasvu.mynotch"
    public static let category = "youtube-bridge"

    private static let logger = Logger(subsystem: subsystem, category: category)

    private let sink: @Sendable (String) -> Void

    public init(_ sink: @escaping @Sendable (String) -> Void) {
        self.sink = sink
    }

    public static let system = YouTubeBridgeLog { line in
        logger.notice("\(line, privacy: .public)")
    }

    /// Writes nothing.
    public static let silent = YouTubeBridgeLog { _ in }

    public func callAsFunction(_ line: String) {
        sink(line)
    }
}

/// Counts frames by kind and by the reason they were lost, and says so now and then instead of at every frame: a
/// summary at most every `interval` seconds, and only when there is something to say.
public final class FrameTally: Sendable {
    private struct State {
        var counted: [String: Int] = [:]
        var lost: [String: Int] = [:]
        var lastSummary: TimeInterval
        var announced: [String: TimeInterval] = [:]
    }

    private let countedLabel: String
    private let lostLabel: String
    private let interval: TimeInterval
    private let now: @Sendable () -> TimeInterval
    private let state: Mutex<State>

    /// - Parameters:
    ///   - counted: what the frames that went through are called in a summary (`forwarded`, `received`).
    ///   - lost: what the others are called (`dropped`, `rejected`).
    public init(counted: String, lost: String, interval: TimeInterval = 10, now: @escaping @Sendable () -> TimeInterval) {
        countedLabel = counted
        lostLabel = lost
        self.interval = interval
        self.now = now
        state = Mutex(State(lastSummary: now()))
    }

    public func count(_ kind: String) {
        state.withLock { $0.counted[kind, default: 0] += 1 }
    }

    public func lose(_ reason: String) {
        state.withLock { $0.lost[reason, default: 0] += 1 }
    }

    /// The summary of what was counted since the last one, when `interval` has passed since then or `force` is set; nil
    /// when there is nothing to report. Taking it starts the counts over.
    public func line(force: Bool = false) -> String? {
        state.withLock { state in
            guard !state.counted.isEmpty || !state.lost.isEmpty else { return nil }
            let current = now()
            guard force || current - state.lastSummary >= interval else { return nil }
            defer {
                state.counted = [:]
                state.lost = [:]
                state.lastSummary = current
            }
            let groups = [(countedLabel, state.counted), (lostLabel, state.lost)].filter { !$0.1.isEmpty }
            return groups
                .map { label, counts in "\(label)[" + counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ") + "]" }
                .joined(separator: " ")
        }
    }

    /// True for the first time a key is asked in each `interval`, so that a repeating problem is announced once and
    /// counted for the summary.
    public func announces(_ key: String) -> Bool {
        state.withLock { state in
            let current = now()
            if let last = state.announced[key], current - last < interval { return false }
            state.announced[key] = current
            return true
        }
    }
}

/// How the host was started, for its first log line. The command line itself is not logged: Chrome puts the
/// extension's origin there.
public struct YouTubeHostLaunch: Sendable {
    public var argumentCount: Int
    /// The name, not the path or the arguments, of the process that started the host.
    public var parentName: String?

    public init(argumentCount: Int, parentName: String?) {
        self.argumentCount = argumentCount
        self.parentName = parentName
    }

    public static var current: YouTubeHostLaunch {
        var name = [CChar](repeating: 0, count: 64)
        let length = Int(proc_name(getppid(), &name, UInt32(name.count)))
        return YouTubeHostLaunch(
            argumentCount: CommandLine.arguments.count,
            parentName: length > 0 ? String(decoding: name.prefix(length).map { UInt8(bitPattern: $0) }, as: UTF8.self) : nil
        )
    }
}
