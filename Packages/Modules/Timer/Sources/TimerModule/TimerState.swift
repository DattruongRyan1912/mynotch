import Observation

@Observable
final class TimerState {
    enum Mode: Hashable { case countdown, stopwatch }

    var model = TimerModel.idle
    /// What the tab offers to start while idle.
    var mode = Mode.countdown
    var customMinutes = 15
}
