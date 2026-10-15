import MyNotchCore
import Testing
@testable import TodoModule

/// What the module writes to the log is made of codes only, so a title the user typed can never get there.
@Suite struct TodoLogTests {
    @Test func statusesAreWrittenAsCodes() {
        #expect(TodoLog.code(.granted) == "granted")
        #expect(TodoLog.code(.denied) == "denied")
        #expect(TodoLog.code(.notDetermined) == "notDetermined")
        #expect(TodoLog.code(.unknown) == "unknown")
    }

    @Test func phasesAreWrittenAsCodes() {
        #expect(TodoLog.code(TodoState.Phase.loading) == "loading")
        #expect(TodoLog.code(TodoState.Phase.ready) == "ready")
        #expect(TodoLog.code(TodoState.Phase.needsAccess) == "needsAccess")
    }

    @Test func eachLineSaysOnlyWhatHappenedAndHowMany() {
        #expect(TodoLog.refresh(status: .notDetermined) == "refresh status=notDetermined")
        #expect(TodoLog.phase(from: .needsAccess, to: .ready) == "phase needsAccess -> ready")
        #expect(TodoLog.read(lists: 3, incomplete: 7, completed: 2, items: 6) == "read lists=3 incomplete=7 completed=2 items=6")
        #expect(TodoLog.request(before: .notDetermined, after: .notDetermined) == "access request before=notDetermined after=notDetermined")
        #expect(TodoLog.recheck(status: .granted, polls: 3) == "access recheck status=granted polls=3")
        #expect(TodoLog.storeRenewed == "store renewed after access was granted")
    }
}
