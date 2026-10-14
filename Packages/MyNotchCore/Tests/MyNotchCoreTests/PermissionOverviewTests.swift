import Observation
import os
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

private nonisolated final class ChangeCount: Sendable {
    private let value = OSAllocatedUnfairLock(initialState: 0)
    var count: Int { value.withLock { $0 } }
    func bump() { value.withLock { $0 += 1 } }
}

@Suite(.timeLimit(.minutes(1))) struct PermissionOverviewTests {
    /// A prompt the user has not answered yet: `request` waits at the returned gate until the test opens it.
    private func openPrompt(on harness: Harness) -> Gate {
        let gate = Gate()
        harness.permissions.awaitAnswer = { await gate.wait() }
        return gate
    }

    /// Bounded, so a request that never arrives fails the test instead of spinning forever.
    private func waitForPrompt(_ gate: Gate) async {
        for _ in 0..<1000 where gate.waiting == 0 { await Task.yield() }
        #expect(gate.waiting > 0)
    }

    private func overview(_ harness: Harness) -> PermissionOverview {
        PermissionOverview(registry: harness.registry, scheduler: harness.scheduler)
    }

    // MARK: what enabled modules need

    @Test func collectsWhatEnabledModulesNeedRequiredFirstAndOncePerPermission() {
        let first = FakeModule(
            "first", order: 1, permissions: [.calendars], optionalPermissions: [.accessibility],
            permissionReasons: [.calendars: "Hiện lịch sắp tới."]
        )
        let second = FakeModule("second", order: 2, permissions: [.accessibility], optionalPermissions: [.pasteboard, .calendars])
        let off = FakeModule("off", order: 3, defaultEnabled: false, permissions: [.screenRecording])
        let overview = overview(Harness([off, second, first]))
        #expect(overview.requirements.map(\.permission) == [.calendars, .accessibility, .pasteboard])
        #expect(overview.requiredRows.map(\.permission) == [.calendars, .accessibility])
        #expect(overview.optionalRows.map(\.permission) == [.pasteboard])
        #expect(overview.requirements.map(\.isRequired) == [true, true, false])
        #expect(overview.requirements[0].uses == [
            .init(module: "first", moduleName: "first", isRequired: true, reason: "Hiện lịch sắp tới."),
            .init(module: "second", moduleName: "second", isRequired: false, reason: Permission.calendars.summary),
        ])
        #expect(overview.requirements[1].uses.map(\.isRequired) == [false, true])
    }

    @Test func aModuleThatListsAPermissionBothWaysNeedsItRequired() {
        let module = FakeModule("m", permissions: [.calendars], optionalPermissions: [.calendars])
        let overview = overview(Harness([module]))
        #expect(overview.requirements.count == 1)
        #expect(overview.requirements[0].uses.map(\.isRequired) == [true])
    }

    @Test func requirementsFollowTheModulesThatAreSwitchedOnAndOff() async {
        let on = FakeModule("on", order: 1, permissions: [.calendars])
        let off = FakeModule("off", order: 2, defaultEnabled: false, permissions: [.screenRecording])
        let harness = Harness([on, off])
        let overview = overview(harness)
        #expect(overview.requirements.map(\.permission) == [.calendars])
        await harness.registry.setEnabled(true, for: "off")
        await harness.registry.setEnabled(false, for: "on")
        #expect(overview.requirements.map(\.permission) == [.screenRecording])
    }

    @Test func nothingIsNeededWhenNoEnabledModuleDeclaresAPermission() {
        #expect(overview(Harness([FakeModule("m")])).requirements.isEmpty)
    }

    // MARK: statuses

    @Test func statusesCoverEveryPermissionAModuleDeclaresSoSwitchingOneOnNeedsNoRefresh() async {
        let off = FakeModule("off", defaultEnabled: false, permissions: [.screenRecording])
        let harness = Harness([off])
        harness.permissions.statuses[.screenRecording] = .notDetermined
        let overview = overview(harness)
        await harness.registry.setEnabled(true, for: "off")
        #expect(overview.status(of: .screenRecording) == .notDetermined)
    }

    @Test func refreshReadsTheCurrentStatusAndKeepsUnknownAsUnknown() {
        let module = FakeModule("m", permissions: [.calendars], optionalPermissions: [.downloadsFolder])
        let harness = Harness([module])
        harness.permissions.statuses = [.calendars: .denied, .downloadsFolder: .unknown]
        let overview = overview(harness)
        #expect(overview.status(of: .calendars) == .denied)
        #expect(overview.status(of: .downloadsFolder) == .unknown)
        harness.permissions.statuses[.calendars] = .granted
        #expect(overview.status(of: .calendars) == .denied)
        overview.refresh()
        #expect(overview.status(of: .calendars) == .granted)
    }

    @Test func aPermissionNoModuleDeclaresIsUnknown() {
        #expect(overview(Harness([FakeModule("m")])).status(of: .microphone) == .unknown)
    }

    // MARK: the status-bar nudge

    @Test func onlyMissingRequiredPermissionsOfEnabledModulesCount() async {
        let module = FakeModule("m", order: 1, permissions: [.calendars, .accessibility], optionalPermissions: [.pasteboard, .systemAudio])
        let off = FakeModule("off", order: 2, defaultEnabled: false, permissions: [.screenRecording])
        let harness = Harness([module, off])
        harness.permissions.statuses = [
            .calendars: .denied, .accessibility: .notDetermined, .pasteboard: .denied, .systemAudio: .unknown, .screenRecording: .denied,
        ]
        let overview = overview(harness)
        #expect(overview.missingRequiredCount == 2)
        #expect(overview.nudgeTitle == "Thiếu 2 quyền…")
        harness.permissions.statuses[.calendars] = .granted
        overview.refresh()
        #expect(overview.missingRequiredCount == 1)
        #expect(overview.nudgeTitle == "Thiếu 1 quyền…")
        harness.permissions.statuses[.accessibility] = .granted
        overview.refresh()
        #expect(overview.missingRequiredCount == 0)
        #expect(overview.nudgeTitle == nil)
    }

    @Test func unknownRequiredPermissionsAreNotMissing() {
        let harness = Harness([FakeModule("m", permissions: [.systemAudio])])
        harness.permissions.statuses[.systemAudio] = .unknown
        let overview = overview(harness)
        #expect(overview.missingRequiredCount == 0)
        #expect(overview.nudgeTitle == nil)
    }

    @Test func theCountIsObservableThroughStatusesAndThroughSwitchingModules() async {
        let on = FakeModule("on", permissions: [.calendars])
        let off = FakeModule("off", defaultEnabled: false, permissions: [.screenRecording])
        let harness = Harness([on, off])
        let overview = overview(harness)
        let changes = ChangeCount()
        func track() { withObservationTracking { _ = overview.missingRequiredCount } onChange: { changes.bump() } }
        track()
        harness.permissions.statuses[.calendars] = .granted
        overview.refresh()
        #expect(changes.count == 1)
        track()
        await harness.registry.setEnabled(true, for: "off")
        #expect(changes.count == 2)
    }

    // MARK: refresh while the page is on screen

    @Test func pollsEveryTwoSecondsOnlyWhileThePageIsVisible() {
        let harness = Harness([FakeModule("m", permissions: [.calendars])])
        let overview = overview(harness)
        harness.permissions.statuses[.calendars] = .denied
        overview.setPageVisible(true)
        #expect(harness.scheduler.pendingCount == 1)
        harness.permissions.statuses[.calendars] = .granted
        harness.scheduler.advance(by: .seconds(1))
        #expect(overview.status(of: .calendars) == .denied)
        harness.scheduler.advance(by: .seconds(1))
        #expect(overview.status(of: .calendars) == .granted)
        harness.permissions.statuses[.calendars] = .denied
        harness.scheduler.advance(by: .seconds(2))
        #expect(overview.status(of: .calendars) == .denied)
        #expect(harness.scheduler.pendingCount == 1)
        overview.setPageVisible(false)
        #expect(harness.scheduler.pendingCount == 0)
        harness.permissions.statuses[.calendars] = .granted
        harness.scheduler.advance(by: .seconds(10))
        #expect(overview.status(of: .calendars) == .denied)
    }

    @Test func showingThePageRefreshesAtOnce() {
        let harness = Harness([FakeModule("m", permissions: [.calendars])])
        let overview = overview(harness)
        harness.permissions.statuses[.calendars] = .granted
        #expect(overview.status(of: .calendars) == .denied)
        overview.setPageVisible(true)
        #expect(overview.status(of: .calendars) == .granted)
    }

    @Test func showingThePageTwiceStillPollsOnce() {
        let harness = Harness([FakeModule("m", permissions: [.calendars])])
        let overview = overview(harness)
        overview.setPageVisible(true)
        overview.setPageVisible(true)
        #expect(harness.scheduler.pendingCount == 1)
    }

    @Test func aHiddenWindowStopsThePollingEvenWithThePageSelected() {
        let harness = Harness([FakeModule("m", permissions: [.calendars])])
        let overview = overview(harness)
        overview.setPageVisible(true)
        overview.setWindowVisible(false)
        #expect(harness.scheduler.pendingCount == 0)
        harness.permissions.statuses[.calendars] = .granted
        harness.scheduler.advance(by: .seconds(6))
        #expect(overview.status(of: .calendars) == .denied)
        overview.setWindowVisible(true)
        #expect(overview.status(of: .calendars) == .granted)
        #expect(harness.scheduler.pendingCount == 1)
    }

    @Test func aVisibleWindowWithAnotherPageSelectedDoesNotPoll() {
        let harness = Harness([FakeModule("m", permissions: [.calendars])])
        let overview = overview(harness)
        overview.setWindowVisible(true)
        #expect(harness.scheduler.pendingCount == 0)
    }

    // MARK: granting one permission

    @Test func grantingRequestsAndRefreshesWhileMarkingItBusy() async {
        let harness = Harness([FakeModule("m", permissions: [.calendars])])
        harness.permissions.statuses[.calendars] = .notDetermined
        let prompt = openPrompt(on: harness)
        let overview = overview(harness)
        let granting = Task { await overview.grant(.calendars) }
        await waitForPrompt(prompt)
        #expect(overview.granting == [.calendars])
        prompt.open()
        await granting.value
        #expect(overview.granting.isEmpty)
        #expect(overview.status(of: .calendars) == .granted)
        #expect(harness.permissions.requested == [.calendars])
    }

    // MARK: "Cấp lần lượt"

    private func walkthroughHarness() -> Harness {
        let first = FakeModule(
            "first", order: 1, permissions: [.calendars], optionalPermissions: [.accessibility, .microphone]
        )
        let second = FakeModule("second", order: 2, optionalPermissions: [.pasteboard, .systemAudio])
        let harness = Harness([first, second])
        harness.permissions.statuses = [
            .calendars: .notDetermined, .accessibility: .denied, .microphone: .granted,
            .pasteboard: .notDetermined, .systemAudio: .unknown,
        ]
        return harness
    }

    @Test func theWalkthroughStepsThroughEveryMissingPermissionInDisplayOrder() async {
        let harness = walkthroughHarness()
        let overview = overview(harness)
        #expect(overview.missingCount == 3)
        overview.startWalkthrough()
        await overview.walkthroughSettled()
        // Calendars and Accessibility are answered by the request; the pasteboard has none, so Settings opens and it waits.
        #expect(harness.permissions.requested == [.calendars, .accessibility])
        #expect(harness.permissions.openedSettings == [.pasteboard])
        #expect(overview.walkthrough == .waiting(.init(permission: .pasteboard, position: 3, total: 3)))
        harness.permissions.statuses[.pasteboard] = .granted
        overview.refresh()
        await overview.walkthroughSettled()
        #expect(overview.walkthrough == .idle)
    }

    @Test func aSettingsOnlyPermissionWaitsForTheUserAndMovesOnOnceItIsGranted() async {
        let first = FakeModule("m", order: 1, permissions: [.accessibility], optionalPermissions: [.calendars])
        let harness = Harness([first])
        harness.permissions.statuses = [.accessibility: .denied, .calendars: .notDetermined]
        harness.permissions.requestResult = .denied
        let overview = overview(harness)
        overview.startWalkthrough()
        await overview.walkthroughSettled()
        #expect(harness.permissions.requested == [.accessibility])
        #expect(harness.permissions.openedSettings == [.accessibility])
        #expect(overview.walkthrough == .waiting(.init(permission: .accessibility, position: 1, total: 2)))
        #expect(overview.walkthrough.step?.permission.instruction == "Bật MyNotch trong danh sách Trợ năng (Accessibility) rồi quay lại.")
        harness.permissions.statuses[.accessibility] = .granted
        harness.permissions.requestResult = .granted
        overview.refresh()
        await overview.walkthroughSettled()
        #expect(harness.permissions.requested == [.accessibility, .calendars])
        #expect(overview.walkthrough == .idle)
    }

    @Test func aRefusedPromptWaitsWithoutOpeningSettings() async {
        let harness = Harness([FakeModule("m", permissions: [.calendars])])
        harness.permissions.statuses[.calendars] = .notDetermined
        harness.permissions.requestResult = .denied
        let overview = overview(harness)
        overview.startWalkthrough()
        await overview.walkthroughSettled()
        #expect(harness.permissions.openedSettings.isEmpty)
        #expect(overview.walkthrough == .waiting(.init(permission: .calendars, position: 1, total: 1)))
    }

    @Test func skippingMovesToTheNextPermission() async {
        let harness = Harness([FakeModule("m", permissions: [.accessibility, .screenRecording])])
        harness.permissions.requestResult = .denied
        let overview = overview(harness)
        overview.startWalkthrough()
        await overview.walkthroughSettled()
        #expect(overview.walkthrough.step?.permission == .accessibility)
        overview.skipWalkthroughStep()
        await overview.walkthroughSettled()
        #expect(overview.walkthrough == .waiting(.init(permission: .screenRecording, position: 2, total: 2)))
        overview.skipWalkthroughStep()
        await overview.walkthroughSettled()
        #expect(overview.walkthrough == .idle)
    }

    @Test func stoppingEndsTheWalkthroughAndLaterGrantsStartNothing() async {
        let harness = Harness([FakeModule("m", permissions: [.accessibility, .screenRecording])])
        harness.permissions.requestResult = .denied
        let overview = overview(harness)
        overview.startWalkthrough()
        await overview.walkthroughSettled()
        overview.stopWalkthrough()
        #expect(overview.walkthrough == .idle)
        harness.permissions.statuses[.accessibility] = .granted
        overview.refresh()
        await overview.walkthroughSettled()
        #expect(harness.permissions.requested == [.accessibility])
        #expect(overview.walkthrough == .idle)
    }

    @Test func aPermissionGrantedWhileWaitingForAnotherIsNotAskedAgain() async {
        let harness = Harness([FakeModule("m", permissions: [.accessibility, .screenRecording])])
        harness.permissions.requestResult = .denied
        let overview = overview(harness)
        overview.startWalkthrough()
        await overview.walkthroughSettled()
        harness.permissions.statuses[.screenRecording] = .granted
        harness.permissions.statuses[.accessibility] = .granted
        overview.refresh()
        await overview.walkthroughSettled()
        #expect(harness.permissions.requested == [.accessibility])
        #expect(overview.walkthrough == .idle)
    }

    @Test func nothingMissingMeansNothingToWalkThrough() async {
        let harness = Harness([FakeModule("m", permissions: [.calendars], optionalPermissions: [.downloadsFolder])])
        harness.permissions.statuses = [.calendars: .granted, .downloadsFolder: .unknown]
        let overview = overview(harness)
        #expect(overview.missingCount == 0)
        overview.startWalkthrough()
        await overview.walkthroughSettled()
        #expect(overview.walkthrough == .idle)
        #expect(harness.permissions.requested.isEmpty)
    }

    @Test func aWalkthroughThatIsRunningIsNotStartedAgain() async {
        let harness = Harness([FakeModule("m", permissions: [.calendars, .reminders])])
        harness.permissions.statuses = [.calendars: .notDetermined, .reminders: .notDetermined]
        let prompt = openPrompt(on: harness)
        let overview = overview(harness)
        overview.startWalkthrough()
        await waitForPrompt(prompt)
        #expect(overview.walkthrough == .requesting(.init(permission: .calendars, position: 1, total: 2)))
        overview.startWalkthrough()
        prompt.open()
        await waitForPrompt(prompt)
        #expect(overview.walkthrough == .requesting(.init(permission: .reminders, position: 2, total: 2)))
        prompt.open()
        await overview.walkthroughSettled()
        #expect(harness.permissions.requested == [.calendars, .reminders])
        #expect(overview.walkthrough == .idle)
    }

    @Test func stoppingWhileAPromptIsOpenIgnoresTheLateAnswer() async {
        let harness = Harness([FakeModule("m", permissions: [.calendars, .reminders])])
        harness.permissions.statuses = [.calendars: .notDetermined, .reminders: .notDetermined]
        let prompt = openPrompt(on: harness)
        let overview = overview(harness)
        overview.startWalkthrough()
        await waitForPrompt(prompt)
        overview.stopWalkthrough()
        #expect(overview.walkthrough == .idle)
        prompt.open()
        await overview.walkthroughSettled()
        #expect(harness.permissions.requested == [.calendars])
        #expect(overview.walkthrough == .idle)
    }

    // MARK: opening the page by itself

    private func missingSomething() -> PermissionOverview {
        let harness = Harness([FakeModule("m", permissions: [.calendars])])
        return overview(harness)
    }

    @Test func opensOnTheFirstLaunchAndOnlyOncePerLaunch() {
        let overview = missingSomething()
        #expect(overview.shouldOpenAtLaunch(previousIdentity: nil, currentIdentity: "a"))
        #expect(!overview.shouldOpenAtLaunch(previousIdentity: nil, currentIdentity: "a"))
        #expect(!overview.shouldOpenAtLaunch(previousIdentity: "a", currentIdentity: "b"))
    }

    @Test func opensWhenTheSigningIdentityChanged() {
        #expect(missingSomething().shouldOpenAtLaunch(previousIdentity: "a", currentIdentity: "b"))
    }

    @Test func staysClosedWhenTheSigningIdentityIsTheSame() {
        #expect(!missingSomething().shouldOpenAtLaunch(previousIdentity: "a", currentIdentity: "a"))
    }

    @Test func anUnreadableIdentityOnlyOpensOnTheFirstLaunch() {
        #expect(!missingSomething().shouldOpenAtLaunch(previousIdentity: "a", currentIdentity: nil))
        #expect(missingSomething().shouldOpenAtLaunch(previousIdentity: nil, currentIdentity: nil))
    }

    @Test func staysClosedWhenNothingIsMissingEvenOnTheFirstLaunch() {
        let harness = Harness([FakeModule("m", permissions: [.calendars])])
        harness.permissions.statuses[.calendars] = .granted
        let overview = overview(harness)
        #expect(!overview.shouldOpenAtLaunch(previousIdentity: nil, currentIdentity: "a"))
    }

    @Test func anOptionalMissingPermissionIsReasonEnoughOnTheFirstLaunch() {
        let harness = Harness([FakeModule("m", optionalPermissions: [.accessibility])])
        let overview = overview(harness)
        #expect(overview.shouldOpenAtLaunch(previousIdentity: nil, currentIdentity: "a"))
    }
}
