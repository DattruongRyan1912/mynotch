import FanHelperKit
import Foundation
import ServiceManagement
import Testing
@testable import PerformanceModule

/// Nothing here touches the system: the registration and the helper are fakes. What the tests pin is what the manager asks of
/// them, and above all when it does not.
@Suite struct FanHelperManagerTests {
    struct Boom: Error {}

    // MARK: Looking

    @Test func eachRegistrationStatusIsAPhase() async {
        for (status, phase) in [
            (FanHelperRegistrationStatus.notRegistered, FanHelperPhase.notInstalled), (.requiresApproval, .needsApproval), (.notFound, .notInstalled),
        ] {
            let rig = HelperRig(status: status)
            await rig.manager.refresh()
            #expect(rig.manager.phase == phase, "\(status)")
            #expect(rig.client.pingCount == 0, "a helper that is not enabled is not called: \(status)")
        }
    }

    @Test func anEnabledHelperIsPingedAndIsRunningWhenItAnswersAsRoot() async {
        let rig = HelperRig(status: .enabled)
        await rig.manager.refresh()
        #expect(rig.manager.phase == .running(.matching))
        #expect(rig.client.pingCount == 1)
    }

    @Test func anEnabledHelperThatDoesNotAnswerIsUnreachable() async {
        let rig = HelperRig(status: .enabled, pings: [.failure(.timeout)])
        await rig.manager.refresh()
        #expect(rig.manager.phase == .unreachable("helper không trả lời"))
    }

    @Test func aHelperThatAnswersButIsNotRootIsAnError() async {
        let rig = HelperRig(status: .enabled, pings: [.success(FanHelperInfo(version: "1", buildID: "aaaa", euid: 501, pid: 5))])
        await rig.manager.refresh()
        #expect(rig.manager.phase == .failed("helper không chạy với quyền root (euid 501)"))
    }

    @Test func aHelperKnownToBeRunningIsNotPingedAgainEachTimeTheTabOpens() async {
        let rig = HelperRig(status: .enabled)
        await rig.manager.refresh()
        await rig.manager.refresh()
        await rig.manager.refresh()
        #expect(rig.client.pingCount == 1)
    }

    @Test func aHelperTheUserSwitchedOffInSystemSettingsIsNoticedByTheNextLook() async {
        let rig = HelperRig(status: .enabled)
        await rig.manager.refresh()
        rig.registration.status = .requiresApproval
        await rig.manager.refresh()
        #expect(rig.manager.phase == .needsApproval)
    }

    @Test func approvingInSystemSettingsIsNoticedByTheNextLook() async {
        let rig = HelperRig(status: .requiresApproval)
        await rig.manager.refresh()
        #expect(rig.manager.phase == .needsApproval)
        rig.registration.status = .enabled
        await rig.manager.refresh()
        #expect(rig.manager.phase == .running(.matching))
    }

    @Test func lookingNeverRegistersAnything() async {
        for status in [FanHelperRegistrationStatus.notRegistered, .enabled, .requiresApproval, .notFound] {
            let rig = HelperRig(status: status)
            await rig.manager.refresh()
            await rig.manager.checkAtLaunch()
            #expect(rig.registration.calls.isEmpty, "\(status)")
        }
    }

    // MARK: Not found yet

    func smError(_ code: Int, _ description: String = "x") -> NSError {
        NSError(domain: FanHelperManager.serviceManagementDomain, code: code, userInfo: [NSLocalizedDescriptionKey: description])
    }

    /// On macOS 26.5 a daemon that was never registered reads `.notFound`; it must not look like an error with nothing to press.
    @Test func aDaemonMacOSCallsNotFoundBeforeTheFirstRegisterIsOfferedForInstall() async {
        let rig = HelperRig(status: .notFound)
        await rig.manager.refresh()
        #expect(rig.manager.phase == .notInstalled)
        let presentation = rig.manager.presentation
        #expect(presentation.status == "Chưa cài")
        #expect(presentation.primary == .install && presentation.tone == nil)
        #expect(rig.registration.calls.isEmpty)
    }

    @Test func notFoundAtLaunchIsTheSameAndNothingIsRegistered() async {
        let rig = HelperRig(status: .notFound)
        await rig.manager.checkAtLaunch()
        #expect(rig.manager.phase == .notInstalled)
        #expect(rig.registration.calls.isEmpty && rig.client.pingCount == 0)
    }

    @Test func installingFromNotFoundThatWorksReachesTheHelper() async {
        let rig = HelperRig(status: .notFound)
        await rig.manager.install()
        #expect(rig.registration.calls == [.register])
        #expect(rig.manager.phase == .running(.matching))
    }

    @Test func aRegisterThatThrowsWhileMacOSSaysNotFoundIsTheFirstErrorAndOffersAnotherTry() async {
        let rig = HelperRig(status: .notFound)
        rig.registration.statusAfterRegister = .notFound
        rig.registration.registerError = smError(kSMErrorJobPlistNotFound)
        await rig.manager.install()
        #expect(rig.manager.phase == .failed("không tìm thấy file plist của helper trong ứng dụng (SMAppService 8)"))
        let presentation = rig.manager.presentation
        #expect(presentation.status == "Lỗi: không tìm thấy file plist của helper trong ứng dụng (SMAppService 8)")
        #expect(presentation.primary == .retry && presentation.tone == .critical)
        #expect(presentation.shortStatus == "lỗi")
    }

    @Test func theErrorStaysOnScreenWhenTheTabOrSettingsLooksAgain() async {
        let rig = HelperRig(status: .notFound)
        rig.registration.statusAfterRegister = .notFound
        rig.registration.registerError = smError(kSMErrorInvalidSignature)
        await rig.manager.install()
        let failed = rig.manager.phase
        for _ in 0..<3 { await rig.manager.refresh() }
        #expect(rig.manager.phase == failed)
        #expect(rig.registration.calls == [.register], "looking does not register")
    }

    @Test func tryingAgainAfterThatErrorRegistersAgain() async {
        let rig = HelperRig(status: .notFound)
        rig.registration.statusAfterRegister = .notFound
        rig.registration.registerError = smError(kSMErrorServiceUnavailable)
        await rig.manager.install()
        await rig.manager.retry()
        #expect(rig.registration.calls == [.register, .register])
        rig.registration.registerError = nil
        rig.registration.statusAfterRegister = .enabled
        await rig.manager.retry()
        #expect(rig.manager.phase == .running(.matching))
    }

    @Test func aRegisterThatThrowsLaunchDeniedMeansTheUserMustAllowItWhateverTheStatusSays() async {
        let rig = HelperRig(status: .notFound)
        rig.registration.statusAfterRegister = .notFound
        rig.registration.registerError = smError(kSMErrorLaunchDeniedByUser)
        await rig.manager.install()
        #expect(rig.manager.phase == .needsApproval)
        #expect(rig.manager.presentation.primary == .openSettings)
    }

    @Test func aRegisterThatThrowsAlreadyRegisteredCarriesOnToTheHelper() async {
        let rig = HelperRig(status: .notFound)
        rig.registration.statusAfterRegister = .enabled
        rig.registration.registerError = smError(kSMErrorAlreadyRegistered)
        await rig.manager.install()
        #expect(rig.manager.phase == .running(.matching))
    }

    @Test func aRegisterThatReturnsButLeavesNothingRegisteredIsAnErrorNotASilentNoOp() async {
        let rig = HelperRig(status: .notFound)
        rig.registration.statusAfterRegister = .notFound
        await rig.manager.install()
        #expect(rig.manager.phase == .failed(FanHelperManager.notAccepted))
        #expect(rig.manager.presentation.primary == .retry)
    }

    @Test func removingWhenNothingIsRegisteredAsksMacOSForNothing() async {
        for status in [FanHelperRegistrationStatus.notFound, .notRegistered] {
            let rig = HelperRig(status: status)
            rig.registration.registerError = nil
            await rig.manager.uninstall()
            #expect(rig.registration.calls.isEmpty, "\(status)")
            #expect(rig.manager.phase == .notInstalled)
        }
    }

    @Test func removingAfterAFailedAttemptJustGoesBackToNotInstalled() async {
        let rig = HelperRig(status: .notFound)
        rig.registration.statusAfterRegister = .notFound
        rig.registration.registerError = smError(kSMErrorInvalidSignature)
        await rig.manager.install()
        await rig.manager.uninstall()
        #expect(rig.registration.calls == [.register])
        #expect(rig.manager.phase == .notInstalled, "nothing to remove: back to not installed, ready for a new try")
    }

    @Test func theJobNotFoundCodeIsRecognisedOnlyInTheServiceManagementDomain() {
        #expect(FanHelperManager.isJobNotFound(smError(kSMErrorJobNotFound)))
        #expect(FanHelperManager.isJobNotFound(NSError(domain: "other", code: kSMErrorJobNotFound)) == false)
        #expect(FanHelperManager.isJobNotFound(smError(kSMErrorInternalFailure)) == false)
    }

    @Test func eachServiceManagementCodeHasAReasonWithItsNumber() {
        #expect(FanHelperManager.describe(smError(kSMErrorInvalidSignature)) == "chữ ký của ứng dụng không hợp lệ (SMAppService 3)")
        #expect(FanHelperManager.describe(smError(kSMErrorLaunchDeniedByUser)) == "chưa được cho phép trong Cài đặt hệ thống (SMAppService 11)")
        #expect(FanHelperManager.describe(smError(kSMErrorJobPlistNotFound)).hasSuffix("(SMAppService 8)"))
    }

    @Test func anErrorWeHaveNoWordsForShowsItsDescriptionWithItsPathsTakenOut() {
        let error = smError(99, "Could not load /Applications/MyNotch.app/Contents/Library/LaunchDaemons/x.plist now")
        let text = FanHelperManager.describe(error)
        #expect(text == "Could not load … now (SMAppServiceErrorDomain 99)")
        #expect(text.contains("/") == false)
    }

    @Test func aPathInAnyDescriptionNeverReachesTheScreen() {
        #expect(FanHelperManager.withoutPaths("a /b/c d") == "a … d")
        #expect(FanHelperManager.withoutPaths("no path here") == "no path here")
        #expect(FanHelperManager.withoutPaths("/only") == "…")
    }

    // MARK: Install and remove

    @Test func installingRegistersThenPingsTheHelper() async {
        let rig = HelperRig(status: .notRegistered)
        await rig.manager.install()
        #expect(rig.registration.calls == [.register])
        #expect(rig.manager.phase == .running(.matching))
    }

    @Test func installingWhenTheSystemWantsApprovalWaitsForTheUser() async {
        let rig = HelperRig(status: .notRegistered)
        rig.registration.statusAfterRegister = .requiresApproval
        await rig.manager.install()
        #expect(rig.manager.phase == .needsApproval)
        #expect(rig.client.pingCount == 0)
    }

    @Test func aRegisterThatThrowsWhileTheStatusSaysApprovalIsNeededIsNotAnError() async {
        let rig = HelperRig(status: .notRegistered)
        rig.registration.statusAfterRegister = .requiresApproval
        rig.registration.registerError = Boom()
        await rig.manager.install()
        #expect(rig.manager.phase == .needsApproval)
    }

    @Test func aRegisterThatThrowsAndLeavesNothingRegisteredIsAnError() async {
        let rig = HelperRig(status: .notRegistered)
        rig.registration.statusAfterRegister = .notRegistered
        rig.registration.registerError = NSError(domain: "SMAppServiceErrorDomain", code: 1, userInfo: [NSLocalizedDescriptionKey: "Operation not permitted"])
        await rig.manager.install()
        #expect(rig.manager.phase == .failed("Operation not permitted (SMAppServiceErrorDomain 1)"))
    }

    @Test func aRegisterThatThrowsAlreadyRegisteredIsAsGoodAsRegistered() async {
        let rig = HelperRig(status: .enabled, pings: [.failure(.timeout), .success(.matching)])
        await rig.manager.refresh()
        #expect(rig.manager.phase == .unreachable("helper không trả lời"))
        rig.registration.registerError = Boom()
        await rig.manager.install()
        #expect(rig.manager.phase == .running(.matching))
    }

    @Test func removingUnregistersAndShowsNotInstalled() async {
        let rig = HelperRig(status: .enabled)
        await rig.manager.refresh()
        await rig.manager.uninstall()
        #expect(rig.registration.calls == [.unregister])
        #expect(rig.manager.phase == .notInstalled)
        #expect(rig.manager.comparison == nil)
    }

    @Test func aRemovalThatFailsIsShown() async {
        let rig = HelperRig(status: .enabled)
        rig.registration.unregisterError = Boom()
        await rig.manager.uninstall()
        if case .failed = rig.manager.phase {} else { Issue.record("expected a failure, got \(rig.manager.phase)") }
    }

    @Test func openingSystemSettingsOnlyOpensThem() async {
        let rig = HelperRig(status: .requiresApproval)
        rig.manager.openSystemSettings()
        #expect(rig.registration.calls == [.openSystemSettings])
    }

    @Test func tryingAgainInstallsWhenNothingIsRegisteredAndOtherwiseLooksAgain() async {
        let rig = HelperRig(status: .notRegistered)
        await rig.manager.retry()
        #expect(rig.registration.calls == [.register])
        let enabled = HelperRig(status: .enabled, pings: [.failure(.timeout), .success(.matching)])
        await enabled.manager.refresh()
        await enabled.manager.retry()
        #expect(enabled.registration.calls.isEmpty)
        #expect(enabled.manager.phase == .running(.matching))
    }

    // MARK: When the app starts

    @Test func aHelperThatWasNeverInstalledIsLeftAlone() async {
        let rig = HelperRig(status: .notRegistered, pings: [.success(.oldBuild)])
        await rig.manager.checkAtLaunch()
        #expect(rig.registration.calls.isEmpty && rig.client.pingCount == 0)
        #expect(rig.manager.phase == .notInstalled)
    }

    @Test func aHelperWaitingForApprovalIsLeftAlone() async {
        let rig = HelperRig(status: .requiresApproval)
        await rig.manager.checkAtLaunch()
        #expect(rig.registration.calls.isEmpty && rig.client.pingCount == 0)
        #expect(rig.manager.phase == .needsApproval)
    }

    @Test func aHelperThatIsTheBundledOneIsLeftAlone() async {
        let rig = HelperRig(status: .enabled)
        await rig.manager.checkAtLaunch()
        #expect(rig.registration.calls.isEmpty)
        #expect(rig.manager.phase == .running(.matching))
    }

    @Test func aHelperThatDoesNotAnswerIsReportedNotRegisteredAgain() async {
        let rig = HelperRig(status: .enabled, pings: [.failure(.timeout)])
        await rig.manager.checkAtLaunch()
        #expect(rig.registration.calls.isEmpty)
        #expect(rig.manager.phase == .unreachable("helper không trả lời"))
    }

    @Test func anOutdatedHelperIsUnregisteredThenAfterAPauseRegisteredAndPingedAgain() async {
        let rig = HelperRig(status: .enabled, pings: [.success(.oldBuild), .success(.matching)])
        await rig.manager.checkAtLaunch()
        #expect(rig.registration.calls == [.unregister, .register])
        #expect(rig.pauses.durations == [.seconds(1)])
        #expect(rig.client.pingCount == 2)
        #expect(rig.manager.phase == .running(.matching))
    }

    @Test func theNewHelperAskingForApprovalAgainIsAnOrdinaryOutcome() async {
        let rig = HelperRig(status: .enabled, pings: [.success(.oldBuild)])
        rig.registration.statusAfterRegister = .requiresApproval
        await rig.manager.checkAtLaunch()
        #expect(rig.registration.calls == [.unregister, .register])
        #expect(rig.manager.phase == .needsApproval)
    }

    @Test func anOldHelperThatKeepsRunningAfterTheAttemptIsAnErrorTellingTheUserWhatToDo() async {
        let rig = HelperRig(status: .enabled, pings: [.success(.oldBuild)])
        await rig.manager.checkAtLaunch()
        #expect(rig.manager.phase == .failed(FanHelperManager.stillOutdated))
        #expect(FanHelperManager.stillOutdated.contains("Gỡ helper"))
    }

    @Test func itTriesOnceInALaunchAndNeverInALoop() async {
        let rig = HelperRig(status: .enabled, pings: [.success(.oldBuild)])
        await rig.manager.checkAtLaunch()
        let calls = rig.registration.calls
        for _ in 0..<3 {
            await rig.manager.checkAtLaunch()
            await rig.manager.refresh()
        }
        #expect(calls == [.unregister, .register])
        #expect(rig.registration.calls == calls, "no second attempt")
    }

    @Test func aFailedUnregisterDuringTheUpdateStopsThereWithAnError() async {
        let rig = HelperRig(status: .enabled, pings: [.success(.oldBuild)])
        rig.registration.unregisterError = Boom()
        await rig.manager.checkAtLaunch()
        #expect(rig.registration.calls == [.unregister])
        if case .failed = rig.manager.phase {} else { Issue.record("expected a failure, got \(rig.manager.phase)") }
    }

    @Test func aRegisterThatFailsAfterTheUpdateLeavesAnError() async {
        let rig = HelperRig(status: .enabled, pings: [.success(.oldBuild)])
        rig.registration.statusAfterRegister = .notRegistered
        rig.registration.registerError = Boom()
        await rig.manager.checkAtLaunch()
        if case .failed = rig.manager.phase {} else { Issue.record("expected a failure, got \(rig.manager.phase)") }
    }

    // MARK: Macs Fan Control and the comparison

    @Test func macsFanControlIsNoticedByItsBundleIdentifier() async {
        #expect(FanHelperManager.macsFanControlBundleID == "com.crystalidea.macsfancontrol")
        let running = HelperRig(runningApps: ["com.apple.finder", "com.crystalidea.macsfancontrol"])
        await running.manager.refresh()
        #expect(running.manager.macsFanControlRunning)
        let absent = HelperRig(runningApps: ["com.apple.finder"])
        await absent.manager.refresh()
        #expect(absent.manager.macsFanControlRunning == false)
    }

    @Test func comparingReadsTheFansThroughTheHelperAndSetsThemBesideTheApps() async {
        let rig = HelperRig(status: .enabled)
        rig.client.answerFans(.success(FanHelperFanInfo.both))
        await rig.manager.refresh()
        await rig.manager.compareFans(app: [FanReading(index: 0, rpm: 5170, minRPM: 1200, maxRPM: 5779)])
        #expect(rig.client.readCount == 1)
        #expect(rig.manager.comparison?.lines.first == "Quạt 1: helper 5173 · app 5170 vòng/phút · tự động")
        #expect(rig.manager.comparison?.lines.last == "Quạt 2: helper 5636 · app — vòng/phút · tự động")
    }

    @Test func comparingWithoutARunningHelperDoesNothing() async {
        let rig = HelperRig(status: .requiresApproval)
        await rig.manager.refresh()
        await rig.manager.compareFans(app: [])
        #expect(rig.client.readCount == 0 && rig.manager.comparison == nil)
    }

    @Test func aComparisonThatFailsShowsWhyAndMarksTheHelperUnreachable() async {
        let rig = HelperRig(status: .enabled)
        rig.client.answerFans(.failure(.helperFailed("cannot open the SMC")))
        await rig.manager.refresh()
        await rig.manager.compareFans(app: [])
        #expect(rig.manager.comparison?.failure == "helper báo: cannot open the SMC")
        #expect(rig.manager.phase == .unreachable("helper báo: cannot open the SMC"))
    }

    @Test func theErrorsHaveShortVietnameseReasons() {
        #expect(FanHelperManager.describe(FanHelperError.timeout) == "helper không trả lời")
        #expect(FanHelperManager.describe(FanHelperError.noProxy) == "không mở được kết nối")
        #expect(FanHelperManager.describe(NSError(domain: NSCocoaErrorDomain, code: 4099)) == "không có helper nào trả lời")
        #expect(FanHelperManager.describe(NSError(domain: NSCocoaErrorDomain, code: 4097)) == "không có helper nào trả lời")
    }
}
