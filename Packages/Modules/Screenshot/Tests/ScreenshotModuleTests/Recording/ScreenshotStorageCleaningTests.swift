import CoreGraphics
import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import ScreenshotModule

/// The module's part of the Storage page: what it measures, what the two cleans remove, and the daily rule, with the module running,
/// stopped after it ran, and never started.
@Suite(.timeLimit(.minutes(2))) final class ScreenshotStorageCleaningTests {
    enum Mode: CaseIterable, CustomTestStringConvertible {
        case running, stoppedAfterRun, neverStarted

        var testDescription: String {
            switch self {
            case .running: "running"
            case .stoppedAfterRun: "stopped after it ran"
            case .neverStarted: "never started"
            }
        }
    }

    /// The lines the module reported, which must hold numbers only.
    final class Reports {
        var lines: [String] = []
    }

    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let day: TimeInterval = 24 * 60 * 60
    /// A recent export: exported at all is what the page looks at, not how long ago.
    static let exportedRecently = now.addingTimeInterval(-1 * day)

    let fakes = FakeRecordingSystem()
    let rig: ModuleRig
    let reports = Reports()
    var module: ScreenshotModule { rig.module }
    var harness: RegistryHarness { rig.harness }
    var editors: FakeRecordingEditors { fakes.editors }
    var capturesFolder: URL { CaptureStore.capturesFolder(in: rig.storage.directory) }

    init() throws {
        rig = try ModuleRig(recording: fakes.dependencies)
        let reports = reports
        rig.module.storageReport = { reports.lines.append($0) }
    }

    // MARK: Fixtures

    /// Puts the module in `mode`. The data is made before this, on disk, so the three modes start from the same files.
    func prepare(_ mode: Mode) async {
        switch mode {
        case .running:
            await rig.start()
        case .stoppedAfterRun:
            await rig.start()
            await harness.registry.setEnabled(false, for: "screenshot")
        case .neverStarted:
            break
        }
    }

    /// `count` captures, oldest first in the returned list, written by a store of their own before the module starts.
    @discardableResult
    func makeCaptures(_ count: Int) async throws -> [CaptureRecord] {
        let store = CaptureStore(directory: rig.storage.directory, cachesDirectory: rig.storage.cachesDirectory, logger: Log.logger(category: "ScreenshotStorageTests"))
        var records: [CaptureRecord] = []
        for index in 0..<count {
            records.append(try await store.add(CaptureStoreTests.image(width: 30 + index, height: 20), keepCount: 200))
        }
        return records
    }

    /// The keep count and the exported-recordings rule, set where the module in `mode` reads them.
    func setRules(_ mode: Mode, keepCount: Int? = nil, exportedDays: Int? = nil) throws {
        if mode == .neverStarted {
            if let keepCount { rig.fallbackSettings.set(keepCount, for: ScreenshotRetentionKeys.keepCount) }
            if let exportedDays {
                rig.fallbackSettings.set(true, for: ScreenshotRetentionKeys.cleanExportedRecordings)
                rig.fallbackSettings.set(exportedDays, for: ScreenshotRetentionKeys.exportedRecordingDays)
            }
        } else {
            let (settings, keys) = try rig.settings()
            if let keepCount { settings.set(keepCount, for: keys.keepCount) }
            if let exportedDays {
                settings.set(true, for: keys.cleanExportedRecordings)
                settings.set(exportedDays, for: keys.exportedRecordingDays)
            }
        }
    }

    /// The size of every regular file under `url`, counted here and not by the code under test.
    func diskBytes(_ url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        if attributes?[.type] as? FileAttributeType == .typeRegular { return (attributes?[.size] as? NSNumber)?.int64Value ?? 0 }
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walker {
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
        }
        return total
    }

    func exists(_ project: RecordingProject) -> Bool {
        FileManager.default.fileExists(atPath: rig.recordingStore.folder(for: project.id).path(percentEncoded: false))
    }

    func listedRecordings() async -> [UUID] {
        await module.refreshRecordings()
        return module.state.recordings.map(\.id)
    }

    func record() async throws {
        let (settings, keys) = try rig.settings()
        settings.set(false, for: keys.recordCountdown)
        module.beginRecording(.region)
        await rig.waitUntil { rig.phase == .recording }
        #expect(rig.phase == .recording)
    }

    // MARK: What is measured

    @Test(arguments: Mode.allCases)
    func theCategoriesAreTheCapturesAndTheRecordingsThatWereExportedAndThatWereNot(mode: Mode) async throws {
        try await makeCaptures(2)
        let exportedA = try rig.makeRecording(bytes: 4_000, exportedAt: Self.exportedRecently)
        let exportedB = try rig.makeRecording(status: .interrupted, bytes: 6_000, exportedAt: Self.exportedRecently)
        let neverA = try rig.makeRecording(bytes: 2_000)
        let neverB = try rig.makeRecording(bytes: 5_000)
        // Not a recording, with something in it: it counts with the ones that were not exported, so it is never offered to a clean.
        let stranger = rig.recordingsRoot.appending(path: "notes", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stranger, withIntermediateDirectories: true)
        try Data(count: 50).write(to: stranger.appending(path: "keep.txt"))
        // The caches hold things of their own, which the module's generic category counts and these do not.
        let thumbnails = rig.storage.cachesDirectory.appending(path: "thumbnails", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: thumbnails, withIntermediateDirectories: true)
        try Data(count: 777).write(to: thumbnails.appending(path: "x.png"))
        await prepare(mode)
        let exportedBytes = diskBytes(rig.recordingStore.folder(for: exportedA.id)) + diskBytes(rig.recordingStore.folder(for: exportedB.id))
        let neverBytes = diskBytes(rig.recordingStore.folder(for: neverA.id)) + diskBytes(rig.recordingStore.folder(for: neverB.id)) + 50

        let categories = await module.storageCategories(storage: rig.storage)

        #expect(categories.map(\.id) == ["screenshot.captures", "screenshot.recordings.exported", "screenshot.recordings.unexported"])
        #expect(categories.map(\.title) == ["Ảnh chụp", "Bản quay đã xuất", "Bản quay chưa xuất"])
        #expect(categories.map(\.keeps) == [
            nil, "File đã xuất ở ~/Movies/MyNotch không bị xoá", "Xoá từng bản trong tab Chụp màn hình (chưa có bản xuất nào)",
        ])
        // The page offers the first two to "Dọn tất cả" and only shows the third.
        #expect(categories.map(\.canClean) == [true, true, false])
        #expect(categories[0].bytes == diskBytes(capturesFolder) && categories[0].bytes > 0)
        #expect(categories[1].bytes == exportedBytes && exportedBytes >= 10_000)
        #expect(categories[2].bytes == neverBytes && neverBytes >= 7_000)
        // Together they are what is on disk.
        #expect(categories[1].bytes + categories[2].bytes == diskBytes(rig.recordingsRoot))
    }

    @Test(arguments: Mode.allCases)
    func aRecordingThatCannotBeToldToBeExportedCountsAsNotExported(mode: Mode) async throws {
        await prepare(mode)
        // Made after the start, which would have rescued the one marked as being recorded.
        let marked = try rig.makeRecording(status: .recording, bytes: 3_000, exportedAt: Self.exportedRecently)
        let unreadable = try rig.makeRecording(bytes: 2_000, exportedAt: Self.exportedRecently)
        try Data("not json".utf8).write(to: rig.recordingStore.folder(for: unreadable.id).appending(path: "project.json"))
        let noProject = try rig.makeRecording(bytes: 1_000, exportedAt: Self.exportedRecently)
        try FileManager.default.removeItem(at: rig.recordingStore.folder(for: noProject.id).appending(path: "project.json"))

        let categories = await module.storageCategories(storage: rig.storage)

        #expect(categories[1].bytes == 0 && categories[2].bytes == diskBytes(rig.recordingsRoot) && categories[2].bytes >= 6_000)
        #expect(await module.clean(categoryID: ScreenshotModule.exportedRecordingsCategoryID, storage: rig.storage) == 0)
        #expect(exists(marked) && exists(unreadable) && exists(noProject))
    }

    @Test func aModuleThatNeverRanMeasuresNothingAndCreatesNothing() async {
        let categories = await module.storageCategories(storage: rig.storage)

        #expect(categories.map(\.bytes) == [0, 0, 0])
        #expect(!FileManager.default.fileExists(atPath: rig.storage.directory.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: rig.storage.cachesDirectory.path(percentEncoded: false)))
    }

    @Test func recordingsLiveInTheDurableFolderAndNeverInTheCaches() {
        let root = rig.recordingsRoot.standardizedFileURL.path(percentEncoded: false)
        #expect(root.hasPrefix(rig.storage.directory.standardizedFileURL.path(percentEncoded: false)))
        #expect(!root.hasPrefix(rig.storage.cachesDirectory.standardizedFileURL.path(percentEncoded: false)))
    }

    // MARK: "Ảnh chụp"

    @Test(arguments: Mode.allCases)
    func cleaningTheCapturesRemovesThemAllAndLeavesTheRecordings(mode: Mode) async throws {
        try await makeCaptures(3)
        let recording = try rig.makeRecording(bytes: 2_000)
        await prepare(mode)
        let before = diskBytes(capturesFolder), recordingsBefore = diskBytes(rig.recordingsRoot)
        #expect(before > 0)

        let freed = await module.clean(categoryID: ScreenshotModule.capturesCategoryID, storage: rig.storage)

        #expect(freed > 0 && freed == before - diskBytes(capturesFolder))
        let remaining = (try? FileManager.default.contentsOfDirectory(atPath: capturesFolder.path(percentEncoded: false))) ?? []
        #expect(!remaining.contains { $0.hasSuffix(".png") })
        #expect(diskBytes(rig.recordingsRoot) == recordingsBefore && exists(recording))
        if mode == .running {
            // The tray follows, and the store the module keeps is the one that was cleaned.
            #expect(module.state.records.isEmpty && module.store?.records.isEmpty == true)
        }
    }

    @Test func aRunningModuleStillCapturesAfterTheCapturesWereCleaned() async throws {
        try await makeCaptures(2)
        await rig.start()
        _ = await module.clean(categoryID: ScreenshotModule.capturesCategoryID, storage: rig.storage)

        await module.capture(mode: .regionOrWindow)

        #expect(module.state.records.count == 1)
        #expect(module.store?.records.count == 1)
    }

    // MARK: "Bản quay đã xuất"

    @Test(arguments: Mode.allCases)
    func cleaningTheExportedRecordingsRemovesTheirFoldersAndNothingElse(mode: Mode) async throws {
        let first = try rig.makeRecording(bytes: 4_000, exportedAt: Self.exportedRecently)
        let second = try rig.makeRecording(status: .interrupted, bytes: 6_000, exportedAt: Self.exportedRecently)
        let never = try rig.makeRecording(createdAt: Self.now.addingTimeInterval(-900 * Self.day), bytes: 7_000)
        let exportedFolder = rig.temporaryRoot.appending(path: "Movies/MyNotch", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: exportedFolder, withIntermediateDirectories: true)
        let video = exportedFolder.appending(path: "Bản quay MyNotch.mp4")
        try Data(count: 900).write(to: video)
        // Not a recording: something of somebody's in the folder, which is left alone.
        let stranger = rig.recordingsRoot.appending(path: "notes", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stranger, withIntermediateDirectories: true)
        try Data(count: 50).write(to: stranger.appending(path: "keep.txt"))
        let cacheFile = rig.storage.cachesDirectory.appending(path: "thumbnails/x.png")
        try FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: 33).write(to: cacheFile)
        await prepare(mode)
        // Made after the start, which would have rescued it: still marked as being recorded, and said to be exported.
        let marked = try rig.makeRecording(status: .recording, exportedAt: Self.exportedRecently)
        let expected = diskBytes(rig.recordingStore.folder(for: first.id)) + diskBytes(rig.recordingStore.folder(for: second.id))

        let freed = await module.clean(categoryID: ScreenshotModule.exportedRecordingsCategoryID, storage: rig.storage)

        #expect(freed == expected && freed >= 10_000)
        #expect(!exists(first) && !exists(second))
        // Never exported, however old: the original is the only copy.
        #expect(exists(never) && exists(marked))
        #expect(FileManager.default.fileExists(atPath: video.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: stranger.appending(path: "keep.txt").path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: cacheFile.path(percentEncoded: false)))
        if mode == .running { #expect(module.state.recordings.map(\.id).contains(never.id) && !module.state.recordings.map(\.id).contains(first.id)) }
    }

    // MARK: "Bản quay chưa xuất"

    @Test(arguments: Mode.allCases)
    func theRecordingsThatWereNotExportedCannotBeCleanedByThePage(mode: Mode) async throws {
        let never = try rig.makeRecording(createdAt: Self.now.addingTimeInterval(-900 * Self.day), bytes: 3_000)
        let alsoNever = try rig.makeRecording(bytes: 2_000)
        await prepare(mode)
        let before = diskBytes(rig.recordingsRoot)

        let freed = await module.clean(categoryID: ScreenshotModule.unexportedRecordingsCategoryID, storage: rig.storage)
        // The id the first version of this page used for all recordings does nothing either.
        let old = await module.clean(categoryID: "screenshot.recordings", storage: rig.storage)

        #expect(freed == 0 && old == 0 && exists(never) && exists(alsoNever) && diskBytes(rig.recordingsRoot) == before)
    }

    @Test func theRecordingsThatWereNotExportedStayWhenTheExportedOnesGo() async throws {
        let exported = try rig.makeRecording(bytes: 3_000, exportedAt: Self.exportedRecently)
        let never = try rig.makeRecording(bytes: 2_000)
        await rig.start()

        _ = await module.clean(categoryID: ScreenshotModule.exportedRecordingsCategoryID, storage: rig.storage)
        _ = await module.clean(categoryID: ScreenshotModule.exportedRecordingsCategoryID, storage: rig.storage)

        #expect(!exists(exported) && exists(never))
    }

    @Test func aCleanLeavesTheRecordingBeingMade() async throws {
        let old = try rig.makeRecording(bytes: 3_000, exportedAt: Self.exportedRecently)
        await rig.start()
        try await record()
        let live = try #require(fakes.recorder.currentRecordingID)

        let freed = await module.clean(categoryID: ScreenshotModule.exportedRecordingsCategoryID, storage: rig.storage)

        #expect(!exists(old) && freed >= 3_000)
        #expect(FileManager.default.fileExists(atPath: rig.recordingStore.folder(for: live).appending(path: "project.json").path(percentEncoded: false)))
        #expect(try RecordingProject.load(from: rig.recordingStore.folder(for: live)).status == .recording)
        // And the one being made is shown with the ones that were not exported.
        let categories = await module.storageCategories(storage: rig.storage)
        #expect(categories[2].bytes == diskBytes(rig.recordingStore.folder(for: live)) && categories[1].bytes == 0)
    }

    @Test func aCleanRemovesNothingWhileTheStreamStarts() async throws {
        let old = try rig.makeRecording(bytes: 3_000, exportedAt: Self.exportedRecently)
        await rig.start()
        fakes.recorder.isStartGated = true
        let (settings, keys) = try rig.settings()
        settings.set(false, for: keys.recordCountdown)
        module.beginRecording(.region)
        await rig.waitUntil { rig.phase == .starting }

        let freed = await module.clean(categoryID: ScreenshotModule.exportedRecordingsCategoryID, storage: rig.storage)

        #expect(freed == 0 && exists(old))
        fakes.recorder.releaseStart()
        await rig.waitUntil { rig.phase == .recording }
    }

    @Test func aCleanLeavesARecordingAnEditorHasOpenUntilItIsClosed() async throws {
        let open = try rig.makeRecording(bytes: 3_000, exportedAt: Self.exportedRecently)
        let other = try rig.makeRecording(bytes: 2_000, exportedAt: Self.exportedRecently)
        await rig.start()
        let summary = try #require(await listedRecordings().isEmpty ? nil : module.state.recordings.first { $0.id == open.id })
        module.openRecording(summary)

        _ = await module.clean(categoryID: ScreenshotModule.exportedRecordingsCategoryID, storage: rig.storage)
        #expect(exists(open) && !exists(other))

        editors.close(folder: summary.folder)
        _ = await module.clean(categoryID: ScreenshotModule.exportedRecordingsCategoryID, storage: rig.storage)
        #expect(!exists(open))
    }

    @Test func anUnknownCategoryCleansNothing() async throws {
        let recording = try rig.makeRecording()
        await rig.start()
        #expect(await module.clean(categoryID: "screenshot.nothing", storage: rig.storage) == 0)
        #expect(exists(recording))
    }

    // MARK: The daily rule: captures

    @Test(arguments: Mode.allCases)
    func theDailyRuleKeepsTheNewestCapturesUpToTheKeepCount(mode: Mode) async throws {
        let records = try await makeCaptures(8)
        await prepare(mode)
        try setRules(mode, keepCount: 5)
        let expected = records.prefix(3).reduce(Int64(0)) { total, record in
            total + diskBytes(capturesFolder.appending(path: record.fileName))
        }

        let freed = await module.autoClean(now: Self.now, storage: rig.storage)

        #expect(freed == expected && freed > 0)
        let kept = CaptureStore(directory: rig.storage.directory, cachesDirectory: rig.storage.cachesDirectory, logger: Log.logger(category: "ScreenshotStorageTests")).load()
        #expect(kept.map(\.id) == records.suffix(5).reversed().map(\.id))
        if mode == .running { #expect(module.state.records.map(\.id) == kept.map(\.id)) }
    }

    @Test(arguments: Mode.allCases)
    func theDailyRuleWithinTheKeepCountChangesNothing(mode: Mode) async throws {
        try await makeCaptures(4)
        await prepare(mode)
        try setRules(mode, keepCount: 30)

        #expect(await module.autoClean(now: Self.now, storage: rig.storage) == 0)
        #expect(diskBytes(capturesFolder) > 0)
    }

    @Test func aModuleNeverStartedUsesTheAppsSettingsAndTheStandardKeepCount() async throws {
        try await makeCaptures(40)

        _ = await module.autoClean(now: Self.now, storage: rig.storage)

        let kept = CaptureStore(directory: rig.storage.directory, cachesDirectory: rig.storage.cachesDirectory, logger: Log.logger(category: "ScreenshotStorageTests")).load()
        #expect(kept.count == ScreenshotSettingKeys.defaultKeepCount)
    }

    // MARK: The daily rule: recordings

    @Test(arguments: Mode.allCases)
    func theDailyRuleLeavesEveryRecordingAloneUnlessThePersonTurnedItOn(mode: Mode) async throws {
        let exportedLongAgo = try rig.makeRecording(exportedAt: Self.now.addingTimeInterval(-400 * Self.day))
        let neverExported = try rig.makeRecording()
        await prepare(mode)

        _ = await module.autoClean(now: Self.now, storage: rig.storage)

        #expect(exists(exportedLongAgo) && exists(neverExported))
    }

    @Test(arguments: Mode.allCases)
    func theDailyRuleRemovesOnlyRecordingsThatWereExportedAtLeastTheDaysAgo(mode: Mode) async throws {
        let old = try rig.makeRecording(bytes: 5_000, exportedAt: Self.now.addingTimeInterval(-10 * Self.day))
        let interrupted = try rig.makeRecording(status: .interrupted, bytes: 4_000, exportedAt: Self.now.addingTimeInterval(-20 * Self.day))
        let recent = try rig.makeRecording(exportedAt: Self.now.addingTimeInterval(-3 * Self.day))
        let exactly = try rig.makeRecording(exportedAt: Self.now.addingTimeInterval(-7 * Self.day))
        let justShort = try rig.makeRecording(exportedAt: Self.now.addingTimeInterval(-7 * Self.day + 1))
        // Old, but never exported: its original is the only copy.
        let neverExported = try rig.makeRecording(createdAt: Self.now.addingTimeInterval(-900 * Self.day))
        await prepare(mode)
        // Still marked as being recorded: never taken, whatever it says. (Made after the start, which would have rescued it.)
        let recording = try rig.makeRecording(status: .recording, exportedAt: Self.now.addingTimeInterval(-30 * Self.day))
        try setRules(mode, exportedDays: 7)
        let expected = diskBytes(rig.recordingStore.folder(for: old.id)) + diskBytes(rig.recordingStore.folder(for: interrupted.id))
            + diskBytes(rig.recordingStore.folder(for: exactly.id))

        let freed = await module.autoClean(now: Self.now, storage: rig.storage)

        #expect(freed == expected)
        #expect(!exists(old) && !exists(interrupted) && !exists(exactly))
        #expect(exists(recent) && exists(justShort) && exists(neverExported) && exists(recording))
    }

    @Test func theDailyRuleLeavesARecordingAnEditorHasOpen() async throws {
        let open = try rig.makeRecording(exportedAt: Self.now.addingTimeInterval(-30 * Self.day))
        let other = try rig.makeRecording(exportedAt: Self.now.addingTimeInterval(-30 * Self.day))
        await rig.start()
        try setRules(.running, exportedDays: 7)
        let summary = try #require(await listedRecordings().isEmpty ? nil : module.state.recordings.first { $0.id == open.id })
        module.openRecording(summary)

        _ = await module.autoClean(now: Self.now, storage: rig.storage)

        #expect(exists(open) && !exists(other))
    }

    // MARK: Never during a recording or an export

    @Test func theDailyRuleDoesNothingWhileARecordingIsBeingMade() async throws {
        let captures = try await makeCaptures(8)
        let exported = try rig.makeRecording(exportedAt: Self.now.addingTimeInterval(-30 * Self.day))
        await rig.start()
        try setRules(.running, keepCount: 5, exportedDays: 7)
        try await record()
        let before = diskBytes(capturesFolder)

        #expect(await module.autoClean(now: Self.now, storage: rig.storage) == 0)
        fakes.recorder.state = .paused
        module.toggleRecordingPause()
        await rig.waitUntil { rig.phase == .paused }
        #expect(await module.autoClean(now: Self.now, storage: rig.storage) == 0)

        #expect(diskBytes(capturesFolder) == before && captures.count == 8 && exists(exported))
        #expect(module.state.records.count == 8)
    }

    @Test func theDailyRuleDoesNothingDuringTheCountdownOrWhileSelecting() async throws {
        try await makeCaptures(8)
        let exported = try rig.makeRecording(exportedAt: Self.now.addingTimeInterval(-30 * Self.day))
        await rig.start()
        try setRules(.running, keepCount: 5, exportedDays: 7)
        let before = diskBytes(capturesFolder)
        module.beginRecording(.region)
        await rig.waitUntil { rig.phase == .countdown(3) }

        #expect(await module.autoClean(now: Self.now, storage: rig.storage) == 0)
        #expect(diskBytes(capturesFolder) == before && exists(exported))
        module.cancelRecordingCountdown()
        #expect(await module.autoClean(now: Self.now, storage: rig.storage) > 0)
    }

    @Test func theDailyRuleDoesNothingWhileAnEditorExports() async throws {
        try await makeCaptures(8)
        let exported = try rig.makeRecording(exportedAt: Self.now.addingTimeInterval(-30 * Self.day))
        let other = try rig.makeRecording(exportedAt: Self.now.addingTimeInterval(-30 * Self.day))
        await rig.start()
        try setRules(.running, keepCount: 5, exportedDays: 7)
        let summary = try #require(await listedRecordings().isEmpty ? nil : module.state.recordings.first { $0.id == exported.id })
        module.openRecording(summary)
        editors.isExporting = true
        let before = diskBytes(capturesFolder)

        #expect(await module.autoClean(now: Self.now, storage: rig.storage) == 0)
        #expect(diskBytes(capturesFolder) == before && exists(exported) && exists(other))

        editors.isExporting = false
        #expect(await module.autoClean(now: Self.now, storage: rig.storage) > 0)
        #expect(exists(exported) && !exists(other))
    }

    @Test func nothingIsEverWrittenInTheCachesByTheCleaning() async throws {
        try await makeCaptures(8)
        try rig.makeRecording(exportedAt: Self.now.addingTimeInterval(-30 * Self.day))
        let thumbnails = rig.storage.cachesDirectory.appending(path: "thumbnails", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: thumbnails, withIntermediateDirectories: true)
        try Data(count: 10).write(to: thumbnails.appending(path: "keep.png"))
        await rig.start()
        try setRules(.running, keepCount: 5, exportedDays: 7)

        _ = await module.autoClean(now: Self.now, storage: rig.storage)
        _ = await module.clean(categoryID: ScreenshotModule.exportedRecordingsCategoryID, storage: rig.storage)
        _ = await module.clean(categoryID: ScreenshotModule.capturesCategoryID, storage: rig.storage)

        #expect(!FileManager.default.fileExists(atPath: rig.storage.cachesDirectory.appending(path: "Recordings").path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: thumbnails.appending(path: "keep.png").path(percentEncoded: false)))
    }

    // MARK: The summary

    @Test(arguments: Mode.allCases)
    func theSummaryNamesBothRules(mode: Mode) async throws {
        await prepare(mode)
        #expect(module.autoCleanSummary == "Giữ 30 ảnh chụp gần nhất, không tự xoá bản quay")

        try setRules(mode, keepCount: 12, exportedDays: 14)
        #expect(module.autoCleanSummary == "Giữ 12 ảnh chụp gần nhất, tự xoá bản quay gốc đã xuất sau 14 ngày")
    }

    @Test func aKeepCountOutsideTheLimitsReadsAsTheNearestLimit() async throws {
        try setRules(.neverStarted, keepCount: 1)
        #expect(module.autoCleanSummary?.hasPrefix("Giữ 5 ảnh chụp") == true)
        try setRules(.neverStarted, keepCount: 5_000, exportedDays: 9_999)
        #expect(module.autoCleanSummary == "Giữ 200 ảnh chụp gần nhất, tự xoá bản quay gốc đã xuất sau 365 ngày")
    }

    // MARK: The fallback keys

    @Test func theKeysReadWithoutTheModuleAreTheKeysTheSettingsPageWrites() throws {
        let (settings, keys) = try rig.settings()

        #expect(ScreenshotRetentionKeys.keepCount.name == keys.keepCount.name)
        #expect(ScreenshotRetentionKeys.cleanExportedRecordings.name == keys.cleanExportedRecordings.name)
        #expect(ScreenshotRetentionKeys.exportedRecordingDays.name == keys.exportedRecordingDays.name)
        #expect(ScreenshotRetentionKeys.keepCount.defaultValue == keys.keepCount.defaultValue)
        #expect(ScreenshotRetentionKeys.cleanExportedRecordings.defaultValue == keys.cleanExportedRecordings.defaultValue)
        #expect(ScreenshotRetentionKeys.exportedRecordingDays.defaultValue == keys.exportedRecordingDays.defaultValue)
        #expect(!keys.cleanExportedRecordings.defaultValue)
        // The same limits, read through a store.
        for (low, high) in [(-5, 5_000), (0, 100)] {
            settings.set(low, for: keys.keepCount)
            rig.fallbackSettings.set(low, for: ScreenshotRetentionKeys.keepCount)
            #expect(settings.value(keys.keepCount) == rig.fallbackSettings.value(ScreenshotRetentionKeys.keepCount))
            settings.set(high, for: keys.exportedRecordingDays)
            rig.fallbackSettings.set(high, for: ScreenshotRetentionKeys.exportedRecordingDays)
            #expect(settings.value(keys.exportedRecordingDays) == rig.fallbackSettings.value(ScreenshotRetentionKeys.exportedRecordingDays))
        }
    }

    @Test func theSettingsPageGivesTheModuleItsSettingsWhenItHasNone() throws {
        // A module that never started has only the app's store; the page's rows hand it the real ones.
        try setRules(.neverStarted, keepCount: 40)
        #expect(module.autoCleanSummary?.hasPrefix("Giữ 40 ảnh") == true)
        let environment = try #require(harness.settingsEnvironment(for: "screenshot"))
        environment.settings.set(15, for: ScreenshotSettingKeys(environment.settings).keepCount)

        _ = module.makeSettingsView(environment)

        #expect(module.autoCleanSummary?.hasPrefix("Giữ 15 ảnh") == true)
    }

    // MARK: Logs

    @Test func theLogsHoldNumbersOnly() async throws {
        try await makeCaptures(8)
        let recording = try rig.makeRecording(exportedAt: Self.now.addingTimeInterval(-30 * Self.day))
        await rig.start()
        try setRules(.running, keepCount: 5, exportedDays: 7)

        _ = await module.autoClean(now: Self.now, storage: rig.storage)
        _ = await module.clean(categoryID: ScreenshotModule.exportedRecordingsCategoryID, storage: rig.storage)
        _ = await module.clean(categoryID: ScreenshotModule.capturesCategoryID, storage: rig.storage)

        #expect(reports.lines.count == 3)
        let uuid = /[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-/
        for line in reports.lines {
            #expect(line.hasPrefix("storage: ") && line.contains(where: \.isNumber))
            #expect(!line.contains("/") && !line.contains(".png") && !line.contains(".mov") && !line.contains(".mp4") && !line.contains("json"))
            #expect(!line.contains(rig.temporaryRoot.lastPathComponent) && !line.contains(recording.id.uuidString) && line.firstMatch(of: uuid) == nil)
        }
    }

    // MARK: The page

    @Test func theStoragePageSeesAllThreeCategoriesWhileTheModuleIsOffAndCleansOnlyWhatMayGo() async throws {
        try await makeCaptures(3)
        let exported = try rig.makeRecording(bytes: 8_000, exportedAt: Self.exportedRecently)
        let never = try rig.makeRecording(createdAt: Self.now.addingTimeInterval(-900 * Self.day), bytes: 5_000)
        await rig.start()
        await harness.registry.setEnabled(false, for: "screenshot")
        let center = harness.registry.storageCenter

        await center.refresh()

        let group = try #require(center.groups.first { $0.id == "screenshot" })
        #expect(group.categories.map(\.id) == [
            "screenshot.captures", "screenshot.recordings.exported", "screenshot.recordings.unexported", "screenshot.cache",
        ])
        #expect(group.categories[0].bytes > 0 && group.categories[1].bytes >= 8_000 && group.categories[2].bytes >= 5_000)
        #expect(group.autoCleanSummary == "Giữ 30 ảnh chụp gần nhất, không tự xoá bản quay")
        // What "Dọn tất cả" would free leaves out the recordings that were not exported.
        #expect(center.cleanableBytes == group.categories[0].bytes + group.categories[1].bytes + group.categories[3].bytes)

        let freed = await center.clean("screenshot.recordings.exported")
        #expect(freed >= 8_000 && !exists(exported) && exists(never))
        // Cleaning the other one by its id does nothing.
        #expect(await center.clean("screenshot.recordings.unexported") == 0)
        #expect(exists(never))

        // "Dọn tất cả" takes the captures and, if there were any left, the exported ones, and never the other.
        let second = try rig.makeRecording(bytes: 4_000, exportedAt: Self.exportedRecently)
        await center.refresh()
        _ = await center.cleanAll()
        await center.refresh()
        let after = try #require(center.groups.first { $0.id == "screenshot" })
        #expect(after.categories[0].bytes == 0 && after.categories[1].bytes == 0)
        #expect(!exists(second) && exists(never) && after.categories[2].bytes >= 5_000)
    }

    @Test func theDailyRunOfThePageAppliesTheRuleToAModuleThatIsOff() async throws {
        try await makeCaptures(8)
        let exported = try rig.makeRecording(exportedAt: Self.now.addingTimeInterval(-30 * Self.day))
        try setRules(.neverStarted, keepCount: 5, exportedDays: 7)

        let freed = await harness.registry.storageCenter.autoClean(now: Self.now)

        #expect(freed > 0 && !exists(exported))
        let kept = CaptureStore(directory: rig.storage.directory, cachesDirectory: rig.storage.cachesDirectory, logger: Log.logger(category: "ScreenshotStorageTests")).load()
        #expect(kept.count == 5)
    }
}
