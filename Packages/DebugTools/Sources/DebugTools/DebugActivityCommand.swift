#if DEBUG
import MyNotchCore

/// What the DEBUG trigger understands, read from the string a shell sends as the notification's object: `add <n>`
/// (n = 1...5), `high` or `clear`. Anything else is not a command, so a stray notification does nothing.
nonisolated enum DebugActivityCommand: Equatable, Sendable {
    static let maxCount = 5

    case add(Int)
    case high
    case clear

    init?(_ text: String?) {
        let words = (text ?? "").lowercased().split(whereSeparator: \.isWhitespace)
        switch words.first {
        case "add" where words.count == 2:
            guard let count = Int(words[1]), (1...Self.maxCount).contains(count) else { return nil }
            self = .add(count)
        case "high" where words.count == 1:
            self = .high
        case "clear" where words.count == 1:
            self = .clear
        default:
            return nil
        }
    }
}

/// One synthetic activity, before it becomes views, so what the commands publish can be checked without any.
nonisolated struct DebugActivitySpec: Equatable, Sendable {
    let id: String
    let symbol: String
    let summary: String
    let priority: ActivityPriority
    /// Short text for the trailing side of the primary: the priority's initial and the number, so what is on the notch says
    /// which activity it is.
    let trailingText: String
    let lifetime: Duration?

    static let highID = "debug-high"
    static let highLifetime = Duration.seconds(8)

    /// The ids `add` may have published, so a smaller `add` can remove the rest.
    static let addIDs = (1...DebugActivityCommand.maxCount).map(addID)

    private static let symbols = ["star.fill", "heart.fill", "bolt.fill", "moon.fill", "flame.fill"]
    private static let priorities: [ActivityPriority] = [.low, .normal, .high]
    private static let initials: [ActivityPriority: String] = [.low: "L", .normal: "N", .high: "H"]

    static func addID(_ number: Int) -> String { "debug-\(number)" }

    /// Activities 1...`count` (at most 5): each with its own symbol, "Thử nghiệm <number>" as summary, priorities
    /// cycling low, normal, high, and no expiry.
    static func added(count: Int) -> [DebugActivitySpec] {
        (1...DebugActivityCommand.maxCount).prefix(max(count, 0)).map { number in
            let priority = priorities[(number - 1) % priorities.count]
            return DebugActivitySpec(
                id: addID(number), symbol: symbols[(number - 1) % symbols.count], summary: "Thử nghiệm \(number)",
                priority: priority, trailingText: "\(initials[priority] ?? "?")\(number)", lifetime: nil
            )
        }
    }

    /// One more `.high` activity that goes by itself: to watch a promotion and the demotion after it.
    static let high = DebugActivitySpec(
        id: highID, symbol: "exclamationmark.triangle.fill", summary: "Thử nghiệm ưu tiên cao",
        priority: .high, trailingText: "H!", lifetime: highLifetime
    )
}

/// One command per second: a faster one is dropped, and a dropped one does not push the next back.
nonisolated struct DebugCommandLimiter {
    static let interval = Duration.seconds(1)

    private var lastAccepted: ContinuousClock.Instant?

    mutating func accept(at now: ContinuousClock.Instant) -> Bool {
        // A clock that went back does not block for ever.
        if let lastAccepted, (Duration.zero..<Self.interval).contains(now - lastAccepted) { return false }
        lastAccepted = now
        return true
    }
}
#endif
