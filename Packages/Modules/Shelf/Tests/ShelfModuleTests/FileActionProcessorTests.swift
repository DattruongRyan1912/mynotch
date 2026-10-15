import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ShelfModule

/// Every action on files generated in code under a temporary folder.
@Suite struct FileActionProcessorTests {
    func processor(
        recognizer: FakeRecognizer = FakeRecognizer(), cutter: FakeCutter = FakeCutter(), quality: Double = 0.85, stripLocation: Bool = true,
        promised: URL? = nil
    ) -> FileActionProcessor {
        FileActionProcessor(
            recognizer: recognizer, cutter: cutter, quality: quality, stripLocation: stripLocation,
            folders: OutputFolders(promisedDirectory: promised)
        )
    }

    func names(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    func png(_ name: String = "ảnh.png", _ width: Int = 200, _ height: Int = 100, in folder: URL) throws -> URL {
        try SyntheticFiles.write(SyntheticFiles.image(width: width, height: height), as: .png, named: name, in: folder)
    }

    // MARK: Convert

    @Test(arguments: [(ImageFormat.jpeg, "jpg"), (.tiff, "tiff")])
    func convertsAPNGNextToItWithTheNewExtension(format: ImageFormat, ext: String) async throws {
        let folder = try makeTempDirectory()
        let source = try png(in: folder)
        let output = try await processor().process(.convert(format), source: source)
        let file = try #require(output.files.first)
        #expect(output.files.count == 1 && file.deletingLastPathComponent() == folder)
        #expect(file.lastPathComponent == "ảnh.\(ext)")
        #expect(try SyntheticFiles.type(of: file) == format.utType)
        #expect(try names(in: folder) == ["ảnh.\(ext)", "ảnh.png"].sorted())
        #expect(try SyntheticFiles.decoded(file).width == 200)
    }

    @Test func convertsBetweenAllFormatsAndBack() async throws {
        let folder = try makeTempDirectory()
        var current = try png(in: folder)
        for format in ImageCodecTests.lossyFormats + [.tiff, .png] {
            let output = try await processor().process(.convert(format), source: current)
            current = try #require(output.files.first)
            #expect(try SyntheticFiles.type(of: current) == format.utType)
        }
    }

    @Test func anImageAlreadyInTheFormatIsRefused() async throws {
        let folder = try makeTempDirectory()
        let source = try png(in: folder)
        await #expect(throws: FileActionError.alreadyFormat(.png)) { try await processor().process(.convert(.png), source: source) }
        #expect(try names(in: folder) == ["ảnh.png"])
    }

    @Test func conversionKeepsASidewaysPhotoUpright() async throws {
        let folder = try makeTempDirectory()
        let source = try SyntheticFiles.write(SyntheticFiles.image(width: 200, height: 100), as: .jpeg, named: "đứng.jpg", in: folder, properties: [kCGImagePropertyOrientation: 6])
        let file = try #require(try await processor().process(.convert(.png), source: source).files.first)
        let image = try SyntheticFiles.decoded(file)
        #expect(image.width == 100 && image.height == 200)
        #expect(SyntheticFiles.pixel(of: image, x: 50, y: 10).r > 200)
    }

    // MARK: Resize

    @Test(arguments: [(ResizePreset.side1280, "1280", 1280, 640), (.side800, "800", 800, 400), (.half, "50%", 1000, 500)])
    func shrinksTheLongestSideKeepingTheShapeAndTheFormat(preset: ResizePreset, suffix: String, width: Int, height: Int) async throws {
        let folder = try makeTempDirectory()
        let source = try SyntheticFiles.write(SyntheticFiles.image(width: 2000, height: 1000), as: .jpeg, named: "ảnh.jpg", in: folder)
        let file = try #require(try await processor().process(.resize(preset), source: source).files.first)
        #expect(file.lastPathComponent == "ảnh-\(suffix).jpg")
        #expect(try SyntheticFiles.type(of: file) == .jpeg)
        let image = try SyntheticFiles.decoded(file)
        #expect(image.width == width && image.height == height)
    }

    @Test func aPortraitImageIsLimitedOnItsHeight() async throws {
        let folder = try makeTempDirectory()
        let source = try png("dọc.png", 1000, 2000, in: folder)
        let image = try SyntheticFiles.decoded(try #require(try await processor().process(.resize(.side800), source: source).files.first))
        #expect(image.width == 400 && image.height == 800)
    }

    @Test func aSidewaysPhotoIsShrunkByItsShownSizeAndWrittenUpright() async throws {
        let folder = try makeTempDirectory()
        // Stored 2000 x 1000, shown 1000 x 2000.
        let source = try SyntheticFiles.write(SyntheticFiles.image(width: 2000, height: 1000), as: .jpeg, named: "đứng.jpg", in: folder, properties: [kCGImagePropertyOrientation: 6])
        let file = try #require(try await processor().process(.resize(.side800), source: source).files.first)
        let image = try SyntheticFiles.decoded(file)
        #expect(image.width == 400 && image.height == 800)
        #expect(SyntheticFiles.pixel(of: image, x: 200, y: 20).r > 200)
        #expect(SyntheticFiles.pixel(of: image, x: 200, y: 780).b > 200)
        #expect((try SyntheticFiles.properties(of: file)[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
    }

    @Test func anImageThatIsAlreadySmallerIsRefusedInsteadOfEnlarged() async throws {
        let folder = try makeTempDirectory()
        let source = try png(in: folder)
        await #expect(throws: FileActionError.notSmaller) { try await processor().process(.resize(.side800), source: source) }
        await #expect(throws: FileActionError.notSmaller) { try await processor().process(.resize(.side1920), source: source) }
        #expect(try names(in: folder) == ["ảnh.png"])
    }

    @Test func theLocationIsStrippedByDefault() async throws {
        let folder = try makeTempDirectory()
        let source = try SyntheticFiles.write(
            SyntheticFiles.image(width: 2000, height: 1000), as: .jpeg, named: "gps.jpg", in: folder, properties: [kCGImagePropertyGPSDictionary: SyntheticFiles.gps]
        )
        let stripped = try #require(try await processor().process(.resize(.side800), source: source).files.first)
        #expect(try SyntheticFiles.properties(of: stripped)[kCGImagePropertyGPSDictionary] == nil)
        let kept = try #require(try await processor(stripLocation: false).process(.resize(.side800), source: source).files.first)
        #expect(try SyntheticFiles.properties(of: kept)[kCGImagePropertyGPSDictionary] != nil)
        #expect(kept.lastPathComponent == "gps-800 2.jpg")
    }

    @Test func aPNGStaysAPNGWithItsTransparency() async throws {
        let folder = try makeTempDirectory()
        let source = try SyntheticFiles.write(SyntheticFiles.image(width: 1600, height: 1600, alpha: true), as: .png, named: "trong.png", in: folder)
        let file = try #require(try await processor().process(.resize(.side800), source: source).files.first)
        #expect(file.lastPathComponent == "trong-800.png")
        #expect(SyntheticFiles.pixel(of: try SyntheticFiles.decoded(file), x: 600, y: 100).a == 0)
    }

    @Test func aFormatTheShelfCannotWriteComesOutAsPNG() async throws {
        let folder = try makeTempDirectory()
        let source = try SyntheticFiles.write(SyntheticFiles.image(width: 1600, height: 800), as: .gif, named: "động.gif", in: folder)
        let file = try #require(try await processor().process(.resize(.side800), source: source).files.first)
        #expect(file.lastPathComponent == "động-800.png")
        #expect(try SyntheticFiles.type(of: file) == .png)
    }

    @Test(.enabled(if: ImageCodecTests.canWriteHEIC))
    func aHEICStaysAHEIC() async throws {
        let folder = try makeTempDirectory()
        let source = try SyntheticFiles.write(SyntheticFiles.image(width: 1600, height: 800), as: .heic, named: "ảnh.heic", in: folder)
        let file = try #require(try await processor().process(.resize(.side800), source: source).files.first)
        #expect(file.lastPathComponent == "ảnh-800.heic")
        #expect(try SyntheticFiles.type(of: file) == .heic)
    }

    @Test func resultsNeverReplaceEachOther() async throws {
        let folder = try makeTempDirectory()
        let source = try png("a.png", 2000, 1000, in: folder)
        var made: [String] = []
        for _ in 0..<3 { made.append(try await processor().process(.resize(.side800), source: source).files[0].lastPathComponent) }
        #expect(made == ["a-800.png", "a-800 2.png", "a-800 3.png"])
    }

    // MARK: Compress

    @Test func compressesToJPEGAtTheQualitySetting() async throws {
        let folder = try makeTempDirectory()
        let source = try SyntheticFiles.write(ImageCodecTests.noisyImage(), as: .png, named: "ồn.png", in: folder)
        let low = try #require(try await processor(quality: 0.2).process(.compressImage(.jpeg), source: source).files.first)
        let high = try #require(try await processor(quality: 0.95).process(.compressImage(.jpeg), source: source).files.first)
        #expect(low.lastPathComponent == "ồn-nén.jpg" && high.lastPathComponent == "ồn-nén 2.jpg")
        #expect(try SyntheticFiles.type(of: low) == .jpeg)
        let size = { (url: URL) in (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        #expect(size(low) < size(high))
        #expect(size(low) < size(source))
    }

    @Test(.enabled(if: ImageCodecTests.canWriteHEIC))
    func compressesToHEIC() async throws {
        let folder = try makeTempDirectory()
        let source = try SyntheticFiles.write(ImageCodecTests.noisyImage(), as: .png, named: "ồn.png", in: folder)
        let file = try #require(try await processor().process(.compressImage(.heic), source: source).files.first)
        #expect(file.lastPathComponent == "ồn-nén.heic")
        #expect(try SyntheticFiles.type(of: file) == .heic)
    }

    // MARK: Cut out

    @Test func cutsOutToAPNGWithTransparency() async throws {
        let folder = try makeTempDirectory()
        let source = try SyntheticFiles.write(SyntheticFiles.image(width: 100, height: 60), as: .jpeg, named: "ảnh.jpg", in: folder)
        let cutter = FakeCutter()
        let file = try #require(try await processor(cutter: cutter).process(.cutOut, source: source).files.first)
        #expect(file.lastPathComponent == "ảnh-không-nền.png")
        #expect(cutter.calls == 1)
        let image = try SyntheticFiles.decoded(file)
        #expect(SyntheticFiles.pixel(of: image, x: 10, y: 10).a == 0)
        #expect(SyntheticFiles.pixel(of: image, x: 90, y: 10).a == 255)
    }

    @Test func aPictureWithNoSubjectIsReportedAndLeavesNothing() async throws {
        let folder = try makeTempDirectory()
        let source = try png(in: folder)
        let cutter = FakeCutter { _ in throw FileActionError.noSubject }
        await #expect(throws: FileActionError.noSubject) { try await processor(cutter: cutter).process(.cutOut, source: source) }
        #expect(try names(in: folder) == ["ảnh.png"])
    }

    @Test func aCutterThatFailsForAnotherReasonIsReportedAsFailing() async throws {
        let folder = try makeTempDirectory()
        let source = try png(in: folder)
        struct Broken: Error {}
        await #expect(throws: FileActionError.cutOutFailed) { try await processor(cutter: FakeCutter { _ in throw Broken() }).process(.cutOut, source: source) }
    }

    // MARK: Read text

    @Test func readsTextInVietnameseAndEnglishAndTrimsIt() async throws {
        let folder = try makeTempDirectory()
        let source = try png(in: folder)
        let recognizer = FakeRecognizer { _ in "\n  Xin chào\nHello  \n" }
        let output = try await processor(recognizer: recognizer).process(.readText, source: source)
        #expect(output.text == "Xin chào\nHello")
        #expect(output.files.isEmpty)
        #expect(recognizer.requests.map(\.languages) == [["vi-VN", "en-US"]])
        #expect(try names(in: folder) == ["ảnh.png"])
    }

    @Test func aSidewaysPhotoIsReadUpright() async throws {
        let folder = try makeTempDirectory()
        let source = try SyntheticFiles.write(SyntheticFiles.image(width: 300, height: 100), as: .jpeg, named: "đứng.jpg", in: folder, properties: [kCGImagePropertyOrientation: 6])
        let recognizer = FakeRecognizer()
        _ = try await processor(recognizer: recognizer).process(.readText, source: source)
        #expect(recognizer.requests.map(\.width) == [100])
    }

    @Test func aPictureWithoutTextIsReported() async throws {
        let folder = try makeTempDirectory()
        let source = try png(in: folder)
        await #expect(throws: FileActionError.noText) { try await processor(recognizer: FakeRecognizer { _ in " \n " }).process(.readText, source: source) }
    }

    @Test func aRecognizerThatFailsIsReportedAsFailing() async throws {
        let folder = try makeTempDirectory()
        let source = try png(in: folder)
        struct Broken: Error {}
        await #expect(throws: FileActionError.recognitionFailed) { try await processor(recognizer: FakeRecognizer { _ in throw Broken() }).process(.readText, source: source) }
    }

    // MARK: Errors

    @Test(arguments: [FileAction.convert(.jpeg), .resize(.side800), .compressImage(.jpeg), .cutOut, .readText])
    func aFileThatIsNotAnImageIsRefusedByEveryImageAction(action: FileAction) async throws {
        let folder = try makeTempDirectory()
        let text = try makeTempFile(in: folder)
        let corrupt = folder.appending(path: "hỏng.png")
        try Data("not a png".utf8).write(to: corrupt)
        await #expect(throws: FileActionError.notAnImage) { try await processor().process(action, source: text) }
        await #expect(throws: FileActionError.notAnImage) { try await processor().process(action, source: corrupt) }
        await #expect(throws: FileActionError.notAnImage) { try await processor().process(action, source: folder) }
        #expect(try names(in: folder) == ["hỏng.png", "note.txt"])
    }

    @Test func aFileThatIsGoneOrCannotBeReadIsToldApart() async throws {
        let folder = try makeTempDirectory()
        await #expect(throws: FileActionError.missing) { try await processor().process(.convert(.jpeg), source: folder.appending(path: "mất.png")) }
        let locked = try png("khoá.png", in: folder)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }
        await #expect(throws: FileActionError.unreadable) { try await processor().process(.convert(.jpeg), source: locked) }
    }

    @Test func aFolderThatCannotBeWrittenToIsReportedAndKeepsTheSource() async throws {
        let folder = try makeTempDirectory()
        let source = try png("a.png", 2000, 1000, in: folder)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        await #expect(throws: FileActionError.cannotWrite) { try await processor().process(.resize(.side800), source: source) }
        #expect(exists(source))
    }

    @Test func aCancelledTaskWritesNothing() async throws {
        let folder = try makeTempDirectory()
        let source = try png("a.png", 2000, 1000, in: folder)
        let worker = processor()
        let task = Task { () async throws -> FileActionProcessor.Output in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await worker.process(.resize(.side800), source: source)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try names(in: folder) == ["a.png"])
    }

    @Test func aResultForAPromisedCopyGoesInAFolderOfItsOwn() async throws {
        let promised = try makeTempDirectory().appending(path: "promised", directoryHint: .isDirectory)
        let own = promised.appending(path: "X", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
        let source = try png("a.png", 2000, 1000, in: own)
        let file = try #require(try await processor(promised: promised).process(.resize(.side800), source: source).files.first)
        #expect(file.deletingLastPathComponent() != own)
        #expect(file.deletingLastPathComponent().deletingLastPathComponent().resolvingSymlinksInPath() == promised.resolvingSymlinksInPath())
        #expect(exists(file))
    }

    // MARK: PDF

    @Test func splitsAPDFIntoImages() async throws {
        let folder = try makeTempDirectory()
        let pdf = try SyntheticFiles.pdf(pages: 2, in: folder)
        let output = try await processor().process(.pdfToImages, source: pdf)
        #expect(output.files.map(\.lastPathComponent) == ["tài liệu-trang-1.png", "tài liệu-trang-2.png"])
    }

    @Test func mergesImagesIntoOnePDFAndReportsTheOnesItSkipped() async throws {
        let folder = try makeTempDirectory()
        let one = try png("một.png", in: folder)
        let bad = try makeTempFile(named: "hỏng.png", in: folder)
        let combined = try await processor().combine(.imagesToPDF, sources: [one, bad])
        #expect(combined.files.map(\.lastPathComponent) == ["một.pdf"])
        #expect(combined.skipped.map(\.source) == [bad] && combined.skipped.map(\.error) == [.notAnImage])
    }

    // MARK: Zip

    @Test func zipsEverythingThatIsThereAndReportsWhatIsNot() async throws {
        let folder = try makeTempDirectory()
        let one = try makeTempFile(named: "a.txt", in: folder)
        let gone = folder.appending(path: "mất.txt")
        let combined = try await processor().combine(.zip, sources: [one, gone])
        #expect(combined.files.map(\.lastPathComponent) == ["a.zip"])
        #expect(combined.skipped.map(\.source) == [gone] && combined.skipped.map(\.error) == [.missing])
        #expect(try SyntheticFiles.zipEntries(combined.files[0]).map(\.precomposedStringWithCanonicalMapping).filter { !$0.hasSuffix("/") } == ["a/a.txt"])
    }

    @Test func zipsAnyFileNotJustImages() async throws {
        let folder = try makeTempDirectory()
        let pdf = try SyntheticFiles.pdf(pages: 1, in: folder)
        let combined = try await processor().combine(.zip, sources: [pdf, folder.appending(path: "gone")])
        #expect(combined.files.count == 1)
    }

    @Test func withNothingThereZipFails() async throws {
        let folder = try makeTempDirectory()
        await #expect(throws: FileActionError.missing) { try await processor().combine(.zip, sources: [folder.appending(path: "gone")]) }
    }
}
