import Observation

@Observable
final class PortsState {
    /// Every row of the last read, UDP included, sorted by port.
    var entries: [PortEntry] = []
    /// Whether a read has finished, so "nothing is listening" is not said before the first answer.
    var hasLoaded = false
    var showUDP = false
    /// Whether the rows show what each process was started with. Not while MyNotch is kept out of recordings (see
    /// `PortsModule.showsCommandLines(under:)`): then a row is the process's name and nothing more.
    var showsCommandLines = true
    /// What the filter field holds.
    var filter = ""
    /// What "Cổng nào đang bị chiếm?" holds, and what the system said about that port when no row of the user's has it.
    var quickQuery = ""
    var probe: PortProbeOutcome?
    /// The stops in progress, by pid.
    var flows: [Int32: StopFlow] = [:]
    /// A line that says what just happened ("Đã dừng node"), for a few seconds.
    var notice: String?
    /// Whether a tab is on screen: the polling only runs then.
    var isTabVisible = false

    var visibleEntries: [PortEntry] { PortFilter.apply(entries, query: filter, showUDP: showUDP, searchesCommands: showsCommandLines) }
    var quickAnswer: PortQuickCheck.Answer { PortQuickCheck.answer(query: quickQuery, entries: entries, probe: probe) }
    /// Whether a confirmation or an offer is waiting for the user, on a row that is on screen: one the filter hides asks nothing
    /// of anybody, so it does not hold the notch open.
    var needsAnswer: Bool {
        let shown = Set(visibleEntries.map(\.id))
        return flows.values.contains { $0.phase.needsAnswer && shown.contains($0.entry.id) }
    }
}
