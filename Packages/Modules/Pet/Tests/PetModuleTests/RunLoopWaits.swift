import Foundation

/// Runs the main run loop, as the display would, until `condition` holds. The limit only matters when something is
/// wrong, so it is very generous: a busy machine can take many seconds to get to what is queued.
@discardableResult
func runLoop(until condition: () -> Bool, seconds: TimeInterval = 60) -> Bool {
    let deadline = ContinuousClock.now + .seconds(seconds)
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    return true
}

/// Runs the main run loop until `value` has stayed the same through `turns` runs in a row, which is to say that what was
/// already on its way has come and a test can start counting what it does not expect.
func runLoopUntilQuiet<Value: Equatable>(_ value: () -> Value, turns: Int = 5, seconds: TimeInterval = 60) {
    let deadline = ContinuousClock.now + .seconds(seconds)
    var last = value()
    var quiet = 0
    while quiet < turns, ContinuousClock.now < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        let current = value()
        if current == last {
            quiet += 1
        } else {
            last = current
            quiet = 0
        }
    }
}

#if canImport(AppKit)
import AppKit
@testable import PetModule

/// Every view under `view`, itself included.
@MainActor func descendants(of view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(descendants(of:))
}

/// Lets a notch that was just put in a window find which display it is on, which a view of the pets does a turn of the main loop after it
/// is in one, and show or not show what the user chose for that display.
@MainActor func settleDisplays(in window: NSWindow) {
    guard let root = window.contentView else { return }
    let probes = descendants(of: root).compactMap { $0 as? DisplayProbeView }
    runLoop(until: { probes.allSatisfy { $0.hasReported } }, seconds: 10)
    runLoopUntilQuiet({ descendants(of: root).count }, turns: 5, seconds: 10)
}
#endif
