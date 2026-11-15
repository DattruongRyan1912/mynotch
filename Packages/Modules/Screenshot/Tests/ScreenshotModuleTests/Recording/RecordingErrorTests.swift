import Foundation
import ScreenCaptureKit
import Testing
@testable import ScreenshotModule

@Suite struct RecordingErrorTests {
    private func streamError(_ code: SCStreamError.Code) -> NSError {
        NSError(domain: SCStreamErrorDomain, code: code.rawValue)
    }

    @Test func aDeclinedStreamIsAMissingScreenRecordingPermission() {
        #expect(RecordingError(streamError(.userDeclined)) == .screenRecordingDenied)
    }

    @Test func aMicrophoneThatCouldNotStartIsAMissingMicrophonePermission() {
        #expect(RecordingError(streamError(.failedToStartMicrophoneCapture)) == .microphoneDenied)
    }

    @Test func noDisplayListIsNoDisplay() {
        #expect(RecordingError(streamError(.noDisplayList)) == .noDisplay)
    }

    @Test func theSystemsOwnStopIsNotAFailure() {
        #expect(RecordingError(streamError(.userStopped)) == .stoppedBySystem)
        #expect(RecordingError(streamError(.systemStoppedStream)) == .stoppedBySystem)
    }

    @Test func anyOtherErrorKeepsItsDescription() {
        let other = NSError(domain: "Elsewhere", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])

        #expect(RecordingError(other) == .failed("boom"))
        #expect(RecordingError(streamError(.internalError)) != .screenRecordingDenied)
    }

    @Test func aRecordingErrorStaysAsItIs() {
        #expect(RecordingError(RecordingError.nothingRecorded) == .nothingRecorded)
    }

    @Test func everyErrorHasAMessageForTheUser() {
        let all: [RecordingError] = [
            .screenRecordingDenied, .microphoneDenied, .noDisplay, .encoderUnavailable("x"), .writerFailed("x"),
            .nothingRecorded, .alreadyRecording, .stoppedBySystem, .failed("x"),
        ]

        #expect(all.allSatisfy { !$0.message.isEmpty })
        #expect(Set(all.map(\.message)).count == all.count)
    }
}
