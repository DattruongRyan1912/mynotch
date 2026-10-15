import Foundation
import Testing
@testable import ClipboardModule

/// What the Settings rows show of a backup or restore: working with its progress, done with the summary, failed with the
/// reason, cancelled. The actions are fakes, so no file is touched.
@Suite final class ClipboardBackupModelTests {
    final class Calls {
        var exports: [(options: ClipboardBackupOptions, url: URL)] = []
        var restores: [URL] = []
        var exportOutcome: Result<ClipboardBackupExportSummary, any Error> = .success(ClipboardBackupExportSummary(itemCount: 2, boardCount: 1))
        var restoreOutcome: Result<ClipboardBackupRestoreSummary, any Error> = .success(ClipboardBackupRestoreSummary(added: 2, duplicates: 1))
        /// When set, the actions report this and then wait until cancelled.
        var reportsAndWaits: Double?
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
            restore: { url, progress in
                calls.restores.append(url)
                if let value = calls.reportsAndWaits {
                    progress(value)
                    try await Task.sleep(for: .seconds(60))
                }
                return try calls.restoreOutcome.get()
            }
        ))
    }

    func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<2_000 where !condition() { await Task.yield() }
    }

    @Test func startsIdleAndAvailableWhenTheModuleRuns() {
        let model = makeModel()
        #expect(model.status == .idle && model.isAvailable && !model.isWorking)
    }

    @Test func withoutActionsTheModuleIsStoppedAndNothingStarts() async {
        let model = ClipboardBackupModel(actions: nil)
        model.startExport(ClipboardBackupOptions(), to: url)
        model.startRestore(from: url)
        #expect(!model.isAvailable && model.status == .idle && model.task == nil)
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

    @Test func aFinishedRestoreShowsItsSummary() async {
        let model = makeModel()
        model.startRestore(from: url)
        await model.task?.value
        #expect(model.status == .finished("Đã thêm 2 mục, bỏ qua 1 trùng lặp"))
        #expect(calls.restores == [url])
    }

    @Test func aFailureShowsItsReason() async {
        let model = makeModel()
        calls.restoreOutcome = .failure(ClipboardBackupError.newerVersion(2))
        model.startRestore(from: url)
        await model.task?.value
        #expect(model.status == .failed(ClipboardBackupError.newerVersion(2).errorDescription!))

        struct Odd: LocalizedError { var errorDescription: String? { "lỗi lạ" } }
        calls.exportOutcome = .failure(Odd())
        model.startExport(ClipboardBackupOptions(), to: url)
        await model.task?.value
        #expect(model.status == .failed("lỗi lạ"))
    }

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

    @Test func aRestoreTitlesItselfAsOne() async {
        let model = makeModel()
        calls.reportsAndWaits = 0.1
        model.startRestore(from: url)
        await waitUntil { model.status == .working(title: "Đang khôi phục…", fraction: 0.1) }
        #expect(model.status == .working(title: "Đang khôi phục…", fraction: 0.1))
        model.cancel()
        await model.task?.value
    }

    @Test func cancellingEndsTheWorkAsCancelled() async {
        let model = makeModel()
        calls.reportsAndWaits = 0.2
        model.startRestore(from: url)
        await waitUntil { model.status == .working(title: "Đang khôi phục…", fraction: 0.2) }

        model.cancel()
        await model.task?.value

        #expect(model.status == .cancelled && !model.isWorking)
    }

    @Test func aSecondStartWhileWorkingIsIgnored() async {
        let model = makeModel()
        calls.reportsAndWaits = 0.3
        model.startExport(ClipboardBackupOptions(), to: url)
        model.startExport(ClipboardBackupOptions(), to: url)
        model.startRestore(from: url)
        await waitUntil { model.status == .working(title: "Đang sao lưu…", fraction: 0.3) }

        #expect(calls.exports.count == 1 && calls.restores.isEmpty)
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
        model.startRestore(from: url)
        await model.task?.value
        model.dismiss()
        #expect(model.status == .idle)

        calls.reportsAndWaits = 0.5
        model.startRestore(from: url)
        await waitUntil { model.status == .working(title: "Đang khôi phục…", fraction: 0.5) }
        model.dismiss()
        #expect(model.isWorking)
        model.cancel()
        await model.task?.value
    }

    @Test func aNewStartClearsTheMessageOfTheLastOne() async {
        let model = makeModel()
        calls.restoreOutcome = .failure(ClipboardBackupError.notABackup)
        model.startRestore(from: url)
        await model.task?.value
        #expect(model.status != .idle)

        calls.restoreOutcome = .success(ClipboardBackupRestoreSummary(added: 1))
        model.startRestore(from: url)
        await model.task?.value
        #expect(model.status == .finished("Đã thêm 1 mục"))
    }
}
