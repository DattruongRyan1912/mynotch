import EventKit
import Foundation
import MyNotchCore
import Testing
@testable import TodoModule

/// The real service with its authorization faked: without access it must answer before touching EventKit, so these run
/// without a prompt, a permission or an event store. Nothing here reads or writes the real Reminders database.
@Suite struct TodoServiceTests {
    let denied = TodoService(authorizationStatus: { .denied })

    @Test func withoutAccessThereAreNoListsOrReminders() async {
        #expect(await denied.lists().isEmpty)
        #expect(await denied.incomplete(dueBy: .now, undatedIn: "inbox").isEmpty)
        #expect(await denied.completed(from: .now, to: .now.addingTimeInterval(3_600)).isEmpty)
    }

    @Test func completingWithoutAccessSaysAccessWasDenied() async {
        await #expect(throws: TodoServiceError.accessDenied) {
            try await denied.setCompleted(true, reminderID: "r1")
        }
    }

    @Test func savingWithoutAccessSaysAccessWasDeniedBeforeTouchingEventKit() async {
        let new = NewTodo(title: "Mua sữa", due: due(14), priority: .none, listID: nil)
        await #expect(throws: TodoServiceError.accessDenied) {
            try await denied.create(new)
        }
        // Write-only access cannot read reminders, so it counts as denied here too.
        let notAsked = TodoService(authorizationStatus: { .notDetermined })
        await #expect(throws: TodoServiceError.accessDenied) {
            try await notAsked.create(new)
        }
    }

    @Test func theSystemStatusMapsFullAccessToGrantedAndEverythingElseToNotGranted() {
        #expect(TodoService.status(of: .fullAccess) == .granted)
        #expect(TodoService.status(of: .notDetermined) == .notDetermined)
        #expect(TodoService.status(of: .denied) == .denied)
        #expect(TodoService.status(of: .restricted) == .denied)
        #expect(TodoService.status(of: .writeOnly) == .denied)
    }

    @Test(.timeLimit(.minutes(1)))
    func aBurstOfStoreChangesIsOneSignal() async {
        let center = NotificationCenter()
        let quiet = Duration.milliseconds(300)
        let service = TodoService(authorizationStatus: { .granted }, notificationCenter: center, changeQuietPeriod: quiet)
        let signals = Counter()
        let consumer = Task { for await _ in service.changes { signals.increment() } }
        defer { consumer.cancel() }

        // The stream listens a moment after it is made; probe until it does, then let that signal pass.
        while signals.value == 0 {
            center.post(name: .EKEventStoreChanged, object: nil)
            try? await Task.sleep(for: .milliseconds(20))
        }
        try? await Task.sleep(for: quiet * 2)
        let before = signals.value

        for _ in 1...5 { center.post(name: .EKEventStoreChanged, object: nil) }
        await settle { signals.value > before }
        try? await Task.sleep(for: quiet * 2)

        #expect(signals.value == before + 1)
    }

    @Test func theDefaultQuietPeriodIsOneSecond() {
        #expect(TodoService.changeQuietPeriod == .seconds(1))
    }
}
