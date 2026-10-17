import Observation

@Observable
final class PerformanceState {
    /// Whether this Mac's SMC could be opened; the temperature half of the tab is left out when not.
    var hasThermal = false
    var thermal: ThermalSnapshot?
    var history = ThermalHistory()
    var usage: MemoryUsage?
    var processes: [ProcessRow] = []
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
}

/// What the tab tells the module about itself.
struct PerformanceTabActions {
    var appeared: () -> Void
    var disappeared: () -> Void
}
