import Foundation
import Testing
@testable import TimerModule

@Suite struct TimerKindTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    // MARK: Types

    @Test func theThreeTypesHaveTheirOwnDefaultLength() {
        #expect(TimerKind.allCases == [.task, .reminder, .rest])
        #expect(TimerKind.task.defaultMinutes == 25)
        #expect(TimerKind.reminder.defaultMinutes == 10)
        #expect(TimerKind.rest.defaultMinutes == 5)
    }

    @Test func everyTypeHasItsOwnNameAndSymbol() {
        #expect(TimerKind.task.title == "Tập trung")
        #expect(TimerKind.reminder.title == "Nhắc việc")
        #expect(TimerKind.rest.title == "Nghỉ")
        #expect(Set(TimerKind.allCases.map(\.systemImage)).count == 3)
        #expect(Set(TimerKind.allCases.map { "\($0.accent)" }).count == 3)
    }

    @Test func theDefaultsFitTheDial() {
        for kind in TimerKind.allCases {
            #expect(TimerKind.minutesRange.contains(kind.defaultMinutes))
        }
        #expect(TimerKind.minutesRange == 1...60)
    }

    // MARK: Flow

    @Test func aTaskLeadsToABreakAndABreakBackToATaskButAReminderLeadsNowhere() {
        #expect(TimerKind.task.next == .rest)
        #expect(TimerKind.rest.next == .task)
        #expect(TimerKind.reminder.next == nil)
    }

    @Test func theSuggestionNamesTheBreakByItsLengthAndTheTaskByItsName() {
        #expect(TimerSuggestion(kind: .rest, minutes: 5).buttonTitle == "Nghỉ 5 phút")
        #expect(TimerSuggestion(kind: .rest, minutes: 15).buttonTitle == "Nghỉ 15 phút")
        #expect(TimerSuggestion(kind: .task, minutes: 25).buttonTitle == "Bắt đầu tập trung")
    }

    // MARK: Session

    @Test func aLabelIsTrimmedAndOnlyAReminderKeepsIt() {
        #expect(TimerSession(kind: .reminder, label: "  Gọi mẹ \n").label == "Gọi mẹ")
        #expect(TimerSession(kind: .reminder, label: "   ").label == "")
        #expect(TimerSession(kind: .task, label: "Gọi mẹ").label == "")
        #expect(TimerSession(kind: .rest, label: "Gọi mẹ").label == "")
    }

    @Test func aLongLabelIsCut() {
        let label = String(repeating: "a", count: 200)
        #expect(TimerSession(kind: .reminder, label: label).label.count == TimerSession.maxLabelLength)
    }

    @Test func aPlainSessionIsAReminderWithoutALabel() {
        #expect(TimerSession.plain == TimerSession(kind: .reminder, label: ""))
    }

    @Test func theRunningSummaryNamesTheTypeAndTheReminderLabel() {
        #expect(TimerSession(kind: .task, label: "").summary == "Tập trung")
        #expect(TimerSession(kind: .rest, label: "").summary == "Nghỉ")
        #expect(TimerSession(kind: .reminder, label: "").summary == "Nhắc việc")
        #expect(TimerSession(kind: .reminder, label: "Gọi mẹ").summary == "Nhắc việc: Gọi mẹ")
    }

    @Test func theFinishedTextCarriesTheReminderLabel() {
        #expect(TimerSession(kind: .reminder, label: "Gọi mẹ").finishedSummary == "Hết giờ: Gọi mẹ")
        #expect(TimerSession(kind: .reminder, label: "Gọi mẹ").finishedText == "Gọi mẹ")
        #expect(TimerSession(kind: .reminder, label: "").finishedSummary == "Hết giờ")
        #expect(TimerSession(kind: .reminder, label: "").finishedText == "Hết giờ")
        #expect(TimerSession(kind: .task, label: "").finishedSummary == "Hết giờ tập trung")
        #expect(TimerSession(kind: .rest, label: "").finishedSummary == "Hết giờ nghỉ")
        #expect(TimerSession(kind: .task, label: "").finishedText == "Hết giờ")
    }

    @Test func aSessionKeepsItsLabelAcrossEncoding() throws {
        let session = TimerSession(kind: .reminder, label: "Gọi mẹ")
        let decoded = try JSONDecoder().decode(TimerSession.self, from: JSONEncoder().encode(session))
        #expect(decoded == session)
    }

    @Test func aSessionReadFromAFileIsNormalizedLikeOneMadeInCode() throws {
        let json = Data(#"{"kind":"task","label":"leftover"}"#.utf8)
        #expect(try JSONDecoder().decode(TimerSession.self, from: json) == TimerSession(kind: .task, label: ""))
    }

    // MARK: Stored form

    @Test func theStoredTimerRoundTripsEveryState() throws {
        let session = TimerSession(kind: .reminder, label: "Gọi mẹ")
        for model in [TimerModel.idle, .countdown(endDate: t0), .countdownPaused(remaining: 9), .finished,
                      .stopwatch(accumulated: 3, startedAt: t0), .stopwatchPaused(accumulated: 4)] {
            let stored = StoredTimer(model: model, session: session)
            let decoded = try JSONDecoder().decode(StoredTimer.self, from: JSONEncoder().encode(stored))
            #expect(decoded == stored)
        }
    }

    @Test func aTimerFileFromBeforeTheTypesStillLoadsAsAPlainTimer() throws {
        for model in [TimerModel.idle, .countdown(endDate: t0), .countdownPaused(remaining: 9), .finished,
                      .stopwatch(accumulated: 3, startedAt: t0), .stopwatchPaused(accumulated: 4)] {
            let legacy = try JSONEncoder().encode(model)
            let decoded = try JSONDecoder().decode(StoredTimer.self, from: legacy)
            #expect(decoded == StoredTimer(model: model, session: .plain))
        }
    }

    @Test func aStoredTimerWithoutASessionLoadsAsAPlainTimer() throws {
        let model = try JSONEncoder().encode(TimerModel.countdownPaused(remaining: 9))
        let json = Data(#"{"model":"#.utf8) + model + Data("}".utf8)
        #expect(try JSONDecoder().decode(StoredTimer.self, from: json) == StoredTimer(model: .countdownPaused(remaining: 9), session: .plain))
    }

    @Test func garbageIsStillRejected() {
        #expect(throws: (any Error).self) { try JSONDecoder().decode(StoredTimer.self, from: Data("nope".utf8)) }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(StoredTimer.self, from: Data(#"{"model":{"bogus":1}}"#.utf8)) }
    }
}
