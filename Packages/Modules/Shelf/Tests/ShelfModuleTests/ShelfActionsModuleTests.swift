import AppKit
import CoreGraphics
import Foundation
import ImageIO
import MyNotchCore
import Testing
import UniformTypeIdentifiers
@testable import ShelfModule

/// The "Hành động" row from the module's side: what is selected, what a run gets from the settings, and where the
/// results land on the shelf.
@Suite struct ShelfActionsModuleTests {
    func started(_ fixture: ShelfFixture = ShelfFixture()) async -> ShelfFixture {
        await fixture.start()
        return fixture
    }

    /// Puts the files on the shelf in the order given and returns their items.
    func shelve(_ urls: [URL], in fixture: ShelfFixture) async -> [ShelfItem] {
        _ = await fixture.module.add(providers: urls.map { NSItemProvider(object: $0 as NSURL) })
        return fixture.items
    }

    func png(_ name: String, _ width: Int = 2000, _ height: Int = 1000, in folder: URL) throws -> URL {
        try SyntheticFiles.write(SyntheticFiles.image(width: width, height: height), as: .png, named: name, in: folder)
    }

    func finish(_ fixture: ShelfFixture) async {
        await fixture.module.state.actions.currentRun?.value
    }

    /// The report of the run that has finished.
    func finished(_ fixture: ShelfFixture) -> FileActionRunner.Report? {
        if case .finished(let report) = fixture.module.state.actions.phase { report } else { nil }
    }

    func fileNames(_ fixture: ShelfFixture) -> [String] {
        fixture.items.compactMap { fixture.module.state.store?.url(of: $0)?.lastPathComponent }
    }

    // MARK: Selection

    @Test func clickingAFileCardSelectsItAndClickingAgainClearsIt() async throws {
        let fixture = await started()
        let folder = try makeTempDirectory()
        let items = await shelve([try png("a.png", in: folder), try png("b.png", in: folder)], in: fixture)
        fixture.module.toggleSelection(items[1])
        fixture.module.toggleSelection(items[0])
        #expect(fixture.module.isSelected(items[0]) && fixture.module.isSelected(items[1]))
        // In the order they were picked, which is the page order of a PDF.
        #expect(fixture.module.selectedItems.map(\.id) == [items[1].id, items[0].id])
        fixture.module.toggleSelection(items[1])
        #expect(!fixture.module.isSelected(items[1]) && fixture.module.selectedItems.map(\.id) == [items[0].id])
    }

    @Test func textAndLinkCardsCannotBeSelected() async throws {
        let fixture = await started()
        _ = await fixture.module.add(providers: [NSItemProvider(object: "ghi chú" as NSString), NSItemProvider(object: URL(string: "https://example.com")! as NSURL)])
        for item in fixture.items { fixture.module.toggleSelection(item) }
        #expect(fixture.module.selectedItems.isEmpty)
    }

    @Test func removingACardTakesItOutOfTheSelection() async throws {
        let fixture = await started()
        let items = await shelve([try png("a.png", in: try makeTempDirectory())], in: fixture)
        fixture.module.toggleSelection(items[0])
        fixture.module.remove(items[0])
        #expect(fixture.module.selectedItems.isEmpty && fixture.module.state.selection.isEmpty)
    }

    @Test func clearingTheShelfClearsTheSelection() async throws {
        let fixture = await started()
        let items = await shelve([try png("a.png", in: try makeTempDirectory())], in: fixture)
        fixture.module.toggleSelection(items[0])
        fixture.module.removeAll()
        #expect(fixture.module.state.selection.isEmpty)
    }

    // MARK: Running

    @Test func resultsAppearAsNewShelfItemsNextToTheirSourcesWithoutOverwriting() async throws {
        let fixture = await started()
        let folder = try makeTempDirectory()
        let items = await shelve([try png("a.png", in: folder), try png("b.png", in: folder)], in: fixture)
        fixture.module.runAction(.resize(.side800), on: items)
        await finish(fixture)
        // Each result goes to the front as soon as it is made, so the newest is first, as on the rest of the shelf.
        #expect(fileNames(fixture) == ["b-800.png", "a-800.png", "a.png", "b.png"])
        let result = try #require(fixture.items.first)
        #expect(fixture.module.state.store?.url(of: result)?.deletingLastPathComponent().resolvingSymlinksInPath() == folder.resolvingSymlinksInPath())
        #expect(finished(fixture)?.created.count == 2)

        // A second run finds the first results in the way and goes around them.
        fixture.module.state.actions.dismiss()
        fixture.module.runAction(.resize(.side800), on: items)
        await finish(fixture)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)) == ["a.png", "b.png", "a-800.png", "b-800.png", "a-800 2.png", "b-800 2.png"])
    }

    @Test func theQualitySettingGoesIntoTheResult() async throws {
        let fixture = await started()
        let folder = try makeTempDirectory()
        let source = try SyntheticFiles.write(ImageCodecTests.noisyImage(), as: .png, named: "ồn.png", in: folder)
        let items = await shelve([source], in: fixture)
        let size = { (url: URL) in (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }

        fixture.settings.set(0.2, for: fixture.keys.imageQuality)
        fixture.module.runAction(.compressImage(.jpeg), on: items)
        await finish(fixture)
        let low = try #require(finished(fixture)?.created.first)
        fixture.module.state.actions.dismiss()

        fixture.settings.set(0.95, for: fixture.keys.imageQuality)
        fixture.module.runAction(.compressImage(.jpeg), on: items)
        await finish(fixture)
        let high = try #require(finished(fixture)?.created.first)
        #expect(size(low) < size(high))
    }

    @Test func theLocationSettingDecidesWhetherGPSGoesAlong() async throws {
        let fixture = await started()
        let folder = try makeTempDirectory()
        let source = try SyntheticFiles.write(
            SyntheticFiles.image(width: 2000, height: 1000), as: .jpeg, named: "gps.jpg", in: folder, properties: [kCGImagePropertyGPSDictionary: SyntheticFiles.gps]
        )
        let items = await shelve([source], in: fixture)
        fixture.module.runAction(.resize(.side800), on: items)
        await finish(fixture)
        let stripped = try #require(finished(fixture)?.created.first)
        #expect(try SyntheticFiles.properties(of: stripped)[kCGImagePropertyGPSDictionary] == nil)
        fixture.module.state.actions.dismiss()

        fixture.settings.set(false, for: fixture.keys.stripLocation)
        fixture.module.runAction(.resize(.side800), on: items)
        await finish(fixture)
        let kept = try #require(finished(fixture)?.created.first)
        #expect(try SyntheticFiles.properties(of: kept)[kCGImagePropertyGPSDictionary] != nil)
    }

    @Test func readingTextCopiesItToTheFakePasteboardAndShowsItInTheReport() async throws {
        let fixture = await started(ShelfFixture(recognizer: FakeRecognizer { _ in "Xin chào" }))
        let items = await shelve([try png("a.png", 200, 100, in: try makeTempDirectory())], in: fixture)
        fixture.module.runAction(.readText, on: items)
        await finish(fixture)
        #expect(finished(fixture)?.text == "Xin chào")
        #expect(finished(fixture)?.textCopied == true)
        #expect(fixture.pasteboard.written == ["Xin chào"])
        // Nothing new on the shelf: the text is not a file.
        #expect(fixture.items.count == 1)
    }

    @Test func theTextOfAReportCanBeCopiedAgain() async throws {
        let fixture = await started(ShelfFixture(recognizer: FakeRecognizer { _ in "Xin chào" }))
        let items = await shelve([try png("a.png", 200, 100, in: try makeTempDirectory())], in: fixture)
        fixture.module.runAction(.readText, on: items)
        await finish(fixture)
        fixture.pasteboard.accepts = false
        #expect(fixture.module.copyReportText() == false)
        fixture.pasteboard.accepts = true
        #expect(fixture.module.copyReportText())
        #expect(fixture.pasteboard.written == ["Xin chào", "Xin chào"])
    }

    @Test func aCutOutKeepsTheOriginalAndAddsAPNG() async throws {
        let cutter = FakeCutter()
        let fixture = await started(ShelfFixture(cutter: cutter))
        let folder = try makeTempDirectory()
        let items = await shelve([try png("người.png", 100, 60, in: folder)], in: fixture)
        fixture.module.runAction(.cutOut, on: items)
        await finish(fixture)
        #expect(fileNames(fixture) == ["người-không-nền.png", "người.png"])
        #expect(cutter.calls == 1)
    }

    @Test func aNoteIsLeftOutAndAFileThatWentIsNamed() async throws {
        let fixture = await started()
        let folder = try makeTempDirectory()
        let good = try png("a.png", in: folder), doomed = try png("b.png", in: folder)
        _ = await fixture.module.add(providers: [NSItemProvider(object: "ghi chú" as NSString)])
        _ = await shelve([good, doomed], in: fixture)
        try FileManager.default.removeItem(at: doomed)
        fixture.module.runAction(.resize(.side800), on: fixture.items)
        await finish(fixture)
        let report = try #require(finished(fixture))
        #expect(report.created.map(\.lastPathComponent) == ["a-800.png"])
        #expect(report.failures == [.init(name: "b.png", message: "Không tìm thấy file (đã bị chuyển hoặc xoá)")])
    }

    @Test func anActionOnOnlyTextDoesNothing() async throws {
        let fixture = await started()
        _ = await fixture.module.add(providers: [NSItemProvider(object: "ghi chú" as NSString)])
        fixture.module.runAction(.zip, on: fixture.items)
        #expect(fixture.module.state.actions.phase == .idle)
    }

    @Test func aFileThatMovedIsFoundAgainByItsBookmark() async throws {
        let fixture = await started()
        let folder = try makeTempDirectory()
        let items = await shelve([try png("a.png", in: folder)], in: fixture)
        let moved = folder.appending(path: "mới.png")
        try FileManager.default.moveItem(at: folder.appending(path: "a.png"), to: moved)
        fixture.module.runAction(.resize(.side800), on: items)
        await finish(fixture)
        #expect(finished(fixture)?.created.map(\.lastPathComponent) == ["mới-800.png"])
    }

    @Test func aSecondActionIsIgnoredWhileOneRuns() async throws {
        let gate = Gate()
        let fixture = await started(ShelfFixture(recognizer: FakeRecognizer { _ in
            await gate.pass()
            return "chữ"
        }))
        let items = await shelve([try png("a.png", 200, 100, in: try makeTempDirectory())], in: fixture)
        fixture.module.runAction(.readText, on: items)
        fixture.module.runAction(.resize(.half), on: items)
        await gate.waitForArrivals(1)
        await gate.release()
        await finish(fixture)
        #expect(finished(fixture)?.action == .readText)
        #expect(fixture.items.count == 1)
    }

    // MARK: Dropping on the row

    @Test func aFileDroppedOnAGroupJoinsTheShelfAndRunsTheChoiceUsedLast() async throws {
        let fixture = await started()
        let folder = try makeTempDirectory()
        let items = await shelve([try png("a.png", in: folder)], in: fixture)
        fixture.module.runAction(.resize(.side800), on: items)
        await finish(fixture)
        fixture.module.state.actions.dismiss()

        let dropped = try png("b.png", in: folder)
        await fixture.module.runAction(on: .resize, dropped: [NSItemProvider(object: dropped as NSURL)])
        await finish(fixture)
        #expect(finished(fixture)?.created.map(\.lastPathComponent) == ["b-800.png"])
        #expect(fileNames(fixture).contains("b.png"))
    }

    @Test func aGroupNeverUsedRunsItsFirstChoice() async throws {
        let fixture = await started()
        let folder = try makeTempDirectory()
        let jpeg = try SyntheticFiles.write(SyntheticFiles.image(width: 40, height: 40), as: .jpeg, named: "a.jpg", in: folder)
        await fixture.module.runAction(on: .convert, dropped: [NSItemProvider(object: jpeg as NSURL)])
        await finish(fixture)
        // The first choice of "Đổi định dạng" is PNG.
        #expect(finished(fixture)?.created.map(\.lastPathComponent) == ["a.png"])
    }

    @Test func pdfsDroppedOnThePDFGroupAreSplitAndImagesAreMerged() async throws {
        let fixture = await started()
        let folder = try makeTempDirectory()
        let pdf = try SyntheticFiles.pdf(pages: 2, size: CGSize(width: 40, height: 40), named: "d.pdf", in: folder)
        await fixture.module.runAction(on: .pdf, dropped: [NSItemProvider(object: pdf as NSURL)])
        await finish(fixture)
        #expect(finished(fixture)?.created.map(\.lastPathComponent) == ["d-trang-1.png", "d-trang-2.png"])
        fixture.module.state.actions.dismiss()

        let one = try png("x.png", 30, 30, in: folder), two = try png("y.png", 30, 30, in: folder)
        await fixture.module.runAction(on: .pdf, dropped: [NSItemProvider(object: one as NSURL), NSItemProvider(object: two as NSURL)])
        await finish(fixture)
        #expect(finished(fixture)?.created.map(\.lastPathComponent) == ["x.pdf"])
    }

    @Test func aDropThatHoldsNoFileRunsNothing() async throws {
        let fixture = await started()
        await fixture.module.runAction(on: .convert, dropped: [NSItemProvider(object: "ghi chú" as NSString)])
        #expect(fixture.module.state.actions.phase == .idle)
    }

    @Test func aDropWhileStoppedIsRefused() {
        let module = ShelfModule()
        #expect(module.runAction(on: .convert, dropping: [NSItemProvider(object: URL(filePath: "/tmp/x.png") as NSURL)]) == false)
    }

    // MARK: Promised copies

    @Test func aResultForAPromisedCopySurvivesRemovingTheOriginal() async throws {
        let fixture = await started()
        let image = SyntheticFiles.image(width: 2000, height: 1000)
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        let bytes = data as Data
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            completion(bytes, nil)
            return nil
        }
        _ = await fixture.module.add(providers: [provider])
        let original = try #require(fixture.items.first)
        fixture.module.runAction(.resize(.side800), on: [original])
        await finish(fixture)
        let result = try #require(finished(fixture)?.created.first)
        #expect(exists(result))
        #expect(fixture.items.count == 2)

        fixture.module.remove(original)
        #expect(exists(result))
        #expect(fixture.items.count == 1)
        let reloaded = ShelfStore(directory: fixture.storage.directory, limit: 50)
        #expect(reloaded.items.count == 1 && exists(result))
    }

    // MARK: Stopping

    @Test func stoppingEndsTheRunAndClearsTheSelectionAndTheReport() async throws {
        let fixture = await started(ShelfFixture(recognizer: FakeRecognizer { _ in
            try await Task.sleep(for: .seconds(60))
            return "chữ"
        }))
        let items = await shelve([try png("a.png", 200, 100, in: try makeTempDirectory())], in: fixture)
        fixture.module.toggleSelection(items[0])
        fixture.module.runAction(.readText, on: items)
        let run = try #require(fixture.module.state.actions.currentRun)
        await fixture.harness.registry.pauseAll()
        await run.value
        #expect(fixture.module.state.actions.phase == .idle)
        #expect(fixture.module.state.selection.isEmpty)
    }

    @Test func resultsOfARunThatOutlivedItsShelfAreNotAddedToTheNextOne() async throws {
        let gate = Gate()
        let fixture = await started(ShelfFixture(cutter: FakeCutter { image in
            await gate.pass()
            return FakeCutter.leftHalfCleared(image)
        }))
        let folder = try makeTempDirectory()
        let items = await shelve([try png("a.png", 100, 60, in: folder)], in: fixture)
        fixture.module.runAction(.cutOut, on: items)
        let run = try #require(fixture.module.state.actions.currentRun)
        await gate.waitForArrivals(1)
        await fixture.harness.registry.pauseAll()
        await gate.release()
        await run.value
        await fixture.harness.registry.resumeAll()
        // The new shelf has what the old one saved, and the result is a file on disk but no card.
        #expect(fixture.items.count == 1)
    }
}
