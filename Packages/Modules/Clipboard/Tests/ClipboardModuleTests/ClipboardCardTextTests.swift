import Foundation
import Testing
@testable import ClipboardModule

@Suite struct ClipboardCardTextTests {
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
}
