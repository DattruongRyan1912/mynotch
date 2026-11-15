import Observation

/// Whether the lock screen can be seen right now: locked, with the display on. The panel's views read it as `notchIsOnScreen`
/// (set by `LockScreenRootView`), so a timeline that ticks and a sweep that animates stand still while the display sleeps, in the
/// moment before the module takes the panel away. Observable, so a view already up follows it.
@Observable
final class LockScreenPresence {
    private(set) var isOnScreen = false

    func set(_ isOnScreen: Bool) {
        if isOnScreen != self.isOnScreen { self.isOnScreen = isOnScreen }
    }
}
