import CoreGraphics
import Foundation
import MyNotchTestSupport
import SwiftUI
@testable import TranslationModule

/// Stands in for the system's mouse and key monitors: tests play what the user does, and nothing is ever observed.
final class FakeSelectionInput: SelectionInputSource {
    private(set) var handler: (@MainActor (SelectionInput) -> Void)?
    private(set) var starts = 0
    private(set) var stops = 0
    /// Whether the last start asked for key-ups, which the system only delivers with Accessibility.
    private(set) var watchesKeys = false

    var isRunning: Bool { handler != nil }

    func start(_ handler: @escaping @MainActor (SelectionInput) -> Void, keys: Bool) {
        starts += 1
        watchesKeys = keys
        self.handler = handler
    }

    func stop() {
        stops += 1
        handler = nil
    }

    func send(_ input: SelectionInput) {
        handler?(input)
    }

    func drag(from start: CGPoint, to end: CGPoint) {
        send(.mouseDown(start))
        send(.mouseUp(end, clicks: 1))
    }

    func click(at point: CGPoint) {
        send(.mouseDown(point))
        send(.mouseUp(point, clicks: 1))
    }

    func press(_ code: UInt16, shift: Bool = false, command: Bool = false, pointer: CGPoint = .zero) {
        send(.keyUp(KeyPress(code: code, shift: shift, command: command), pointer: pointer))
    }
}

/// Records what the chip's window was asked to do, and lets tests press the chip's buttons.
final class FakeChipWindow: SelectionChipWindowing {
    struct Shown {
        var content: SelectionChipContent
        var anchor: CGRect
    }

    private(set) var shown: [Shown] = []
    private(set) var hides = 0
    private(set) var isVisible = false

    /// What the user sees now, nil while the chip is hidden.
    var current: Shown? { isVisible ? shown.last : nil }

    func show(_ content: SelectionChipContent, near anchor: CGRect) {
        shown.append(Shown(content: content, anchor: anchor))
        isVisible = true
    }

    func hide() {
        hides += 1
        isVisible = false
    }
}

/// What the watcher wrote to the diagnostics log, one line per entry. The real one is the unified log, which a test must not
/// write to or read.
final class FakeSelectionLog: SelectionLog {
    private(set) var lines: [String] = []

    func write(_ line: SelectionLogLine) {
        lines.append(line.text)
    }

    func contains(_ line: String) -> Bool { lines.contains(line) }

    /// The lines that start with `prefix`, in order.
    func lines(startingWith prefix: String) -> [String] { lines.filter { $0.hasPrefix(prefix) } }
}

/// The notices the watcher put up in the notch, with how long each asked to stay; they are also handed on to the fake presenter.
final class FakeToasts {
    private(set) var durations: [Duration] = []
    var forward: (@MainActor (AnyView, Duration) -> Void)?

    func show(_ content: AnyView, _ duration: Duration) {
        durations.append(duration)
        forward?(content, duration)
    }
}

/// The displays the chip is placed on; tests set them.
final class FakeDisplays {
    /// The main display first, as `NSScreen.screens` lists them: 1440 x 900 with a 25 pt menu bar.
    var areas = [ScreenArea(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875))]
}

extension ModuleFixture {
    var smart: SmartSelection { module.smartSelection! }

    /// The user drags over `text` in the focused app, the debounce passes, and the reading and the decision finish.
    func dragSelecting(_ text: String?, from start: CGPoint = CGPoint(x: 100, y: 500), to end: CGPoint = CGPoint(x: 300, y: 500)) async {
        accessibility.standing = text
        input.drag(from: start, to: end)
        harness.scheduler.advance(by: .milliseconds(250))
        await smart.reading?.value
    }
}
