import Foundation
import ScreenCaptureKit
import Testing
@testable import ScreenshotModule

@Suite struct CaptureErrorTests {
    func screenCaptureKitError(_ code: SCStreamError.Code) -> NSError {
        NSError(domain: SCStreamErrorDomain, code: code.rawValue, userInfo: [NSLocalizedDescriptionKey: "sck \(code.rawValue)"])
    }

    @Test func userDeclinedMeansNoPermission() {
        #expect(CaptureError(screenCaptureKitError(.userDeclined)) == .permissionDenied)
    }

    @Test func missingDisplaysAreTold() {
        #expect(CaptureError(screenCaptureKitError(.noDisplayList)) == .noDisplays)
    }

    @Test func otherScreenCaptureKitErrorsKeepTheirDescription() {
        #expect(CaptureError(screenCaptureKitError(.failedToStart)) == .failed("sck -3802"))
        #expect(CaptureError(NSError(domain: NSCocoaErrorDomain, code: 4, userInfo: [NSLocalizedDescriptionKey: "gone"])) == .failed("gone"))
    }

    @Test func ownErrorsPassThrough() {
        #expect(CaptureError(CaptureError.noDisplays) == .noDisplays)
        #expect(CaptureError(CaptureError.failed("x")) == .failed("x"))
    }

    @Test func aDeclinedErrorFromAnotherDomainIsNotAPermissionProblem() {
        #expect(CaptureError(NSError(domain: "Other", code: SCStreamError.Code.userDeclined.rawValue)) != .permissionDenied)
    }
}
