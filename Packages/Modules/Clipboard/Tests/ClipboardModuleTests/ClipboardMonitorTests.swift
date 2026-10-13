import Foundation
import MyNotchTestSupport
import Testing
@testable import ClipboardModule

@Suite final class ClipboardMonitorTests {
    struct Capture: Equatable {
        let content: ClipboardContent
        let imageData: Data?
        let bundleID: String?
        let appName: String?
    }

    static let interval: Duration = .milliseconds(300)

    let pasteboard = FakePasteboard()
    let scheduler = ManualScheduler()
    var paused = false
    var excluded: Set<String> = []
    var frontmost: (bundleID: String?, name: String?) = ("com.apple.Safari", "Safari")
    var captures: [Capture] = []

    lazy var monitor = ClipboardMonitor(
        pasteboard: pasteboard, scheduler: scheduler,
        frontmostApp: { [unowned self] in frontmost },
        shouldCapture: { [unowned self] in
            (paused: paused, excluded: excluded, classifier: ClipboardClassifier(ignoreSensitive: true, colorsWithoutHash: true))
        },
        onCapture: { [unowned self] content, imageData, app in
            captures.append(Capture(content: content, imageData: imageData, bundleID: app.bundleID, appName: app.name))
        }
    )

    static func text(_ string: String) -> PasteboardSnapshot {
        PasteboardSnapshot(types: ["public.utf8-plain-text"], string: string)
    }

    @Test func doesNotReadWhileTheChangeCountIsUnchanged() {
        monitor.start()
        scheduler.advance(by: .seconds(3))

        #expect(pasteboard.snapshotCount == 0)
        #expect(captures.isEmpty)
    }

    @Test func contentAlreadyThereAtStartIsNotCaptured() {
        pasteboard.copy(Self.text("before"))
        monitor.start()
        scheduler.advance(by: .seconds(1))

        #expect(pasteboard.snapshotCount == 0)
        #expect(captures.isEmpty)
    }

    @Test func aChangeIsCapturedOnceAtTheNextTickWithTheFrontmostAppAsSource() {
        monitor.start()
        pasteboard.copy(Self.text("Xin chào"))

        scheduler.advance(by: Self.interval - .milliseconds(1))
        #expect(captures.isEmpty)
        scheduler.advance(by: .milliseconds(1))
        frontmost = ("com.apple.TextEdit", "TextEdit")
        scheduler.advance(by: .seconds(1))

        #expect(captures == [Capture(content: .text("Xin chào"), imageData: nil, bundleID: "com.apple.Safari", appName: "Safari")])
        #expect(pasteboard.snapshotCount == 1)
    }

    @Test func everyChangeIsCaptured() {
        monitor.start()
        pasteboard.copy(Self.text("one"))
        scheduler.advance(by: Self.interval)
        pasteboard.copy(Self.text("two"))
        scheduler.advance(by: Self.interval)

        #expect(captures.map(\.content) == [.text("one"), .text("two")])
    }

    @Test func anImageIsCapturedWithItsPNGData() {
        monitor.start()
        pasteboard.copy(PasteboardSnapshot(types: ["public.png"], png: ClipboardClassifierTests.png))
        scheduler.advance(by: Self.interval)

        #expect(captures.count == 1)
        #expect(captures.first?.imageData == ClipboardClassifierTests.png)
    }

    @Test func whilePausedAChangeIsConsumedWithoutReading() {
        monitor.start()
        paused = true
        pasteboard.copy(Self.text("while paused"))
        scheduler.advance(by: Self.interval)
        paused = false
        scheduler.advance(by: Self.interval)

        #expect(pasteboard.snapshotCount == 0)
        #expect(captures.isEmpty)

        pasteboard.copy(Self.text("after"))
        scheduler.advance(by: Self.interval)
        #expect(captures.map(\.content) == [.text("after")])
    }

    @Test func aChangeWhileAnExcludedAppIsFrontmostIsNotRead() {
        excluded = ["com.1password.1password"]
        frontmost = ("com.1password.1password", "1Password")
        monitor.start()
        pasteboard.copy(Self.text("hunter2"))
        scheduler.advance(by: Self.interval)

        #expect(pasteboard.snapshotCount == 0)
        #expect(captures.isEmpty)
    }

    @Test func ownWritesAreReadButNotCaptured() {
        monitor.start()
        pasteboard.write(.text("again"), imageURL: nil, plainTextOnly: false)
        scheduler.advance(by: Self.interval)

        #expect(pasteboard.snapshotCount == 1)
        #expect(captures.isEmpty)
    }

    @Test func stopCancelsPolling() {
        monitor.start()
        scheduler.advance(by: Self.interval)
        monitor.stop()
        pasteboard.copy(Self.text("later"))
        scheduler.advance(by: .seconds(1))

        #expect(scheduler.pendingCount == 0)
        #expect(pasteboard.snapshotCount == 0)
        #expect(captures.isEmpty)
    }

    @Test func startingAgainKeepsASinglePoll() {
        monitor.start()
        monitor.start()

        #expect(scheduler.pendingCount == 1)
    }
}
