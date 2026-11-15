import AppKit
import Testing
@testable import SystemActivitiesModule

/// The notifications are posted in this process only; nothing about the displays, the audio or the Mac itself changes.
/// Serialized because every notifier hears every post.
@Suite(.serialized) struct HardwareChangeNotifierTests {
    /// Gives the main queue the turns it needs to deliver a notification.
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func aDisplayChangeOrAWakeIsReportedWhileListeningAndNotAfter() async {
        let notifier = HardwareChangeNotifier()
        var reports = 0
        notifier.start { reports += 1 }

        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        await settle { reports == 1 }
        #expect(reports == 1)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        await settle { reports == 2 }
        #expect(reports == 2)

        notifier.stop()
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        // Nothing to wait for: give a late delivery a moment to show up.
        try? await Task.sleep(for: .milliseconds(100))
        #expect(reports == 2)
    }

    @Test func startingAgainReplacesTheEarlierListener() async {
        let notifier = HardwareChangeNotifier()
        var first = 0
        var second = 0
        notifier.start { first += 1 }
        notifier.start { second += 1 }
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        await settle { second == 1 }
        #expect((first, second) == (0, 1))
        notifier.stop()
    }
}
