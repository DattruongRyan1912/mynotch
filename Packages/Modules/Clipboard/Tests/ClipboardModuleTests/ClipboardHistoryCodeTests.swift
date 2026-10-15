import Foundation
import Testing
@testable import ClipboardModule

/// Code detection as the history stores it: decided once, when an item is added.
@Suite struct ClipboardHistoryCodeTests {
    static let start = ClipboardHistoryTests.start
    static let swiftCode = "let total = items.reduce(0) { $0 + $1.price }\nprint(total)"

    @discardableResult
    func add(_ content: ClipboardContent, to history: inout ClipboardHistory, at offset: TimeInterval = 0) -> UUID {
        ClipboardHistoryTests.add(content, to: &history, at: offset)
    }

    @Test func aCopiedTextIsClassifiedOnceWhenItIsAdded() throws {
        var history = ClipboardHistory()
        let code = add(.text(Self.swiftCode), to: &history, at: 0)
        let prose = add(.text("Hôm nay trời đẹp quá."), to: &history, at: 1)
        let rich = add(.richText(plain: "SELECT id FROM users;", rtf: Data("{\\rtf1 x}".utf8)), to: &history, at: 2)
        func item(_ id: UUID) throws -> ClipboardItem { try #require(history.items.first { $0.id == id }) }
        #expect(try item(code).codeDetection == .code(.swift))
        #expect(try item(code).isCode && item(code).codeLanguage == .swift)
        #expect(try item(prose).codeDetection == .notCode)
        #expect(try !item(prose).isCode && item(prose).codeLanguage == nil)
        #expect(try item(rich).codeDetection == .code(.sql))
    }

    @Test func otherKindsHaveNoDetection() throws {
        var history = ClipboardHistory()
        let link = add(.link(URL(string: "https://example.com")!), to: &history, at: 0)
        let color = add(.color(hex: "#FF8800"), to: &history, at: 1)
        let files = add(.files([URL(fileURLWithPath: "/tmp/a.swift")]), to: &history, at: 2)
        let image = add(ClipboardHistoryTests.image("a", bytes: 1), to: &history, at: 3)
        for id in [link, color, files, image] {
            #expect(try #require(history.items.first { $0.id == id }).codeDetection == nil)
        }
    }

    @Test func copyingTheSameTextAgainKeepsItsDetection() throws {
        var history = ClipboardHistory()
        let id = add(.text(Self.swiftCode), to: &history, at: 0)
        let rtf = Data("{\\rtf1 x}".utf8)
        let result = history.add(
            .richText(plain: Self.swiftCode, rtf: rtf), hash: ClipboardContent.hash(of: .text(Self.swiftCode)),
            source: (bundleID: nil, name: nil), at: Self.start + 5
        )
        #expect(result == .moved(id))
        #expect(history.items[0].codeDetection == .code(.swift))
    }

    @Test func aRepeatedCopyOfAnUnclassifiedItemClassifiesIt() throws {
        let content = ClipboardContent.text(Self.swiftCode)
        var history = ClipboardHistory(items: [
            ClipboardItem(
                id: UUID(), content: content, contentHash: ClipboardContent.hash(of: content), copiedAt: Self.start,
                sourceBundleID: nil, sourceAppName: nil
            ),
        ])
        history.add(content, hash: ClipboardContent.hash(of: content), source: (nil, nil), at: Self.start + 1)
        #expect(history.items[0].codeDetection == .code(.swift))
    }

    // MARK: Items from before code detection

    @Test func classifyingFillsOnlyTheTextsThatHaveNone() throws {
        func legacy(_ content: ClipboardContent, _ detection: CodeDetection? = nil) -> ClipboardItem {
            ClipboardItem(
                id: UUID(), content: content, contentHash: ClipboardContent.hash(of: content), copiedAt: Self.start,
                sourceBundleID: nil, sourceAppName: nil, codeDetection: detection
            )
        }
        var history = ClipboardHistory(items: [
            legacy(.text(Self.swiftCode)), legacy(.text("Xin chào")), legacy(.link(URL(string: "https://example.com")!)),
            // Decided already: not looked at again, even when the text now looks like something else.
            legacy(.text(Self.swiftCode), .notCode),
        ])
        history.classifyUnclassifiedTexts()
        #expect(history.items.map(\.codeDetection) == [.code(.swift), .notCode, nil, .notCode])
        let again = history
        history.classifyUnclassifiedTexts()
        #expect(history == again)
    }

    @Test func aHistorySavedBeforeDetectionStillLoads() throws {
        let json = """
        {"items": [{"id": "00000000-0000-0000-0000-000000000001", "content": {"text": {"_0": "Xin chào"}},
        "contentHash": "h", "copiedAt": 800000000}], "boards": []}
        """
        let history = try JSONDecoder().decode(ClipboardHistory.self, from: Data(json.utf8))
        #expect(history.items.count == 1)
        #expect(history.items[0].codeDetection == nil)
    }

    @Test func theDetectionIsStoredAsOneReadableWord() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        func encoded(_ detection: CodeDetection) throws -> String {
            String(decoding: try encoder.encode([detection]), as: UTF8.self)
        }
        #expect(try encoded(.notCode) == #"["text"]"#)
        #expect(try encoded(.code(.swift)) == #"["swift"]"#)
        #expect(try encoded(.code(.generic)) == #"["generic"]"#)
        for detection in [CodeDetection.notCode] + CodeLanguage.allCases.map(CodeDetection.code) {
            let decoded = try JSONDecoder().decode([CodeDetection].self, from: encoder.encode([detection]))
            #expect(decoded == [detection])
        }
    }

    @Test func aLanguageFromALaterVersionStillReadsAsCode() throws {
        let decoded = try JSONDecoder().decode([CodeDetection].self, from: Data(#"["zig"]"#.utf8))
        #expect(decoded == [.code(.generic)])
    }

    @Test func anItemWithADetectionRoundTripsAndOneWithoutLeavesTheKeyOut() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var history = ClipboardHistory()
        add(.text(Self.swiftCode), to: &history, at: 0)
        let json = String(decoding: try encoder.encode(history), as: UTF8.self)
        #expect(json.contains(#""codeDetection":"swift""#))
        #expect(try JSONDecoder().decode(ClipboardHistory.self, from: Data(json.utf8)) == history)
        var legacy = history
        legacy.items[0].codeDetection = nil
        #expect(!String(decoding: try encoder.encode(legacy), as: UTF8.self).contains("codeDetection"))
    }
}
