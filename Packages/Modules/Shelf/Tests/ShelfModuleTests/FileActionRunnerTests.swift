import Foundation
import Testing
@testable import ShelfModule

/// Lets a test hold a fake's work at a point and see how far a run got.
actor Gate {
    private var tokens = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var arrivals = 0
    private var arrivalWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    /// Called by the fake: counts as an arrival and returns once the test releases it.
    func pass() async {
        arrivals += 1
        for waiter in arrivalWaiters.filter({ $0.count <= arrivals }) { waiter.continuation.resume() }
        arrivalWaiters.removeAll { $0.count <= arrivals }
        if tokens > 0 {
            tokens -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty { tokens += 1 } else { waiters.removeFirst().resume() }
    }

    func waitForArrivals(_ count: Int) async {
        if arrivals >= count { return }
        await withCheckedContinuation { arrivalWaiters.append((count, $0)) }
    }
}

@Suite struct FileActionRunnerTests {
    let pasteboard = FakePasteboard()
    let runner = FileActionRunner()

    func source(_ url: URL) -> ActionSource { ActionSource(name: url.lastPathComponent, url: url) }

    func images(_ count: Int, size: (Int, Int) = (2000, 1000), in folder: URL) throws -> [URL] {
        try (1...count).map { try SyntheticFiles.write(SyntheticFiles.image(width: size.0, height: size.1), as: .png, named: "ảnh-\($0).png", in: folder) }
    }

    func run(_ action: FileAction, _ sources: [ActionSource], processor: FileActionProcessor = FileActionProcessor(), delivered: Delivered = Delivered()) async {
        await runner.run(action, sources: sources, processor: processor, pasteboard: pasteboard, deliver: delivered.receive)
    }

    var report: FileActionRunner.Report? {
        if case .finished(let report) = runner.phase { report } else { nil }
    }

    // MARK: Results

    @Test func eachSourceIsProcessedInOrderAndItsResultsAreDeliveredAtOnce() async throws {
        let folder = try makeTempDirectory()
        let urls = try images(3, in: folder)
        let delivered = Delivered()
        await run(.resize(.side800), urls.map(source), delivered: delivered)
        #expect(delivered.batches.map { $0.map(\.lastPathComponent) } == [["ảnh-1-800.png"], ["ảnh-2-800.png"], ["ảnh-3-800.png"]])
        let report = try #require(report)
        #expect(report.created.count == 3 && report.failures.isEmpty && !report.wasCancelled)
        #expect(report.text == nil)
    }

    @Test func aFileThatFailsDoesNotStopTheOthersAndEachErrorNamesItsFile() async throws {
        let folder = try makeTempDirectory()
        let good = try images(1, in: folder)[0]
        let corrupt = folder.appending(path: "hỏng.png")
        try Data("x".utf8).write(to: corrupt)
        let small = try SyntheticFiles.write(SyntheticFiles.image(width: 100, height: 50), as: .png, named: "nhỏ.png", in: folder)
        let gone = ActionSource(name: "mất.png", url: nil)
        let delivered = Delivered()
        await run(.resize(.side800), [source(corrupt), gone, source(small), source(good)], delivered: delivered)
        let report = try #require(report)
        #expect(report.created.map(\.lastPathComponent) == ["ảnh-1-800.png"])
        #expect(report.failures == [
            .init(name: "hỏng.png", message: "Không phải ảnh, hoặc ảnh bị hỏng"),
            .init(name: "mất.png", message: "Không tìm thấy file (đã bị chuyển hoặc xoá)"),
            .init(name: "nhỏ.png", message: "Ảnh đã nhỏ hơn mức này"),
        ])
        #expect(delivered.batches.count == 1)
    }

    @Test func recognisedTextIsJoinedCopiedAndKeptForTheCard() async throws {
        let folder = try makeTempDirectory()
        let urls = try images(2, in: folder)
        let words = Delivered.Words(["Một", "Hai"])
        let recognizer = FakeRecognizer { _ in words.next() }
        await run(.readText, urls.map(source), processor: FileActionProcessor(recognizer: recognizer))
        let report = try #require(report)
        #expect(report.text == "Một\n\nHai")
        #expect(report.textCopied)
        #expect(pasteboard.written == ["Một\n\nHai"])
        #expect(report.created.isEmpty)
    }

    @Test func textThatCannotBeCopiedIsStillShown() async throws {
        let folder = try makeTempDirectory()
        pasteboard.accepts = false
        await run(.readText, try images(1, in: folder).map(source), processor: FileActionProcessor(recognizer: FakeRecognizer { _ in "chữ" }))
        let report = try #require(report)
        #expect(report.text == "chữ" && !report.textCopied)
    }

    @Test func aPictureWithoutTextCopiesNothing() async throws {
        let folder = try makeTempDirectory()
        await run(.readText, try images(1, in: folder).map(source), processor: FileActionProcessor(recognizer: FakeRecognizer { _ in "" }))
        let report = try #require(report)
        #expect(report.text == nil && pasteboard.written.isEmpty)
        #expect(report.failures.map(\.message) == ["Không thấy chữ"])
    }

    @Test func severalSourcesMakeOneZipDeliveredOnce() async throws {
        let folder = try makeTempDirectory()
        let a = try makeTempFile(named: "a.txt", in: folder), b = try makeTempFile(named: "b.txt", in: folder)
        let delivered = Delivered()
        await run(.zip, [source(a), source(b), ActionSource(name: "mất.txt", url: nil)], delivered: delivered)
        let report = try #require(report)
        #expect(delivered.batches.map { $0.map(\.lastPathComponent) } == [["Lưu trữ.zip"]])
        #expect(report.failures == [.init(name: "mất.txt", message: "Không tìm thấy file (đã bị chuyển hoặc xoá)")])
    }

    @Test func imagesThatCannotBeMergedAreNamedAndTheRestMakeThePDF() async throws {
        let folder = try makeTempDirectory()
        let good = try images(1, size: (50, 50), in: folder)[0]
        let bad = try makeTempFile(named: "hỏng.png", in: folder)
        await run(.imagesToPDF, [source(good), source(bad)])
        let report = try #require(report)
        #expect(report.created.map(\.lastPathComponent) == ["ảnh-1.pdf"])
        #expect(report.failures == [.init(name: "hỏng.png", message: "Không phải ảnh, hoặc ảnh bị hỏng")])
    }

    @Test func aCombinedActionThatFailsAsAWholeReportsOneError() async throws {
        let folder = try makeTempDirectory()
        let bad = try makeTempFile(named: "hỏng.png", in: folder)
        let delivered = Delivered()
        await run(.imagesToPDF, [source(bad)], delivered: delivered)
        let report = try #require(report)
        #expect(report.failures == [.init(name: "hỏng.png", message: "Không có ảnh nào để gộp")])
        #expect(delivered.batches.isEmpty && report.created.isEmpty)
    }

    @Test func aZipOfNothingThatExistsReportsOneError() async throws {
        await run(.zip, [ActionSource(name: "mất.txt", url: nil), ActionSource(name: "mất 2.txt", url: nil)])
        let report = try #require(report)
        #expect(report.failures.map(\.name) == ["mất.txt", "mất 2.txt"])
    }

    // MARK: Progress and cancelling

    @Test func progressNamesTheFileBeingWorkedOnAndCountsTheOnesDone() async throws {
        let folder = try makeTempDirectory()
        let urls = try images(3, in: folder)
        let gate = Gate()
        let processor = FileActionProcessor(recognizer: FakeRecognizer { _ in
            await gate.pass()
            return "chữ"
        })
        runner.start(.readText, sources: urls.map(source), processor: processor, pasteboard: pasteboard, deliver: { _ in [] })
        #expect(runner.isRunning)
        await gate.waitForArrivals(1)
        #expect(runner.phase == .running(.init(action: .readText, done: 0, total: 3, current: "ảnh-1.png")))
        await gate.release()
        await gate.waitForArrivals(2)
        #expect(runner.phase == .running(.init(action: .readText, done: 1, total: 3, current: "ảnh-2.png")))
        await gate.release()
        await gate.release()
        await runner.currentRun?.value
        #expect(!runner.isRunning)
        #expect(report?.text != nil)
    }

    @Test func aCombinedActionHasNoCountToShow() async throws {
        let folder = try makeTempDirectory()
        let a = try makeTempFile(named: "a.txt", in: folder)
        runner.start(.zip, sources: [source(a)], processor: FileActionProcessor(), pasteboard: pasteboard, deliver: { _ in [] })
        #expect(runner.phase == .running(.init(action: .zip, done: 0, total: nil, current: "a.txt")))
        await runner.currentRun?.value
        #expect(report?.created.count == 1)
    }

    @Test func cancellingStopsBeforeTheNextFileAndKeepsWhatWasDone() async throws {
        let folder = try makeTempDirectory()
        let urls = try images(3, size: (100, 60), in: folder)
        let gate = Gate()
        let cutter = FakeCutter { image in
            await gate.pass()
            try Task.checkCancellation()
            return FakeCutter.leftHalfCleared(image)
        }
        let delivered = Delivered()
        runner.start(.cutOut, sources: urls.map(source), processor: FileActionProcessor(cutter: cutter), pasteboard: pasteboard, deliver: delivered.receive)
        await gate.waitForArrivals(1)
        await gate.release()
        // The first file is done and the second is in the cutter when the user cancels.
        await gate.waitForArrivals(2)
        runner.cancel()
        await gate.release()
        await runner.currentRun?.value
        let report = try #require(report)
        #expect(report.wasCancelled)
        #expect(cutter.calls == 2)
        #expect(report.created.map(\.lastPathComponent) == ["ảnh-1-không-nền.png"])
        #expect(delivered.batches.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 4)
    }

    @Test func cancellingARunWithNothingDeliveredYetLeavesNothing() async throws {
        let folder = try makeTempDirectory()
        let urls = try images(2, in: folder)
        let recognizer = FakeRecognizer { _ in
            try await Task.sleep(for: .seconds(60))
            return "chữ"
        }
        let delivered = Delivered()
        runner.start(.readText, sources: urls.map(source), processor: FileActionProcessor(recognizer: recognizer), pasteboard: pasteboard, deliver: delivered.receive)
        // The first file is being read when the user cancels.
        await eventually { !recognizer.requests.isEmpty }
        runner.cancel()
        await runner.currentRun?.value
        let report = try #require(report)
        #expect(report.wasCancelled && report.created.isEmpty && report.text == nil)
        #expect(recognizer.requests.count == 1)
        #expect(delivered.batches.isEmpty && pasteboard.written.isEmpty)
    }

    @Test func cancellingAZipWritesNoZip() async throws {
        let folder = try makeTempDirectory()
        let a = try makeTempFile(named: "a.txt", in: folder)
        runner.start(.zip, sources: [source(a)], processor: FileActionProcessor(), pasteboard: pasteboard, deliver: { _ in [] })
        runner.cancel()
        await runner.currentRun?.value
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(report?.wasCancelled == true)
        #expect(names == ["a.txt"])
    }

    // MARK: One run at a time

    @Test func aSecondRunIsIgnoredWhileOneIsRunning() async throws {
        let folder = try makeTempDirectory()
        let urls = try images(1, in: folder)
        let gate = Gate()
        let processor = FileActionProcessor(recognizer: FakeRecognizer { _ in
            await gate.pass()
            return "chữ"
        })
        runner.start(.readText, sources: urls.map(source), processor: processor, pasteboard: pasteboard, deliver: { _ in [] })
        runner.start(.resize(.side800), sources: urls.map(source), processor: processor, pasteboard: pasteboard, deliver: { _ in [] })
        await gate.waitForArrivals(1)
        runner.dismiss()
        #expect(runner.isRunning)
        await gate.release()
        await runner.currentRun?.value
        #expect(report?.action == .readText)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["ảnh-1.png"])
    }

    @Test func filesThatDidNotFitOnTheShelfAreReportedWithTheirFolder() async throws {
        let folder = try makeTempDirectory()
        let urls = try images(3, in: folder)
        await run(.resize(.side800), urls.map(source), delivered: Delivered(room: 1))
        let report = try #require(report)
        #expect(report.created.count == 3)
        #expect(report.notShelved.map(\.url.lastPathComponent) == ["ảnh-2-800.png", "ảnh-3-800.png"])
    }

    @Test func cancellingShowsThatTheRunIsStoppingUntilItHas() async throws {
        let folder = try makeTempDirectory()
        let urls = try images(2, in: folder)
        let gate = Gate()
        let processor = FileActionProcessor(recognizer: FakeRecognizer { _ in
            await gate.pass()
            return "chữ"
        })
        runner.start(.readText, sources: urls.map(source), processor: processor, pasteboard: pasteboard, deliver: { _ in [] })
        await gate.waitForArrivals(1)
        runner.cancel()
        let running = try #require({ () -> FileActionRunner.Progress? in
            if case .running(let progress) = runner.phase { progress } else { nil }
        }())
        #expect(running.isCancelling && running.detail == "Đang huỷ…")
        await gate.release()
        await runner.currentRun?.value
        #expect(report?.wasCancelled == true)
    }

    @Test func progressInsideASourceCountsTowardsTheBarAndNeverGoesBack() async throws {
        let folder = try makeTempDirectory()
        let urls = try images(1, in: folder)
        let gate = Gate()
        let processor = FileActionProcessor(recognizer: FakeRecognizer { _ in
            await gate.pass()
            return "chữ"
        })
        runner.start(.readText, sources: urls.map(source), processor: processor, pasteboard: pasteboard, deliver: { _ in [] })
        await gate.waitForArrivals(1)
        let token = runner.generation
        func fraction() -> Double? {
            if case .running(let progress) = runner.phase { progress.fraction } else { nil }
        }
        runner.noteFraction(0.4, run: token, source: 0)
        #expect(fraction() == 0.4)
        runner.noteFraction(0.2, run: token, source: 0)
        runner.noteFraction(0.9, run: token, source: 1)
        runner.noteFraction(0.9, run: token - 1, source: 0)
        #expect(fraction() == 0.4)
        await gate.release()
        await runner.currentRun?.value
    }

    @Test func resetStopsTheRunAndItsLateEndLeavesNoReportBehind() async throws {
        let folder = try makeTempDirectory()
        let urls = try images(2, in: folder)
        let recognizer = FakeRecognizer { _ in
            try await Task.sleep(for: .seconds(60))
            return "chữ"
        }
        runner.start(.readText, sources: urls.map(source), processor: FileActionProcessor(recognizer: recognizer), pasteboard: pasteboard, deliver: { _ in [] })
        await eventually { !recognizer.requests.isEmpty }
        let stopped = try #require(runner.currentRun)
        runner.reset()
        #expect(runner.phase == .idle)
        await stopped.value
        #expect(runner.phase == .idle)
        #expect(pasteboard.written.isEmpty)
    }

    @Test func aRunStartedRightAfterAResetIsNotOverwrittenByTheOldOne() async throws {
        let folder = try makeTempDirectory()
        let urls = try images(1, in: folder)
        let old = FakeRecognizer { _ in
            try await Task.sleep(for: .seconds(60))
            return "cũ"
        }
        runner.start(.readText, sources: urls.map(source), processor: FileActionProcessor(recognizer: old), pasteboard: pasteboard, deliver: { _ in [] })
        await eventually { !old.requests.isEmpty }
        let stopped = try #require(runner.currentRun)
        runner.reset()
        runner.start(.readText, sources: urls.map(source), processor: FileActionProcessor(recognizer: FakeRecognizer { _ in "mới" }), pasteboard: pasteboard, deliver: { _ in [] })
        await stopped.value
        await runner.currentRun?.value
        #expect(report?.text == "mới")
        #expect(pasteboard.written == ["mới"])
    }

    @Test func dismissingTheReportReturnsToIdle() async throws {
        let folder = try makeTempDirectory()
        await run(.resize(.side800), try images(1, in: folder).map(source))
        #expect(report != nil)
        runner.dismiss()
        #expect(runner.phase == .idle)
    }
}

/// What a run delivered to the shelf, one batch per call. `room` is how many files the shelf still takes; the
/// ones past it come back as not shelved.
final class Delivered {
    private(set) var batches: [[URL]] = []
    var room: Int

    init(room: Int = .max) { self.room = room }

    func receive(_ urls: [URL]) async -> [UnshelvedResult] {
        batches.append(urls)
        let taken = min(room, urls.count)
        room -= taken
        return urls.dropFirst(taken).map { UnshelvedResult(url: $0, reason: .shelfFull) }
    }

    /// The progress values a processor reported, from any thread.
    nonisolated final class Fractions: @unchecked Sendable {
        private let lock = NSLock()
        private var seen: [Double] = []
        func add(_ value: Double) { lock.withLock { seen.append(value) } }
        var values: [Double] { lock.withLock { seen } }
    }

    /// Hands out strings in turn.
    nonisolated final class Words: @unchecked Sendable {
        private let lock = NSLock()
        private var remaining: [String]
        init(_ words: [String]) { remaining = words }
        func next() -> String { lock.withLock { remaining.isEmpty ? "" : remaining.removeFirst() } }
    }
}


/// Waits until `condition` holds and records a failure after thirty seconds, so a fake that is never called fails the
/// test instead of hanging it. Thirty, since the suite runs in parallel on a machine that may be busy building.
func eventually(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
    let deadline = ContinuousClock.now + .seconds(30)
    while !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("Timed out waiting", sourceLocation: sourceLocation)
            return
        }
        await Task.yield()
    }
}
