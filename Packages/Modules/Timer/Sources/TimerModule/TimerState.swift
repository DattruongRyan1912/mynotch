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
    /// A countdown has ended and the user has not yet answered it: the finished activity pulses, the lock screen says so and the
    /// sound may still be repeating. Ends when the user dismisses or snoozes it, starts something else or opens the tab.
    var isAlerting = false
}
