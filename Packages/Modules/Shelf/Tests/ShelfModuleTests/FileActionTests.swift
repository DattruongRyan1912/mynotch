import Foundation
import Testing
import UniformTypeIdentifiers
@testable import ShelfModule

@Suite struct FileActionTests {
    @Test func theRowHasTheSixActionsInOrder() {
        #expect(ShelfActionGroup.allCases.map(\.title) == ["Đổi định dạng", "Đổi kích thước", "Nén", "Tách nền", "Nhận chữ", "PDF"])
    }

    @Test func everyActionIsReachableFromExactlyOneGroup() {
        let all: [FileAction] = ImageFormat.allCases.map(FileAction.convert) + ResizePreset.allCases.map(FileAction.resize)
            + [.compressImage(.jpeg), .compressImage(.heic), .zip, .cutOut, .readText, .imagesToPDF, .pdfToImages]
        for action in all {
            #expect(ShelfActionGroup.allCases.filter { $0.choices.contains { $0.action == action } }.count == 1, "\(action)")
            #expect(ShelfActionGroup.containing(action) != nil)
        }
        #expect(ShelfActionGroup.allCases.flatMap(\.choices).count == all.count)
    }

    @Test func convertOffersTheFourFormatsAndResizeTheFourPresets() {
        #expect(ShelfActionGroup.convert.choices.map(\.title) == ["Sang PNG", "Sang JPEG", "Sang HEIC", "Sang TIFF"])
        #expect(ShelfActionGroup.resize.choices.map(\.title) == ["50 %", "1920 px", "1280 px", "800 px"])
        #expect(ShelfActionGroup.compress.choices.map(\.action) == [.compressImage(.jpeg), .compressImage(.heic), .zip])
    }

    @Test func aDropOnAGroupRunsTheChoiceUsedLastElseTheFirst() {
        #expect(ShelfActionGroup.resize.action(preferred: nil, droppingPDFsOnly: false) == .resize(.half))
        #expect(ShelfActionGroup.resize.action(preferred: .resize(.side800), droppingPDFsOnly: false) == .resize(.side800))
        // A choice that belongs to another group is not a preference of this one.
        #expect(ShelfActionGroup.resize.action(preferred: .convert(.png), droppingPDFsOnly: false) == .resize(.half))
        #expect(ShelfActionGroup.cutOut.action(preferred: nil, droppingPDFsOnly: false) == .cutOut)
    }

    @Test func aDropOnPDFSplitsPDFsAndMergesAnythingElse() {
        #expect(ShelfActionGroup.pdf.action(preferred: nil, droppingPDFsOnly: true) == .pdfToImages)
        #expect(ShelfActionGroup.pdf.action(preferred: .pdfToImages, droppingPDFsOnly: false) == .imagesToPDF)
    }

    @Test func theButtonsTakeFilesAndNotNotesOrLinks() {
        #expect(ShelfActionChip.dropTypes == [.fileURL, .image])
        #expect(!ShelfActionChip.dropTypes.contains(.plainText) && !ShelfActionChip.dropTypes.contains(.url))
    }

    @Test func onlyZipAndPDFMergeTakeTheirSourcesTogether() {
        #expect(FileAction.zip.combinesSources && FileAction.imagesToPDF.combinesSources)
        #expect(![FileAction.cutOut, .readText, .pdfToImages, .convert(.png), .resize(.half), .compressImage(.jpeg)].contains { $0.combinesSources })
    }

    @Test func formatsAreFoundFromTheirTypes() {
        #expect(ImageFormat(.png) == .png && ImageFormat(.jpeg) == .jpeg && ImageFormat(.tiff) == .tiff)
        #expect(ImageFormat(.heic) == .heic && ImageFormat(.heif) == .heic)
        #expect(ImageFormat(.gif) == nil && ImageFormat(.pdf) == nil)
        #expect(ImageFormat.jpeg.fileExtension == "jpg" && ImageFormat.heic.fileExtension == "heic")
        #expect(ImageFormat.allCases.filter(\.isLossy) == [.jpeg, .heic])
    }

    @Test func presetsShrinkAndNeverGoBelowOnePixel() {
        #expect(ResizePreset.half.longestSide(from: 3001) == 1500)
        #expect(ResizePreset.half.longestSide(from: 1) == 1)
        #expect(ResizePreset.side1280.longestSide(from: 4000) == 1280)
    }

    @Test func everyActionHasATitleForTheProgressLine() {
        #expect(FileAction.convert(.jpeg).title == "Đổi sang JPEG")
        #expect(FileAction.resize(.side1280).title == "Đổi kích thước 1280 px")
        #expect(FileAction.zip.title == "Nén thành .zip")
        #expect(FileAction.readText.title == "Nhận chữ")
    }

    @Test func theProgressLineNamesTheFileAndItsPlaceInTheBatch() {
        typealias Progress = FileActionRunner.Progress
        #expect(Progress(action: .cutOut, done: 1, total: 3, current: "b.png").detail == "b.png · 2/3")
        #expect(Progress(action: .cutOut, done: 0, total: 1, current: "a.png").detail == "a.png")
        #expect(Progress(action: .zip, done: 0, total: nil, current: "a.txt").detail == "a.txt")
        #expect(Progress(action: .zip, done: 0, total: nil, current: nil).detail == "")
        #expect(Progress(action: .zip, done: 0, total: nil, current: "a.txt", isCancelling: true).detail == "Đang huỷ…")
    }

    // MARK: The report's summary

    @Test func aReportSaysWhatWasMadeAndWhatFailed() {
        typealias Report = FileActionRunner.Report
        let url = URL(filePath: "/tmp/a.png")
        var report = Report(action: .cutOut, created: [url, url])
        #expect(report.summary == "Đã tạo 2 file")
        report.failures = [.init(name: "x", message: "m")]
        #expect(report.summary == "Đã tạo 2 file · 1 file lỗi")
        #expect(Report(action: .cutOut, failures: [.init(name: "x", message: "m")]).summary == "1 file lỗi")
        #expect(Report(action: .readText, text: "chữ", textCopied: true).summary == "Đã chép 3 ký tự")
        #expect(Report(action: .readText, text: "chữ", textCopied: false).summary == "Đọc được chữ, nhưng không chép được")
        #expect(Report(action: .cutOut, wasCancelled: true).summary == "Đã huỷ")
        #expect(Report(action: .cutOut, created: [url], wasCancelled: true).summary == "Đã huỷ, đã tạo 1 file")
    }

    @Test func aReportSaysWhenResultsStayedOffAFullShelfAndWhere() {
        typealias Report = FileActionRunner.Report
        let folder = URL(filePath: "/tmp/Ảnh", directoryHint: .isDirectory)
        let made = (1...3).map { folder.appending(path: "a\($0).png") }
        var report = Report(action: .resize(.half), created: made, notShelved: made.dropFirst().map { UnshelvedResult(url: $0, reason: .shelfFull) })
        #expect(report.summary == "Đã tạo 3 file · 2 file chưa vào khay")
        #expect(report.shelfNote == "Khay đầy: 2 file nằm trong thư mục Ảnh")
        #expect(report.revealable == Array(made.dropFirst()))
        report.notShelved = []
        #expect(report.shelfNote == nil && report.summary == "Đã tạo 3 file" && report.revealable.isEmpty)
    }

    @Test func eachReasonAResultHasNoCardGetsItsOwnTrueMessage() {
        typealias Report = FileActionRunner.Report
        let folder = URL(filePath: "/tmp/Ảnh", directoryHint: .isDirectory)
        func result(_ name: String, _ reason: UnshelvedResult.Reason) -> UnshelvedResult { UnshelvedResult(url: folder.appending(path: name), reason: reason) }

        // A failed bookmark is not a full shelf.
        let failed = Report(action: .cutOut, notShelved: [result("a.png", .cardFailed)])
        #expect(failed.shelfNote == "1 file không tạo được thẻ trên khay, nằm trong thư mục Ảnh")
        #expect(failed.shelfNote?.contains("đầy") == false)

        let stopped = Report(action: .cutOut, notShelved: [result("a.png", .shelfStopped), result("b.png", .shelfStopped)])
        #expect(stopped.shelfNote == "Khay đã dừng khi đang chạy: 2 file nằm trong thư mục Ảnh")

        // Lost at the next launch, so it says so, and the file is not offered to Finder.
        let stranded = Report(action: .cutOut, notShelved: [result("a.png", .stranded)])
        #expect(stranded.shelfNote == "1 file không chuyển ra được thư mục kết quả, nên còn trong bộ nhớ tạm của MyNotch và sẽ bị xoá khi mở lại app")
        #expect(stranded.revealable.isEmpty)

        let mixed = Report(action: .cutOut, notShelved: [result("a.png", .shelfFull), result("b.png", .cardFailed), result("c.png", .shelfFull)])
        #expect(mixed.shelfNote == "Khay đầy: 2 file nằm trong thư mục Ảnh\n1 file không tạo được thẻ trên khay, nằm trong thư mục Ảnh")
        #expect(mixed.revealable.count == 3)
    }
}
