import Foundation
import MyNotchCore
import Testing
@testable import ClipboardModule

/// Whether the app that copied an item marked it as a secret, kept with the item so a backup can leave it out.
@Suite struct ClipboardSensitiveFlagTests {
    static let start = ClipboardHistoryTests.start

    func add(_ text: String, sensitive: Bool, to history: inout ClipboardHistory, at offset: TimeInterval = 0) -> UUID {
        let content = ClipboardContent.text(text)
        return history.add(
            content, hash: ClipboardContent.hash(of: content), source: (nil, nil), at: Self.start + offset, isSensitive: sensitive
        ).id
    }

    func item(_ id: UUID, in history: ClipboardHistory) throws -> ClipboardItem {
        try #require(history.items.first(where: { $0.id == id }))
    }

    @Test func aCopyMarkedAsASecretIsKeptMarked() throws {
        var history = ClipboardHistory()
        let secret = add("mật khẩu", sensitive: true, to: &history)
        let plain = add("xin chào", sensitive: false, to: &history, at: 1)

        #expect(try item(secret, in: history).isSensitive)
        #expect(try !item(plain, in: history).isSensitive)
        #expect(try item(plain, in: history).sensitive == false)
    }

    @Test func aCopyIsNeverLeftUnknown() throws {
        var history = ClipboardHistory()
        let id = add("xin chào", sensitive: false, to: &history)
        // Unknown is for what was saved before MyNotch tracked it, not for anything it captures.
        #expect(try item(id, in: history).sensitive != nil)
    }

    @Test func aCopyThatIsNotMarkedDoesNotClearWhatAnEarlierOneWas() throws {
        var legacy = ClipboardHistory(items: [
            ClipboardItem(
                id: UUID(), content: .text("cũ"), contentHash: ClipboardContent.hash(of: .text("cũ")), copiedAt: Self.start,
                sourceBundleID: nil, sourceAppName: nil
            ),
        ])
        legacy.add(.text("cũ"), hash: ClipboardContent.hash(of: .text("cũ")), source: (nil, nil), at: Self.start + 1)
        // The earlier copy may have been a secret; one that is not marked says nothing about it.
        #expect(legacy.items[0].sensitive == nil)
    }

    @Test func aTextThatWasASecretOnceStaysOneWhenCopiedAgainWithoutTheMark() throws {
        var history = ClipboardHistory()
        let id = add("mã 123456", sensitive: true, to: &history)
        _ = add("mã 123456", sensitive: false, to: &history, at: 5)
        #expect(history.items.count == 1)
        #expect(try item(id, in: history).isSensitive)
    }

    @Test func aTextCopiedAgainAsASecretBecomesOne() throws {
        var history = ClipboardHistory()
        let id = add("mã 123456", sensitive: false, to: &history)
        _ = add("mã 123456", sensitive: true, to: &history, at: 5)
        #expect(try item(id, in: history).isSensitive)
    }

    @Test func theFlagIsStoredWhenKnownAndLeftOutWhenNot() throws {
        var history = ClipboardHistory()
        _ = add("mật khẩu", sensitive: true, to: &history)
        _ = add("xin chào", sensitive: false, to: &history, at: 1)
        let unknown = ClipboardItem(
            id: UUID(), content: .text("cũ"), contentHash: "h-old", copiedAt: Self.start, sourceBundleID: nil, sourceAppName: nil
        )
        history.items.append(unknown)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let text = String(decoding: try encoder.encode(history.items), as: UTF8.self)

        #expect(text.components(separatedBy: "\"sensitive\"").count == 3)
        #expect(text.contains("\"sensitive\":true") && text.contains("\"sensitive\":false"))
        #expect(try JSONDecoder().decode([ClipboardItem].self, from: Data(text.utf8)) == history.items)
    }

    @Test func anItemSavedBeforeTheFlagExistedIsNotASecret() throws {
        let json = #"[{"id": "00000000-0000-0000-0000-000000000001", "content": {"text": {"_0": "a"}}, "contentHash": "h", "copiedAt": 800000000}]"#
        let items = try JSONDecoder().decode([ClipboardItem].self, from: Data(json.utf8))
        #expect(items.count == 1 && !items[0].isSensitive)
    }
}

extension ClipboardModuleTests {
    static let concealed = ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]

    @Test func aSecretKeptBecauseTheUserAllowsItIsMarkedAndAPlainCopyIsNot() async throws {
        let (settings, keys) = try settings()
        settings.set(false, for: keys.ignoreSensitive)
        await start()

        copy(PasteboardSnapshot(types: Self.concealed, string: "mật khẩu"))
        copy("xin chào")

        #expect(items.map(\.isSensitive) == [false, true])
        #expect(items.last?.content == .text("mật khẩu"))
    }

    @Test func aTransformOfASecretIsASecret() async throws {
        let (settings, keys) = try settings()
        settings.set(false, for: keys.ignoreSensitive)
        await start()
        copy(PasteboardSnapshot(types: Self.concealed, string: "a%20b"))
        let secret = try #require(items.first)

        #expect(module.apply(.urlDecode, to: secret))

        #expect(items.map(\.content) == [.text("a b"), .text("a%20b")])
        #expect(items.map(\.isSensitive) == [true, true])
    }
}
