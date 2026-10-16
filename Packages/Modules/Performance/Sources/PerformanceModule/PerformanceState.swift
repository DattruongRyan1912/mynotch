import Observation

@Observable
final class PerformanceState {
    var thermal: ThermalSnapshot?
    var history = ThermalHistory()
    /// Whether a tab is on screen: the polling runs only then, or while the strip is shown.
    var isTabVisible = false
    var stripTemperature = false
}

/// What the tab tells the module about itself.
struct PerformanceTabActions {
    var appeared: () -> Void
    var disappeared: () -> Void
}
