import AppKit
import Foundation
import Testing
@testable import ClipboardModule

@Suite(.serialized) struct ClipboardCardTextTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func timesUnderAMinuteReadAsJustNow() {
        #expect(ClipboardCardText.relativeTime(now.addingTimeInterval(-59), now: now) == "Vừa xong")
        // A clock moved back must not show a time in the future.
        #expect(ClipboardCardText.relativeTime(now.addingTimeInterval(30), now: now) == "Vừa xong")
    }

    @Test func olderTimesReadInVietnamese() {
        #expect(ClipboardCardText.relativeTime(now.addingTimeInterval(-120), now: now) == "2 phút trước")
        #expect(ClipboardCardText.relativeTime(now.addingTimeInterval(-3 * 3600), now: now) == "3 giờ trước")
    }

    @Test func linksShowTheirHostAndPath() {
        let page = ClipboardCardText.link(URL(string: "https://www.apple.com/vn/iphone?ref=ad")!)
        #expect(page.title == "www.apple.com")
        #expect(page.detail == "/vn/iphone?ref=ad")
        let site = ClipboardCardText.link(URL(string: "https://example.com/")!)
        #expect(site.title == "example.com")
        #expect(site.detail == nil)
        let mail = ClipboardCardText.link(URL(string: "mailto:ryan%2Bnotch@example.com")!)
        #expect(mail.title == "ryan+notch@example.com")
        #expect(mail.detail == nil)
    }

    @Test func filesShowTheFirstNameAndHowManyMore() {
        let one = ClipboardCardText.files([URL(fileURLWithPath: "/Users/me/Báo cáo quý.pdf")])
        #expect(one.title == "Báo cáo quý.pdf")
        #expect(one.detail == nil)
        let three = ClipboardCardText.files([URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b"), URL(fileURLWithPath: "/tmp/c")])
        #expect(three.title == "a.txt")
        #expect(three.detail == "và 2 file khác")
    }

    @Test func aColorCardReadsAsTheTextThatWasCopied() {
        #expect(ClipboardCardText.summary(of: .color(hex: "#FF8800")) == "#FF8800")
        #expect(ClipboardCardText.summary(of: .color(hex: "#FF8800", original: "rgb(255, 136, 0)")) == "rgb(255, 136, 0)")
    }

    @Test func colorsParseWithAndWithoutAlpha() throws {
        let orange = try #require(ClipboardCardText.colorComponents(hex: "#FF8800"))
        #expect(orange.red == 1 && orange.green == 0x88 / 255.0 && orange.blue == 0 && orange.alpha == 1)
        let translucent = try #require(ClipboardCardText.colorComponents(hex: "#00000080"))
        #expect(translucent.alpha == 0x80 / 255.0)
        #expect(ClipboardCardText.colorComponents(hex: "#XYZ") == nil)
        #expect(ClipboardCardText.colorComponents(hex: "FF8800") == nil)
    }

    @Test func longTextIsCutForThePreview() {
        let long = String(repeating: "a", count: 10_000)
        #expect(ClipboardCardText.preview(of: long).count == ClipboardCardText.previewCharacters)
        #expect(ClipboardCardText.preview(of: "\n\n  Xin chào\nthế giới") == "Xin chào\nthế giới")
    }

    @Test func cardsReadAsKindContentTimeAndPin() {
        func item(_ content: ClipboardContent) -> ClipboardItem {
            ClipboardItem(
                id: UUID(), content: content, contentHash: "", copiedAt: now.addingTimeInterval(-120),
                sourceBundleID: nil, sourceAppName: nil
            )
        }
        #expect(ClipboardCardText.accessibilityLabel(for: item(.text("\n  Xin chào\nthế giới")), isPinned: true, now: now)
            == "Văn bản, Xin chào thế giới, 2 phút trước, đã ghim")
        let image = ClipboardImage(fileName: "a.png", pixelWidth: 1920, pixelHeight: 1080, byteCount: 1)
        #expect(ClipboardCardText.accessibilityLabel(for: item(.image(image)), isPinned: false, now: now)
            == "Ảnh, 1920 × 1080, 2 phút trước")
        #expect(ClipboardCardText.accessibilityLabel(for: item(.link(URL(string: "https://example.com/a")!)), isPinned: false, now: now)
            == "Link, example.com /a, 2 phút trước")
    }

    @Test func thePreviewPaneCutsLongerThanACard() {
        let long = String(repeating: "a", count: 10_000)
        #expect(ClipboardCardText.preview(of: long, limit: 1_500).count == 1_500)
        #expect(ClipboardCardText.preview(of: "  Xin chào", limit: 3) == "Xin")
    }

    @Test func aCodePreviewStartsAtTheFirstLineWithSomethingInItSoItsIndentationSurvives() {
        #expect(ClipboardCardText.codePreview(of: "\n\n    let a = 1\n    let b = 2") == "    let a = 1\n    let b = 2")
        #expect(ClipboardCardText.codePreview(of: "   \n\t\r\nx = 1") == "x = 1")
        #expect(ClipboardCardText.codePreview(of: "  x = 1") == "  x = 1")
        #expect(ClipboardCardText.codePreview(of: "") == "")
        #expect(ClipboardCardText.codePreview(of: " \n  \n") == "")
    }

    @Test func aCodePreviewShowsTabsAsFourSpacesAndIsCutAtTheLimit() {
        #expect(ClipboardCardText.codePreview(of: "\tfoo()\n\t\tbar()") == "    foo()\n        bar()")
        #expect(ClipboardCardText.codePreview(of: String(repeating: "a", count: 10_000)).count == ClipboardCardText.previewCharacters)
        #expect(ClipboardCardText.codePreview(of: String(repeating: "a", count: 10_000), limit: 1_500).count == 1_500)
    }

    @Test func aCodeCardReadsAsCodeAndItsLanguage() {
        func item(_ detection: CodeDetection?) -> ClipboardItem {
            ClipboardItem(
                id: UUID(), content: .text("let x = 1"), contentHash: "", copiedAt: now.addingTimeInterval(-120),
                sourceBundleID: nil, sourceAppName: nil, codeDetection: detection
            )
        }
        #expect(ClipboardCardText.accessibilityLabel(for: item(.code(.swift)), isPinned: false, now: now)
            == "Mã Swift, let x = 1, 2 phút trước")
        #expect(ClipboardCardText.accessibilityLabel(for: item(.code(.generic)), isPinned: false, now: now)
            == "Mã, let x = 1, 2 phút trước")
        #expect(ClipboardCardText.accessibilityLabel(for: item(.notCode), isPinned: false, now: now)
            == "Văn bản, let x = 1, 2 phút trước")
        #expect(ClipboardCardText.accessibilityLabel(for: item(nil), isPinned: false, now: now)
            == "Văn bản, let x = 1, 2 phút trước")
    }

    @Test func rowsNameAnImageBySizeAndOtherContentBySummary() {
        let image = ClipboardImage(fileName: "a.png", pixelWidth: 1920, pixelHeight: 1080, byteCount: 1)
        #expect(ClipboardCardText.rowTitle(of: .image(image)) == "Ảnh 1920 × 1080")
        #expect(ClipboardCardText.rowTitle(of: .text("\n Xin chào\nthế giới")) == "Xin chào thế giới")
        #expect(ClipboardCardText.rowTitle(of: .color(hex: "#FF8800", original: "rgb(255, 136, 0)")) == "rgb(255, 136, 0)")
    }

    @Test func cachedAppAndFileIconsArePreRasterizedAndDoNotAllocateWhenDrawnAtCardSizes() throws {
        let icon = try #require(ClipboardIcons.app(bundleID: "com.apple.finder"))
        let unique = UUID().uuidString
        let missingURL = URL(fileURLWithPath: "/tmp/nonexistent-clipboard-test-\(unique)-a.pdf")
        let fileIcon = ClipboardIcons.file(missingURL)

        let iconRep = try #require(icon.representations.first)
        #expect(icon.representations.count == 1)
        #expect(iconRep.pixelsWide == 64)
        #expect(!NSStringFromClass(type(of: iconRep)).contains("ISIcon"))

        let fileRep = try #require(fileIcon.representations.first)
        #expect(fileIcon.representations.count == 1)
        #expect(fileRep.pixelsWide == 96)
        #expect(!NSStringFromClass(type(of: fileRep)).contains("ISIcon"))

        _ = icon.cgImage(forProposedRect: nil, context: nil, hints: nil)
        _ = fileIcon.cgImage(forProposedRect: nil, context: nil, hints: nil)

        let lookupReport = AllocationMeter.measure {
            var i = 0
            while i < 50 {
                _ = ClipboardIcons.app(bundleID: "com.apple.finder")
                _ = ClipboardIcons.file(missingURL)
                i += 1
            }
        }
        #expect(lookupReport.allocations == 0)

        let drawReport = AllocationMeter.measure(attribution: true) {
            var i = 0
            while i < 50 {
                var r14 = NSRect(x: 0, y: 0, width: 14, height: 14)
                _ = icon.cgImage(forProposedRect: &r14, context: nil, hints: nil)
                var r16 = NSRect(x: 0, y: 0, width: 16, height: 16)
                _ = fileIcon.cgImage(forProposedRect: &r16, context: nil, hints: nil)
                var r28 = NSRect(x: 0, y: 0, width: 28, height: 28)
                _ = fileIcon.cgImage(forProposedRect: &r28, context: nil, hints: nil)
                var r40 = NSRect(x: 0, y: 0, width: 40, height: 40)
                _ = icon.cgImage(forProposedRect: &r40, context: nil, hints: nil)
                i += 1
            }
        }
        #expect(AllocationMeter.categoryTotals(of: drawReport).first(where: { $0.name == "app and file icons" }) == nil)
        #expect(drawReport.allocatedBytes < 250_000)

        let missingOne = ClipboardIcons.file(URL(fileURLWithPath: "/tmp/missing-\(unique)-1.pdf"))
        let missingTwo = ClipboardIcons.file(URL(fileURLWithPath: "/tmp/missing-\(unique)-2.pdf"))
        #expect(missingOne === missingTwo)
    }

    @Test func libraryModelReusesFormattedLabelsWithinTheSameMinuteAndInvalidatesWhenPinContentOrMinuteChanges() throws {
        let t0 = now
        let copiedAt = t0.addingTimeInterval(-120)
        var currentNow = t0

        var history = ClipboardHistory()
        let content = ClipboardContent.text("Xin chào\nthế giới")
        let addedID = history.add(
            content, hash: ClipboardContent.hash(of: content),
            source: ("com.apple.Notes", "Ghi chú"), at: copiedAt
        ).id
        let boardID = history.createBoard(name: "Công việc")

        let state = ClipboardState()
        state.history = history
        let model = ClipboardLibraryModel(state: state, actions: FakeLibraryActions(state: state), now: { currentNow })
        let added = try #require(model.items.first(where: { $0.id == addedID }))

        #expect(model.timeLabel(for: added) == "2 phút trước")
        #expect(model.accessibilityLabel(for: added).contains("2 phút trước"))

        // Still inside the same 60-second minute bucket: repeated card/row draws reuse cached strings with 0 allocations.
        currentNow = t0.addingTimeInterval(15)
        let report = AllocationMeter.measure {
            var i = 0
            while i < 100 {
                _ = model.timeLabel(for: added)
                _ = model.accessibilityLabel(for: added)
                i += 1
            }
        }
        #expect(report.allocations == 0)

        // Pin change invalidates cached accessibility label immediately.
        state.history.pin(itemID: added.id, to: boardID)
        let pinnedItem = try #require(model.items.first(where: { $0.id == added.id }))
        #expect(model.accessibilityLabel(for: pinnedItem).hasSuffix(", đã ghim"))

        // Content edit invalidates cached summary inside accessibility label.
        _ = state.history.applyEdit(to: added.id, content: .text("Nội dung đã sửa"), mode: .replace, at: copiedAt)
        let editedItem = try #require(model.items.first(where: { $0.id == added.id }))
        #expect(model.accessibilityLabel(for: editedItem).contains("Nội dung đã sửa"))

        // Minute rollover invalidates both timeLabel and accessibilityLabel.
        currentNow = t0.addingTimeInterval(60)
        #expect(model.timeLabel(for: editedItem) == "3 phút trước")
        #expect(model.accessibilityLabel(for: editedItem).contains("3 phút trước"))
    }
}
