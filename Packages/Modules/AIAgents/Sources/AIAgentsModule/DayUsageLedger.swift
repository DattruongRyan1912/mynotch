import Foundation

/// A day's usage of one agent, from the events since local midnight.
nonisolated struct AgentDayUsage: Equatable, Sendable {
    var tokens: UsageTotals
    /// From the price table (see `UsageCalculator.estimateLabel`); nil when no model used has a price.
    var estimatedCostUSD: Double?
}

/// Usage per agent for the current local day. It lives outside the sessions and does its own deduplication,
/// so a session that leaves and comes back, or a transcript read again from its tail, never counts twice.
nonisolated struct DayUsageLedger: Equatable, Sendable {
    /// How many message ids are remembered for the day. The records of one message are written close together,
    /// so forgetting the oldest ids only bounds memory.
    static let messageMemory = 5_000
    /// How many sessions' last running totals are remembered.
    static let totalMemory = 500

    private struct Day: Equatable, Sendable {
        var start: Date
        var byModel: [String: UsageTotals] = [:]
    }

    private struct MessageKey: Hashable, Sendable {
        var source: AgentSource
        var messageID: String
    }

    private struct SessionKey: Hashable, Sendable {
        var source: AgentSource
        var sessionID: String
    }

    private var days: [AgentSource: Day] = [:]
    private var messages: [MessageKey: UsageTotals] = [:]
    private var messageOrder: [MessageKey] = []
    /// The day `messages` belongs to; a new day forgets them.
    private var messagesDay: Date?
    /// The latest running total of each session that reports totals (Codex). It is a baseline, not a day's
    /// usage, so it is kept across midnight: what a session adds after midnight is the difference from it.
    private var runningTotals: [SessionKey: UsageTotals] = [:]
    private var totalOrder: [SessionKey] = []

    var rememberedMessageCount: Int { messages.count }
    var rememberedTotalCount: Int { runningTotals.count }

    /// Counts what `usage` adds to the day: a message's usage once however many records repeat it, a running
    /// total as its difference from the one before. Usage that happened before the current day began is not counted.
    mutating func record(_ usage: AgentUsage, source: AgentSource, sessionID: String, at date: Date, now: Date, calendar: Calendar) {
        let dayStart = calendar.startOfDay(for: now)
        let totals = UsageTotals(usage)
        let added: UsageTotals
        if usage.isCumulative {
            let key = SessionKey(source: source, sessionID: sessionID)
            let previous = runningTotals[key]
            remember(total: totals, for: key)
            // Fewer tokens than before means the agent counts from zero again. With nothing before it, the total
            // is a starting point unless the whole session was read, since it may hold work from before anything was watched.
            added = previous.map { totals.isAtLeast($0) ? totals - $0 : totals } ?? (usage.startsFromZero ? totals : UsageTotals())
        } else if let id = usage.messageID {
            guard date >= dayStart else { return }
            if messagesDay != dayStart {
                messages = [:]
                messageOrder = []
                messagesDay = dayStart
            }
            let key = MessageKey(source: source, messageID: id)
            if messages[key] == nil { remember(key) }
            added = totals - (messages.updateValue(totals, forKey: key) ?? UsageTotals())
        } else {
            added = totals
        }
        add(added, model: usage.model ?? "", source: source, at: date, dayStart: dayStart)
    }

    /// Agents with usage today; a day that ended before `now` is left out.
    func usage(now: Date, calendar: Calendar) -> [AgentSource: AgentDayUsage] {
        let dayStart = calendar.startOfDay(for: now)
        return days.compactMapValues { day in
            guard day.start == dayStart else { return nil }
            return AgentDayUsage(
                tokens: day.byModel.values.reduce(UsageTotals(), +),
                estimatedCostUSD: UsageCalculator.estimatedCost(of: day.byModel)
            )
        }
    }

    private mutating func add(_ usage: UsageTotals, model: String, source: AgentSource, at date: Date, dayStart: Date) {
        guard !usage.isEmpty, date >= dayStart else { return }
        var day = days[source].flatMap { $0.start == dayStart ? $0 : nil } ?? Day(start: dayStart)
        day.byModel[model, default: UsageTotals()] += usage
        days[source] = day
    }

    private mutating func remember(_ key: MessageKey) {
        messageOrder.append(key)
        guard messageOrder.count > Self.messageMemory else { return }
        let forgotten = messageOrder.prefix(Self.messageMemory / 2)
        forgotten.forEach { messages[$0] = nil }
        messageOrder.removeFirst(forgotten.count)
    }

    private mutating func remember(total: UsageTotals, for key: SessionKey) {
        if runningTotals.updateValue(total, forKey: key) == nil {
            totalOrder.append(key)
            guard totalOrder.count > Self.totalMemory else { return }
            let forgotten = totalOrder.prefix(Self.totalMemory / 2)
            forgotten.forEach { runningTotals[$0] = nil }
            totalOrder.removeFirst(forgotten.count)
        }
    }
}
