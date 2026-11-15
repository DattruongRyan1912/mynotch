import Observation

nonisolated enum ProcessRankingMode: String, CaseIterable, Sendable {
    case cpu = "CPU"
    case memory = "RAM"
}

@Observable
final class PerformanceState {
    /// Whether this Mac's SMC could be opened; the temperature half of the tab is left out when not.
    var hasThermal = false
    var thermal: ThermalSnapshot?
    var history = ThermalHistory()
    /// Overall system CPU usage percentage (0...100).
    var cpuUsage: Double?
    var usage: MemoryUsage?
    /// Top memory-consuming processes.
    var processes: [ProcessRow] = []
    /// Top CPU-consuming processes.
    var cpuProcesses: [ProcessRow] = []
    /// Which process list the user is viewing: .cpu or .memory.
    var processRankingMode: ProcessRankingMode = .cpu
    /// Whether a tab is on screen: the polling runs only then, or while the strip is shown.
    var isTabVisible = false
    /// What the strip beside the collapsed notch shows; the temperature only on a Mac that has sensors.
    var stripTemperature = false
    var stripMemory = false
    /// The fan helper's installation, for the row in the tab; nil where there is none (a test of a view that has no use for one).
    var helper: FanHelperManager?
    /// The fan curve's runner, for the line in the tab; nil where there is none.
    var curve: FanCurveRunner?
    /// Whether the curve is the fan mode: it keeps the temperature being read with no tab open.
    var curveWanted = false
    /// Manages safe throttling/freezing of heavy background processes (SIGSTOP/SIGCONT).
    let freezer = ProcessFreezer()
}

/// What the tab tells the module about itself.
struct PerformanceTabActions {
    var appeared: () -> Void
    var disappeared: () -> Void
}
