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
        var isSensitive = false
    }

    static let interval: Duration = .milliseconds(300)

    let pasteboard = FakePasteboard()
    let scheduler = ManualScheduler()
    var paused = false
    var excluded: Set<String> = []
    var ignoreSensitive = true
    var frontmost: (bundleID: String?, name: String?) = ("com.apple.Safari", "Safari")
    var captures: [Capture] = []
    var stopOnCapture = false

    lazy var monitor: ClipboardMonitor = ClipboardMonitor(
        pasteboard: pasteboard, scheduler: scheduler,
        frontmostApp: { [unowned self] in frontmost },
        shouldCapture: { [unowned self] in
            (paused: paused, excluded: excluded, classifier: ClipboardClassifier(ignoreSensitive: ignoreSensitive, colorsWithoutHash: true))
        },
        onCapture: { [unowned self] content, imageData, app, isSensitive in
            captures.append(Capture(
                content: content, imageData: imageData, bundleID: app.bundleID, appName: app.name, isSensitive: isSensitive
            ))
            if stopOnCapture { monitor.stop() }
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

    @Test func aChangeIsCapturedOnceAtTheNextTick() {
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

    /// With "ignore sensitive" off the history keeps a secret, but the capture still says it is one.
    @Test func aCopyMarkedSensitiveIsReportedAsSuchWhenTheSettingKeepsIt() {
        ignoreSensitive = false
        monitor.start()
        pasteboard.copy(PasteboardSnapshot(types: ["org.nspasteboard.ConcealedType", "public.utf8-plain-text"], string: "hunter2"))
        scheduler.advance(by: Self.interval)
        pasteboard.copy(Self.text("Xin chào"))
        scheduler.advance(by: Self.interval)

        #expect(captures.map(\.isSensitive) == [true, false])
        #expect(captures.map(\.content) == [.text("hunter2"), .text("Xin chào")])
    }

    /// Passwords.app writes only public.utf8-plain-text, no marker, so the app in front is what tells.
    @Test(arguments: ["com.apple.Passwords", "com.1password.1password"])
    func aCopyFromAPasswordManagerIsNotReadWhenSensitiveCopiesAreIgnored(bundleID: String) {
        frontmost = (bundleID, nil)
        monitor.start()
        pasteboard.copy(Self.text("hunter2"))
        scheduler.advance(by: Self.interval)

        #expect(pasteboard.snapshotCount == 0)
        #expect(captures.isEmpty)
    }

    @Test func aCopyFromAPasswordManagerIsReportedSensitiveWhenTheSettingKeepsIt() {
        ignoreSensitive = false
        frontmost = ("com.apple.Passwords", "Passwords")
        monitor.start()
        pasteboard.copy(Self.text("hunter2"))
        scheduler.advance(by: Self.interval)

        #expect(captures == [Capture(
            content: .text("hunter2"), imageData: nil, bundleID: "com.apple.Passwords", appName: "Passwords", isSensitive: true
        )])
    }

    /// The copy happened between two ticks, so a password manager in front at either tick makes it a secret.
    @Test(arguments: [true, false], [("com.apple.Passwords", "com.apple.Safari"), ("com.apple.Safari", "com.apple.Passwords")])
    func aCopyAcrossASwitchWithAPasswordManagerIsASecret(ignoreSensitive: Bool, apps: (before: String, after: String)) {
        self.ignoreSensitive = ignoreSensitive
        frontmost = (apps.before, nil)
        monitor.start()
        pasteboard.copy(Self.text("hunter2"))
        frontmost = (apps.after, nil)
        scheduler.advance(by: Self.interval)

        #expect(captures.map(\.isSensitive) == (ignoreSensitive ? [] : [true]))
    }

    @Test func plainTextFromAnotherAppIsNotASecret() {
        monitor.start()
        pasteboard.copy(Self.text("Xin chào"))
        scheduler.advance(by: Self.interval)

        #expect(captures.map(\.isSensitive) == [false])
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

    @Test func aCopyIsAttributedToTheAppInFrontAtThePreviousTick() {
        monitor.start()
        frontmost = ("com.apple.Notes", "Notes")
        scheduler.advance(by: Self.interval)
        pasteboard.copy(Self.text("from Notes"))
        frontmost = ("com.apple.TextEdit", "TextEdit")
        scheduler.advance(by: Self.interval)

        #expect(captures == [Capture(content: .text("from Notes"), imageData: nil, bundleID: "com.apple.Notes", appName: "Notes")])
    }

    /// The copy happened between two ticks, so it is skipped when the app in front at either tick is excluded.
    @Test(arguments: zip(
        ["com.1password.1password", "com.apple.Safari"],
        ["com.apple.Safari", "com.1password.1password"]
    ))
    func aCopyAcrossAnAppSwitchIsSkippedWhenEitherAppIsExcluded(before: String, after: String) {
        excluded = ["com.1password.1password"]
        frontmost = (before, nil)
        monitor.start()
        pasteboard.copy(Self.text("hunter2"))
        frontmost = (after, nil)
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

    @Test func stopFromInsideOnCaptureLeavesNoPendingTick() {
        stopOnCapture = true
        monitor.start()
        pasteboard.copy(Self.text("last"))
        scheduler.advance(by: Self.interval)
        pasteboard.copy(Self.text("ignored"))
        scheduler.advance(by: .seconds(1))

        #expect(scheduler.pendingCount == 0)
        #expect(captures.map(\.content) == [.text("last")])
        #expect(pasteboard.snapshotCount == 1)
    }

    @Test func startingAgainKeepsASinglePoll() {
        monitor.start()
        monitor.start()

        #expect(scheduler.pendingCount == 1)
    }
}
