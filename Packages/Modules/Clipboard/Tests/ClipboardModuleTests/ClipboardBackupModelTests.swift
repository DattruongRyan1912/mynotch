import Foundation
import Testing
@testable import ClipboardModule

/// What the Settings rows show of a backup or restore: working with its progress, the plan of a restore waiting for the user's
/// choice, done with the summary, failed with the reason, cancelled. The actions are fakes, so no file is touched.
@Suite final class ClipboardBackupModelTests {
    static let planSummary = ClipboardRestorePlanSummary(added: 8, duplicates: 2, outsideLimits: 3, evictedExisting: 4, evictedExistingImages: 1)

    final class Calls {
        var exports: [(options: ClipboardBackupOptions, url: URL)] = []
        var plans: [URL] = []
        var commits: [ClipboardRestorePolicy] = []
        var exportOutcome: Result<ClipboardBackupExportSummary, any Error> = .success(ClipboardBackupExportSummary(itemCount: 2, boardCount: 1))
        var planOutcome: Result<ClipboardRestorePlanSummary, any Error> = .success(ClipboardBackupModelTests.planSummary)
        var commitOutcome: Result<ClipboardBackupRestoreSummary, any Error> = .success(ClipboardBackupRestoreSummary(added: 2, duplicates: 1))
        /// When set, the actions report this and then wait until cancelled.
        var reportsAndWaits: Double?
        var legacy: [ClipboardBackupOptions.Scope: Int] = [:]
    }

    let calls = Calls()
    let url = URL(fileURLWithPath: "/tmp/ignored.mynotchclip")

    func makeModel() -> ClipboardBackupModel {
        let calls = calls
        return ClipboardBackupModel(actions: ClipboardBackupActions(
            export: { options, url, progress in
                calls.exports.append((options, url))
                if let value = calls.reportsAndWaits {
                    progress(value)
                    try await Task.sleep(for: .seconds(60))
                }
                return try calls.exportOutcome.get()
            },
            planRestore: { url, progress in
                calls.plans.append(url)
                if let value = calls.reportsAndWaits {
                    progress(value)
                    try await Task.sleep(for: .seconds(60))
                }
                let summary = try calls.planOutcome.get()
                return ClipboardRestoreOffer(summary: summary) { policy, progress in
                    calls.commits.append(policy)
                    if let value = calls.reportsAndWaits {
                        progress(value)
                        try await Task.sleep(for: .seconds(60))
                    }
                    return try calls.commitOutcome.get()
                }
            },
            legacyTextCount: { calls.legacy[$0] ?? 0 }
        ))
    }

    func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<2_000 where !condition() { await Task.yield() }
    }

    /// A restore read and waiting for the choice.
    func choosing(_ model: ClipboardBackupModel) async {
        model.startRestore(from: url)
        await model.task?.value
    }

    @Test func startsIdleAndAvailableWhenTheModuleRuns() {
        let model = makeModel()
        #expect(model.status == .idle && model.isAvailable && !model.isWorking && !model.isBusy)
    }

    @Test func withoutActionsTheModuleIsStoppedAndNothingStarts() async {
        let model = ClipboardBackupModel(actions: nil)
        model.startExport(ClipboardBackupOptions(), to: url)
        model.startRestore(from: url)
        #expect(!model.isAvailable && model.status == .idle && model.task == nil)
        #expect(model.legacyTextCount(for: .allHistory) == 0)
    }

    @Test func aFinishedBackupShowsItsSummary() async {
        let model = makeModel()
        let options = ClipboardBackupOptions(scope: .pinnedOnly, skipSensitive: false)

        model.startExport(options, to: url)
        await model.task?.value

        #expect(model.status == .finished("Đã sao lưu 2 mục và 1 board."))
        #expect(calls.exports.count == 1 && calls.exports[0].options == options && calls.exports[0].url == url)
        #expect(!model.isWorking)
    }

    // MARK: A restore is read first, then chosen

    @Test func readingARestoreEndsInTheChoiceAndDoesNothingElse() async {
        let model = makeModel()
        await choosing(model)

        #expect(model.status == .choosing(Self.planSummary))
        #expect(model.choosingSummary == Self.planSummary)
        #expect(calls.plans == [url] && calls.commits.isEmpty)
        #expect(!model.isWorking && model.isBusy)
    }

    @Test func choosingToKeepEverythingDoesIt() async {
        let model = makeModel()
        await choosing(model)

        model.confirmRestore(.keepAll)
        await model.task?.value

        #expect(calls.commits == [.keepAll])
        #expect(model.status == .finished("Đã thêm 2 mục, bỏ qua 1 trùng lặp"))
        #expect(model.choosingSummary == nil && !model.isBusy)
    }

    @Test func choosingTheLimitsDoesThat() async {
        let model = makeModel()
        await choosing(model)

        model.confirmRestore(.applyLimits)
        await model.task?.value

        #expect(calls.commits == [.applyLimits])
    }

    @Test func decliningDoesNothingToTheHistoryAndSaysItWasCancelled() async {
        let model = makeModel()
        await choosing(model)

        model.declineRestore()

        #expect(model.status == .cancelled && calls.commits.isEmpty && !model.isBusy)
        // Nothing left to confirm.
        model.confirmRestore(.keepAll)
        #expect(calls.commits.isEmpty)
    }

    @Test func confirmingWithNothingReadDoesNothing() {
        let model = makeModel()
        model.confirmRestore(.keepAll)
        #expect(model.status == .idle && model.task == nil && calls.commits.isEmpty)
    }

    @Test func aStartWhileTheChoiceIsWaitingIsIgnoredAndTheMessageStays() async {
        let model = makeModel()
        await choosing(model)

        model.startRestore(from: url)
        model.startExport(ClipboardBackupOptions(), to: url)
        model.dismiss()

        #expect(model.status == .choosing(Self.planSummary) && calls.plans.count == 1 && calls.exports.isEmpty)
    }

    @Test func aFailureOfTheReadingShowsItsReasonAndOffersNoChoice() async {
        let model = makeModel()
        calls.planOutcome = .failure(ClipboardBackupError.newerVersion(2))
        model.startRestore(from: url)
        await model.task?.value
        #expect(model.status == .failed(ClipboardBackupError.newerVersion(2).errorDescription!))
        #expect(model.choosingSummary == nil && !model.isBusy)
    }

    @Test func aFailureOfTheCommitShowsItsReason() async {
        let model = makeModel()
        await choosing(model)
        calls.commitOutcome = .failure(ClipboardBackupError.moduleStopped)

        model.confirmRestore(.keepAll)
        await model.task?.value

        #expect(model.status == .failed(ClipboardBackupError.moduleStopped.errorDescription!))
    }

    @Test func aFailureShowsItsReason() async {
        let model = makeModel()
        struct Odd: LocalizedError { var errorDescription: String? { "lỗi lạ" } }
        calls.exportOutcome = .failure(Odd())
        model.startExport(ClipboardBackupOptions(), to: url)
        await model.task?.value
        #expect(model.status == .failed("lỗi lạ"))
    }

    // MARK: Progress and cancelling

    @Test func workingShowsTheProgressTheActionReports() async {
        let model = makeModel()
        calls.reportsAndWaits = 0.4

        model.startExport(ClipboardBackupOptions(), to: url)
        #expect(model.isWorking)
        await waitUntil { model.status == .working(title: "Đang sao lưu…", fraction: 0.4) }

        #expect(model.status == .working(title: "Đang sao lưu…", fraction: 0.4))
        model.cancel()
        await model.task?.value
    }

    @Test func readingARestoreAndDoingItTitleThemselves() async {
        let model = makeModel()
        calls.reportsAndWaits = 0.1
        model.startRestore(from: url)
        await waitUntil { model.status == .working(title: "Đang đọc tệp…", fraction: 0.1) }
        #expect(model.status == .working(title: "Đang đọc tệp…", fraction: 0.1))
        model.cancel()
        await model.task?.value

        calls.reportsAndWaits = nil
        await choosing(model)
        calls.reportsAndWaits = 0.2
        model.confirmRestore(.applyLimits)
        await waitUntil { model.status == .working(title: "Đang khôi phục…", fraction: 0.2) }
        #expect(model.status == .working(title: "Đang khôi phục…", fraction: 0.2))
        model.cancel()
        await model.task?.value
    }

    @Test func cancellingTheReadingEndsItAsCancelled() async {
        let model = makeModel()
        calls.reportsAndWaits = 0.2
        model.startRestore(from: url)
        await waitUntil { model.status == .working(title: "Đang đọc tệp…", fraction: 0.2) }

        model.cancel()
        await model.task?.value

        #expect(model.status == .cancelled && !model.isWorking && !model.isBusy)
    }

    @Test func cancellingTheCommitEndsItAsCancelled() async {
        let model = makeModel()
        await choosing(model)
        calls.reportsAndWaits = 0.3
        model.confirmRestore(.keepAll)
        await waitUntil { model.status == .working(title: "Đang khôi phục…", fraction: 0.3) }

        model.cancel()
        await model.task?.value

        #expect(model.status == .cancelled)
    }

    @Test func aSecondStartWhileWorkingIsIgnored() async {
        let model = makeModel()
        calls.reportsAndWaits = 0.3
        model.startExport(ClipboardBackupOptions(), to: url)
        model.startExport(ClipboardBackupOptions(), to: url)
        model.startRestore(from: url)
        await waitUntil { model.status == .working(title: "Đang sao lưu…", fraction: 0.3) }

        #expect(calls.exports.count == 1 && calls.plans.isEmpty)
        model.cancel()
        await model.task?.value
    }

    @Test func progressNeverGoesBack() async {
        let model = makeModel()
        calls.reportsAndWaits = 0.6
        model.startExport(ClipboardBackupOptions(), to: url)
        await waitUntil { model.status == .working(title: "Đang sao lưu…", fraction: 0.6) }

        model.progressChanged(0.2)

        #expect(model.status == .working(title: "Đang sao lưu…", fraction: 0.6))
        model.cancel()
        await model.task?.value
    }

    @Test func dismissingTheMessageGoesBackToIdleButNotWhileWorking() async {
        let model = makeModel()
        model.startExport(ClipboardBackupOptions(), to: url)
        await model.task?.value
        model.dismiss()
        #expect(model.status == .idle)

        calls.reportsAndWaits = 0.5
        model.startExport(ClipboardBackupOptions(), to: url)
        await waitUntil { model.status == .working(title: "Đang sao lưu…", fraction: 0.5) }
        model.dismiss()
        #expect(model.isWorking)
        model.cancel()
        await model.task?.value
    }

    @Test func aNewStartClearsTheMessageOfTheLastOne() async {
        let model = makeModel()
        calls.exportOutcome = .failure(ClipboardBackupError.notABackup)
        model.startExport(ClipboardBackupOptions(), to: url)
        await model.task?.value
        #expect(model.status != .idle)

        calls.exportOutcome = .success(ClipboardBackupExportSummary(itemCount: 1))
        model.startExport(ClipboardBackupOptions(), to: url)
        await model.task?.value
        #expect(model.status == .finished("Đã sao lưu 1 mục và 0 board."))
    }

    // MARK: Items the secret check cannot see

    @Test func theSheetAsksHowManyOldItemsTheScopeWouldTake() {
        let model = makeModel()
        calls.legacy = [.allHistory: 120, .pinnedOnly: 4]
        #expect(model.legacyTextCount(for: .allHistory) == 120)
        #expect(model.legacyTextCount(for: .pinnedOnly) == 4)
    }
}
