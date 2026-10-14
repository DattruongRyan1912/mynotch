#if DEBUG
import Foundation

/// DEBUG builds only: lets the controller run an Apple Music lyrics lookup for a catalog song id without playing anything,
/// by posting a distributed notification (`io.lucasvu.mynotch.debug.appleLyrics`, whose object is the id as a string).
/// The lookup goes through the normal client and queue, and touches neither the playing track nor the cache; its outcome
/// is logged at the default (notice) level as a kind and a line count, never lyric text, with the steps' own log lines.
final class AppleLyricsDebugTrigger {
    static let notificationName = Notification.Name("io.lucasvu.mynotch.debug.appleLyrics")
    /// A lookup is a few requests to Apple, so a second one this soon is ignored.
    static let minimumInterval: TimeInterval = 5
    /// What the sender could pass is a catalog id: digits, and not more of them than any id has.
    static let maxDigits = 20

    /// Registers a handler for what the notification's object carries (nil when it is no string) and returns how to remove it.
    /// A seam: tests deliver objects themselves instead of posting distributed notifications.
    typealias Observe = (_ handler: @escaping @MainActor (String?) -> Void) -> (() -> Void)

    /// The real thing: the distributed notification center, which also hears other processes (the shell).
    static let systemObserve: Observe = { handler in
        let token = DistributedNotificationCenter.default().addObserver(forName: notificationName, object: nil, queue: .main) { notification in
            let object = notification.object as? String
            MainActor.assumeIsolated { handler(object) }
        }
        return { DistributedNotificationCenter.default().removeObserver(token) }
    }

    private let lookUp: (String) async -> LyricsResult
    private let log: any AppleMusicLog
    private let now: () -> Date
    private let observe: Observe
    private var removeObserver: (() -> Void)?
    private var lastAccepted: Date?

    var isObserving: Bool { removeObserver != nil }

    init(
        lookUp: @escaping (String) async -> LyricsResult, log: any AppleMusicLog = OSAppleMusicLog(),
        now: @escaping () -> Date = Date.init, observe: @escaping Observe = AppleLyricsDebugTrigger.systemObserve
    ) {
        self.lookUp = lookUp
        self.log = log
        self.now = now
        self.observe = observe
    }

    func start() {
        guard removeObserver == nil else { return }
        removeObserver = observe { [weak self] object in _ = self?.receive(object) }
    }

    func stop() {
        removeObserver?()
        removeObserver = nil
    }

    /// What the observer calls. The lookup it starts, nil when `object` is ignored: not a string of digits, or less than
    /// `minimumInterval` after the lookup before it (an ignored object does not count). Nothing of the object is logged.
    @discardableResult
    func receive(_ object: String?) -> Task<Void, Never>? {
        guard let id = object, !id.isEmpty, id.count <= Self.maxDigits, id.utf8.allSatisfy({ (48...57).contains($0) }) else {
            log.write("Apple debug lookup: ignored, the object is not a numeric song id", level: .default)
            return nil
        }
        let time = now()
        // A clock that went back does not block for ever.
        if let lastAccepted, (0..<Self.minimumInterval).contains(time.timeIntervalSince(lastAccepted)) {
            log.write("Apple debug lookup: ignored, one lookup per \(Int(Self.minimumInterval)) seconds", level: .default)
            return nil
        }
        lastAccepted = time
        log.write("Apple debug lookup: started", level: .default)
        return Task { [lookUp, log] in
            let result = await lookUp(id)
            log.write("Apple debug lookup: \(Self.describe(result))", level: .default)
        }
    }

    /// A kind and, for lyrics, how many lines: never what they say.
    private static func describe(_ result: LyricsResult) -> String {
        switch result {
        case .synced(let lines): "result=synced lines=\(lines.count)"
        case .plain(let text): "result=plain lines=\(text.split(whereSeparator: \.isNewline).count)"
        case .instrumental: "result=instrumental"
        case .notFound: "result=notFound"
        case .unavailable(let reason): "result=unavailable reason=\(reason)"
        }
    }
}
#endif
