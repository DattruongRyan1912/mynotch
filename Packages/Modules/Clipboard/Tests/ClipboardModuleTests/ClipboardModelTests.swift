import Foundation
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import ClipboardModule

/// Registers the `clipboard` id so the harness hands out its settings namespace.
final class ClipboardIDModule: FeatureModule {
    let descriptor = ModuleDescriptor(id: "clipboard", displayName: "Clipboard", systemImage: "doc.on.clipboard", defaultEnabled: false, order: 0)
    func start(_ context: ModuleContext) async throws(ModuleError) {}
    func stop() async {}
    func makeTab() -> NotchTab? { nil }
    func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? { nil }
}

@Suite struct ClipboardModelTests {
    nonisolated static let rtf = Data("{\\rtf1 Bold}".utf8)
    nonisolated static let image = ClipboardImage(fileName: "abc.png", pixelWidth: 2, pixelHeight: 3, byteCount: 120)
    nonisolated static let files = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b c.pdf")]

    nonisolated static let contents: [ClipboardContent] = [
        .text("Xin chào"),
        .richText(plain: "Bold", rtf: rtf),
        .link(URL(string: "https://example.com/path?q=1")!),
        .color(hex: "#FF8800"),
        .image(image),
        .files(files),
    ]

    @Test(arguments: contents)
    func itemsRoundTripThroughJSON(content: ClipboardContent) throws {
        let item = ClipboardItem(
            id: UUID(), content: content, contentHash: ClipboardContent.hash(of: content),
            copiedAt: Date(timeIntervalSinceReferenceDate: 800_000_000), sourceBundleID: "com.apple.Safari", sourceAppName: "Safari"
        )
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: JSONEncoder().encode(item))
        #expect(decoded == item)
    }

    /// Pins the stored shape of every case: renaming a case or a label must not silently orphan saved history.
    @Test func decodesTheStoredJSONOfEveryContent() throws {
        let rtf = Self.rtf.base64EncodedString()
        let json = """
        [
            {"text": {"_0": "Xin chào"}},
            {"richText": {"plain": "Bold", "rtf": "\(rtf)"}},
            {"link": {"_0": "https://example.com/path?q=1"}},
            {"color": {"hex": "#FF8800"}},
            {"image": {"_0": {"fileName": "abc.png", "pixelWidth": 2, "pixelHeight": 3, "byteCount": 120}}},
            {"files": {"_0": ["file:///tmp/a.txt", "file:///tmp/b%20c.pdf"]}}
        ]
        """
        #expect(try JSONDecoder().decode([ClipboardContent].self, from: Data(json.utf8)) == Self.contents)
    }

    @Test func boardsRoundTripThroughJSON() throws {
        let board = ClipboardBoard(id: UUID(), name: "Công việc", systemImage: "tray.full", itemIDs: [UUID(), UUID()])
        #expect(try JSONDecoder().decode(ClipboardBoard.self, from: JSONEncoder().encode(board)) == board)
    }

    @Test func kindGroupsRichTextWithTextAndFilesAsFile() {
        #expect(Self.contents.map(\.kind) == [.text, .text, .link, .color, .image, .file])
        #expect(ClipboardKind.allCases == [.text, .link, .image, .file, .color])
    }

    @Test func plainTextOfEveryContent() {
        #expect(Self.contents.map(\.plainText) == [
            "Xin chào", "Bold", "https://example.com/path?q=1", "#FF8800", nil, "/tmp/a.txt\n/tmp/b c.pdf",
        ])
    }

    @Test func hashIsStableHexSHA256() {
        for content in Self.contents {
            let hash = ClipboardContent.hash(of: content)
            #expect(hash == ClipboardContent.hash(of: content))
            #expect(hash.count == 64 && hash.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        }
        #expect(Set(Self.contents.map(ClipboardContent.hash(of:))).count == Self.contents.count)
    }

    @Test func hashSeparatesKindsWithTheSameString() {
        #expect(ClipboardContent.hash(of: .text("#FFFFFF")) != ClipboardContent.hash(of: .color(hex: "#FFFFFF")))
        #expect(ClipboardContent.hash(of: .text("https://a.com")) != ClipboardContent.hash(of: .link(URL(string: "https://a.com")!)))
        #expect(ClipboardContent.hash(of: .text("/tmp/a.txt")) != ClipboardContent.hash(of: .files([URL(fileURLWithPath: "/tmp/a.txt")])))
        #expect(ClipboardContent.hash(of: .text("a")) != ClipboardContent.hash(of: .text("b")))
    }

    @Test func richTextSharesTheHashOfItsPlainText() {
        #expect(ClipboardContent.hash(of: .richText(plain: "Bold", rtf: Self.rtf)) == ClipboardContent.hash(of: .text("Bold")))
    }

    @Test func imageHashFollowsItsFile() {
        let other = ClipboardImage(fileName: "def.png", pixelWidth: 2, pixelHeight: 3, byteCount: 120)
        #expect(ClipboardContent.hash(of: .image(Self.image)) != ClipboardContent.hash(of: .image(other)))
    }

    @Test func retentionIntervals() {
        let day: TimeInterval = 24 * 60 * 60
        #expect(Retention.allCases.map(\.interval) == [day, 7 * day, 30 * day, 365 * day, nil])
    }

    @Test func settingKeysUseTheClipboardNamespaceAndDefaults() throws {
        let harness = RegistryHarness([ClipboardIDModule()])
        let settings = try #require(harness.settingsEnvironment(for: "clipboard")).settings
        let keys = ClipboardSettingKeys(settings)
        #expect([
            keys.paused.name, keys.historyLimit.name, keys.retention.name, keys.imageStorageLimitMB.name,
            keys.ignoreSensitive.name, keys.excludedBundleIDs.name, keys.clickAction.name,
            keys.closeAfterAction.name, keys.showCopiedActivity.name, keys.colorsWithoutHash.name,
        ] == [
            "paused", "historyLimit", "retention", "imageStorageLimitMB", "ignoreSensitive",
            "excludedBundleIDs", "clickAction", "closeAfterAction", "showCopiedActivity", "colorsWithoutHash",
        ].map { "module.clipboard.\($0)" })
        #expect(settings.value(keys.paused) == false)
        #expect(settings.value(keys.historyLimit) == 500)
        #expect(settings.value(keys.retention) == .month)
        #expect(settings.value(keys.imageStorageLimitMB) == 250)
        #expect(settings.value(keys.ignoreSensitive) == true)
        #expect(settings.value(keys.excludedBundleIDs) == [])
        #expect(settings.value(keys.clickAction) == .copy)
        #expect(settings.value(keys.closeAfterAction) == true)
        #expect(settings.value(keys.showCopiedActivity) == true)
        #expect(settings.value(keys.colorsWithoutHash) == true)
    }

    @Test func settingKeysClampAndStoreValues() throws {
        let harness = RegistryHarness([ClipboardIDModule()])
        let settings = try #require(harness.settingsEnvironment(for: "clipboard")).settings
        let keys = ClipboardSettingKeys(settings)
        settings.set(10, for: keys.historyLimit)
        #expect(settings.value(keys.historyLimit) == 50)
        settings.set(9000, for: keys.historyLimit)
        #expect(settings.value(keys.historyLimit) == 5000)
        settings.set(10, for: keys.imageStorageLimitMB)
        #expect(settings.value(keys.imageStorageLimitMB) == 50)
        settings.set(3000, for: keys.imageStorageLimitMB)
        #expect(settings.value(keys.imageStorageLimitMB) == 2000)
        settings.set(.forever, for: keys.retention)
        #expect(settings.value(keys.retention) == .forever)
        settings.set(.paste, for: keys.clickAction)
        #expect(settings.value(keys.clickAction) == .paste)
        settings.set(["com.agilebits.onepassword7"], for: keys.excludedBundleIDs)
        #expect(settings.value(keys.excludedBundleIDs) == ["com.agilebits.onepassword7"])
    }
}
