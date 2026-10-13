import Foundation

/// A day's usage of one agent, from the events since local midnight.
nonisolated struct AgentDayUsage: Equatable, Sendable {
    var tokens: UsageTotals
    /// From the price table (see `UsageCalculator.estimateLabel`); nil when no model used has a price.
    var estimatedCostUSD: Double?
}

/// Usage per agent for the current local day. It lives outside the sessions so that a session leaving does
/// not take its usage out of the day.
nonisolated struct DayUsageLedger: Equatable, Sendable {
    private struct Day: Equatable, Sendable {
        var start: Date
        var byModel: [String: UsageTotals] = [:]
    }

    private var days: [AgentSource: Day] = [:]

    /// Adds usage that happened at `date`; ignored when that was before the current day began.
    mutating func add(_ usage: UsageTotals, model: String, source: AgentSource, at date: Date, now: Date, calendar: Calendar) {
        let dayStart = calendar.startOfDay(for: now)
        guard !usage.isEmpty, date >= dayStart else { return }
        var day = days[source].flatMap { $0.start == dayStart ? $0 : nil } ?? Day(start: dayStart)
        day.byModel[model, default: UsageTotals()] += usage
        days[source] = day
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
}
