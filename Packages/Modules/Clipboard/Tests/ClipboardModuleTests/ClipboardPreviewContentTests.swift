import Foundation
import Testing
@testable import ClipboardModule

/// What the preview shows for each kind of item, as values: no view, no window, no disk. The colour values, the link's
/// parts, the picture's size, the text's bound and the facts about files are all decided here.
@Suite struct ClipboardPreviewContentTests {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    static func item(_ content: ClipboardContent, code: CodeLanguage? = nil) -> ClipboardItem {
        ClipboardItem(
            id: UUID(), content: content, contentHash: ClipboardContent.hash(of: content), copiedAt: start,
            sourceBundleID: nil, sourceAppName: nil, codeDetection: code.map { .code($0) } ?? .notCode
        )
    }

    static func content(_ content: ClipboardContent, code: CodeLanguage? = nil, facts: ClipboardFileFacts = .none) -> ClipboardPreviewContent {
        ClipboardPreviewContent(item: item(content, code: code), facts: facts)
    }

    // MARK: Text

    @Test func aTextIsShownWholeWhenItFits() {
        guard case .text(let text) = Self.content(.text("Xin chào\ncả nhà")) else { Issue.record("not text"); return }
        #expect(text.text == "Xin chào\ncả nhà")
        #expect(!text.isTruncated)
        #expect(text.language == nil)
        #expect(text.byteCount == "Xin chào\ncả nhà".utf8.count)
    }

    @Test func aRichTextShowsItsPlainWords() {
        guard case .text(let text) = Self.content(.richText(plain: "Bảng giá", rtf: Data("{\\rtf1 x}".utf8))) else { Issue.record("not text"); return }
        #expect(text.text == "Bảng giá")
    }

    @Test func codeCarriesItsLanguageForTheHighlighting() {
        guard case .text(let text) = Self.content(.text("let x = 1"), code: .swift) else { Issue.record("not text"); return }
        #expect(text.language == .swift)
    }

    @Test func aHugeTextIsCutAtTheBoundBetweenCharactersAndSaysSo() {
        let limit = ClipboardPreviewText.characterLimit
        let long = String(repeating: "é", count: limit + 50)
        guard case .text(let text) = Self.content(.text(long)) else { Issue.record("not text"); return }
        #expect(text.text.count == limit)
        #expect(text.isTruncated)
        // The size is the whole text's, not the cut one's.
        #expect(text.byteCount == long.utf8.count)
    }

    @Test func aTextExactlyAtTheBoundIsNotCut() {
        let limit = ClipboardPreviewText.characterLimit
        guard case .text(let text) = Self.content(.text(String(repeating: "a", count: limit))) else { Issue.record("not text"); return }
        #expect(text.text.count == limit)
        #expect(!text.isTruncated)
    }

    @Test func aCutNeverSplitsACharacterMadeOfSeveralScalars() {
        let flag = "🇻🇳"
        let limit = ClipboardPreviewText.characterLimit
        guard case .text(let text) = Self.content(.text(String(repeating: flag, count: limit + 3))) else { Issue.record("not text"); return }
        #expect(text.text.count == limit)
        #expect(text.text.hasSuffix(flag))
    }

    @Test func theCutIsMadeFromTheStartAndKeepsIndentationAndBlankLines() {
        guard case .text(let text) = Self.content(.text("\n\n    indented\n")) else { Issue.record("not text"); return }
        #expect(text.text == "\n\n    indented\n")
    }

    // MARK: Colours

    @Test(arguments: [
        ("#FF8800", "rgb(255, 136, 0)", "hsl(32, 100%, 50%)"),
        ("#000000", "rgb(0, 0, 0)", "hsl(0, 0%, 0%)"),
        ("#FFFFFF", "rgb(255, 255, 255)", "hsl(0, 0%, 100%)"),
        ("#808080", "rgb(128, 128, 128)", "hsl(0, 0%, 50%)"),
        ("#3366CC", "rgb(51, 102, 204)", "hsl(220, 60%, 50%)"),
        ("#FF0000", "rgb(255, 0, 0)", "hsl(0, 100%, 50%)"),
        ("#00FF00", "rgb(0, 255, 0)", "hsl(120, 100%, 50%)"),
        ("#0000FF", "rgb(0, 0, 255)", "hsl(240, 100%, 50%)"),
    ])
    func aColourShowsItsHexRgbAndHsl(hex: String, rgb: String, hsl: String) throws {
        let values = try #require(ClipboardColorValues(hex: hex, original: nil))
        #expect(values.hex == hex)
        #expect(values.rgb == rgb)
        #expect(values.hsl == hsl)
    }

    @Test func aTranslucentColourShowsItsAlphaInAllThree() throws {
        let values = try #require(ClipboardColorValues(hex: "#FF880080", original: nil))
        #expect(values.hex == "#FF880080")
        #expect(values.rgb == "rgba(255, 136, 0, 0.5)")
        #expect(values.hsl == "hsla(32, 100%, 50%, 0.5)")
        #expect(values.alpha > 0.49 && values.alpha < 0.51)
    }

    @Test func anAlphaIsShownWithAtMostTwoDecimals() throws {
        #expect(try #require(ClipboardColorValues(hex: "#00000033", original: nil)).rgb == "rgba(0, 0, 0, 0.2)")
        #expect(try #require(ClipboardColorValues(hex: "#00000000", original: nil)).rgb == "rgba(0, 0, 0, 0)")
        #expect(try #require(ClipboardColorValues(hex: "#000000F0", original: nil)).rgb == "rgba(0, 0, 0, 0.94)")
    }

    @Test func theRgbTextReadsBackAsTheSameColour() throws {
        for hex in ["#FF8800", "#3366CC", "#123456", "#ABCDEF", "#0A0B0C", "#FF880080"] {
            let values = try #require(ClipboardColorValues(hex: hex, original: nil))
            #expect(ClipboardCSSColor.hex(values.rgb) == hex, "\(hex)")
        }
    }

    @Test func theHslTextReadsBackAsAColourWithinARoundingStepOfTheSame() throws {
        for hex in ["#FF8800", "#3366CC", "#123456", "#ABCDEF", "#0A0B0C"] {
            let values = try #require(ClipboardColorValues(hex: hex, original: nil))
            let back = try #require(ClipboardCSSColor.hex(values.hsl))
            let a = ClipboardCardText.colorComponents(hex: hex)!, b = ClipboardCardText.colorComponents(hex: back)!
            // Whole degrees and percents cannot hold every byte.
            #expect(abs(a.red - b.red) < 0.03 && abs(a.green - b.green) < 0.03 && abs(a.blue - b.blue) < 0.03, "\(hex) -> \(back)")
        }
    }

    @Test func aColourCopiedAsAFunctionKeepsTheWordsItWasCopiedAs() throws {
        guard case .color(let values) = Self.content(.color(hex: "#FF8800", original: "hsl(32, 100%, 50%)")) else { Issue.record("not a colour"); return }
        #expect(values.original == "hsl(32, 100%, 50%)")
        #expect(values.hex == "#FF8800")
        guard case .color(let plain) = Self.content(.color(hex: "#FF8800")) else { Issue.record("not a colour"); return }
        #expect(plain.original == nil)
    }

    @Test func aHexNobodyCanReadHasNoValues() {
        #expect(ClipboardColorValues(hex: "FF8800", original: nil) == nil)
        #expect(ClipboardColorValues(hex: "#FF88", original: nil) == nil)
        #expect(ClipboardColorValues(hex: "#GG8800", original: nil) == nil)
    }

    // MARK: Links

    @Test func aLinkShowsItsWholeAddressAndItsParts() {
        guard case .link(let link) = Self.content(.link(URL(string: "https://example.com/a/b?q=1#top")!)) else { Issue.record("not a link"); return }
        #expect(link.address == "https://example.com/a/b?q=1#top")
        #expect(link.host == "example.com")
        #expect(link.detail == "/a/b?q=1")
        #expect(link.scheme == "https")
    }

    @Test func aLinkWithNoPathHasNoDetail() {
        guard case .link(let link) = Self.content(.link(URL(string: "https://example.com/")!)) else { Issue.record("not a link"); return }
        #expect(link.host == "example.com")
        #expect(link.detail == nil)
    }

    @Test func aLinkWithoutAHostShowsWhatFollowsTheScheme() {
        guard case .link(let link) = Self.content(.link(URL(string: "mailto:ten@example.com")!)) else { Issue.record("not a link"); return }
        #expect(link.host == "ten@example.com")
        #expect(link.detail == nil)
        #expect(link.address == "mailto:ten@example.com")
    }

    // MARK: Pictures

    @Test func aPictureShowsItsPixelSizeAndItsBytes() {
        let image = ClipboardImage(fileName: "a.png", pixelWidth: 1920, pixelHeight: 1080, byteCount: 1_234_567)
        guard case .image(let info) = Self.content(.image(image)) else { Issue.record("not an image"); return }
        #expect(info.pixelWidth == 1920 && info.pixelHeight == 1080)
        #expect(info.dimensionsText == "1920 × 1080")
        #expect(info.sizeText == ByteCountFormatter.string(fromByteCount: 1_234_567, countStyle: .file))
        #expect(info.fileName == "a.png")
    }

    // MARK: Files

    static let facts = ClipboardFileFacts { url in
        switch url.lastPathComponent {
        case "báo cáo.pdf": .init(isDirectory: false, byteCount: 52_000, kind: "Tài liệu PDF")
        case "ảnh.png": .init(isDirectory: false, byteCount: 900, kind: "Ảnh PNG")
        case "thư mục": .init(isDirectory: true, byteCount: nil, kind: "Thư mục")
        case "Công cụ.app": .init(isDirectory: true, isPackage: true, byteCount: nil, kind: "Ứng dụng")
        default: nil
        }
    }

    @Test func oneExistingFileIsOfferedToQuickLookWithItsFacts() throws {
        let url = URL(fileURLWithPath: "/Users/me/báo cáo.pdf")
        guard case .files(let files) = Self.content(.files([url]), facts: Self.facts) else { Issue.record("not files"); return }
        let entry = try #require(files.entries.first)
        #expect(files.entries.count == 1)
        #expect(entry.name == "báo cáo.pdf")
        #expect(entry.folder == "/Users/me")
        #expect(entry.exists)
        #expect(entry.kind == "Tài liệu PDF")
        #expect(entry.sizeText == ByteCountFormatter.string(fromByteCount: 52_000, countStyle: .file))
        #expect(files.quickLookURL == url)
    }

    @Test func severalFilesAreListedWithoutQuickLook() {
        let urls = ["báo cáo.pdf", "ảnh.png"].map { URL(fileURLWithPath: "/Users/me/\($0)") }
        guard case .files(let files) = Self.content(.files(urls), facts: Self.facts) else { Issue.record("not files"); return }
        #expect(files.entries.map(\.name) == ["báo cáo.pdf", "ảnh.png"])
        #expect(files.quickLookURL == nil)
    }

    @Test func aFileThatIsGoneIsListedAsMissingAndNotOffered() throws {
        let url = URL(fileURLWithPath: "/Users/me/đã xoá.txt")
        guard case .files(let files) = Self.content(.files([url]), facts: Self.facts) else { Issue.record("not files"); return }
        let entry = try #require(files.entries.first)
        #expect(!entry.exists)
        #expect(entry.sizeText == nil)
        #expect(entry.kind == nil)
        #expect(files.quickLookURL == nil)
    }

    @Test func aFolderIsNotOfferedToQuickLookButAPackageIs() {
        let folder = URL(fileURLWithPath: "/Users/me/thư mục", isDirectory: true)
        guard case .files(let asFolder) = Self.content(.files([folder]), facts: Self.facts) else { Issue.record("not files"); return }
        #expect(asFolder.entries.first?.isDirectory == true)
        #expect(asFolder.quickLookURL == nil)

        let package = URL(fileURLWithPath: "/Applications/Công cụ.app", isDirectory: true)
        guard case .files(let asPackage) = Self.content(.files([package]), facts: Self.facts) else { Issue.record("not files"); return }
        #expect(asPackage.quickLookURL == package)
    }

    @Test func aLongListOfFilesIsCutAndSaysHowManyAreLeftOut() {
        let limit = ClipboardPreviewFiles.entryLimit
        let urls = (0..<limit + 7).map { URL(fileURLWithPath: "/tmp/f\($0).txt") }
        guard case .files(let files) = Self.content(.files(urls), facts: Self.facts) else { Issue.record("not files"); return }
        #expect(files.entries.count == limit)
        #expect(files.omittedCount == 7)
    }

    @Test func thePreviewOnlyEverReadsFactsNeverWritesThem() {
        // The facts are a pure question about a URL; the value type has nothing to write with.
        var asked: [String] = []
        let facts = ClipboardFileFacts { url in
            asked.append(url.lastPathComponent)
            return nil
        }
        _ = Self.content(.files([URL(fileURLWithPath: "/tmp/a.txt")]), facts: facts)
        #expect(asked == ["a.txt"])
    }

    // MARK: The system's facts

    @Test func theSystemFactsOfAFileThatIsNotThereAreNil() {
        let missing = URL(fileURLWithPath: "/definitely/not/here-\(UUID().uuidString).txt")
        #expect(ClipboardFileFacts.system.look(missing) == nil)
    }

    /// `/tmp` is a link to `/private/tmp`, and /Applications/Safari.app is one on a current macOS: the facts are of the file it
    /// leads to, not of the link (which is a few dozen bytes of "Alias").
    @Test func aSymbolicLinkIsAskedAboutWhatItLeadsTo() {
        let look = ClipboardFileFacts.system.look(URL(fileURLWithPath: "/tmp"))
        #expect(look?.isDirectory == true)
        #expect(look?.kind != "Alias")
    }

    @Test func aLinkThatLeadsNowhereIsGone() {
        // A dangling link has no file behind it, which is what the preview should say.
        let name = "/private/var/empty/mynotch-preview-test-\(UUID().uuidString)"
        #expect(ClipboardFileFacts.system.look(URL(fileURLWithPath: name)) == nil)
    }

    @Test func theSystemFactsOfAFolderSayItIsOne() {
        let look = ClipboardFileFacts.system.look(URL(fileURLWithPath: "/System", isDirectory: true))
        #expect(look?.isDirectory == true)
        #expect(look?.isPackage == false)
    }
}
