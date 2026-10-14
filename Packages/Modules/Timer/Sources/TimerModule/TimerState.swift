import Observation

@Observable
final class TimerState {
    enum Mode: Hashable { case timer(TimerKind), stopwatch }

    var model = TimerModel.idle
    /// What the countdown on screen is. Meaningless while idle or for a stopwatch.
    var session = TimerSession.plain
    /// What the tab offers to start while idle.
    var mode = Mode.timer(.task)
    /// Lengths the user turned the dial to since a timer of that type last started; the Settings default applies otherwise.
    var adjustedMinutes: [TimerKind: Int] = [:]
    /// What the reminder field holds.
    var reminderLabel = ""
}
