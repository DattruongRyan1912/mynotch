import ClipboardMCPKit
import Foundation
import Testing
@testable import ClipboardModule

/// What an agent may read of the history, and in what shape. The history is built by hand, so every rule is met on its own.
@Suite struct ClipboardMCPAnswererTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func item(
        _ content: ClipboardContent, daysAgo: Double = 0, app: String? = "Safari", bundleID: String? = "com.apple.Safari",
        sensitive: Bool? = false, code: CodeDetection? = .notCode
    ) -> ClipboardItem {
        ClipboardItem(
            id: UUID(), content: content, contentHash: UUID().uuidString, copiedAt: now.addingTimeInterval(-daysAgo * 86_400),
            sourceBundleID: bundleID, sourceAppName: app, codeDetection: code, sensitive: sensitive
        )
    }

    func answer(
        _ request: ClipboardMCPRequest, _ items: [ClipboardItem], boards: [ClipboardBoard] = [], locked: Set<UUID> = []
    ) -> ClipboardMCPAnswer {
        let history = ClipboardHistory(items: items, boards: boards)
        return ClipboardMCPAnswerer.answer(request, history: history, index: ClipboardSearchIndex(), lockedBoardIDs: locked, now: now)
    }

    func search(_ query: String = "", kind: ClipboardMCPKind? = nil, app: String? = nil, limit: Int = 10, sinceDays: Int? = nil) -> ClipboardMCPRequest {
        .search(ClipboardMCPSearch(query: query, kind: kind, app: app, limit: limit, sinceDays: sinceDays))
    }

    /// The items of a successful answer, as the JSON an agent reads.
    func items(of answer: ClipboardMCPAnswer) -> [JSON] {
        guard case .success(let result) = answer.reply, case .array(let items)? = result["items"] else { return [] }
        return items
    }

    func ids(of answer: ClipboardMCPAnswer) -> [String] {
        items(of: answer).compactMap { $0["id"]?.string }
    }

    func result(_ answer: ClipboardMCPAnswer) -> JSON? {
        if case .success(let result) = answer.reply { result } else { nil }
    }

    // MARK: Finding

    @Test func everyWordMustBeInTheItemIgnoringCaseAndAccents() {
        let hit = item(.text("Hóa đơn tháng Mười số 42"))
        let miss = item(.text("hóa đơn tháng chín"))
        let found = answer(search("HOA DON muoi"), [miss, hit])
        #expect(ids(of: found) == [hit.id.uuidString])
        #expect(found.resultCount == 1)
    }

    @Test func anEmptyTextListsTheNewestFirstAndTheLimitCutsTheList() {
        let all = (0..<5).map { item(.text("n\($0)"), daysAgo: Double($0)) }
        let found = answer(search(limit: 3), all)
        #expect(ids(of: found) == all.prefix(3).map(\.id.uuidString))
        #expect(found.resultCount == 3)
        #expect(result(found)?["count"] == .int(3))
        #expect(result(found)?["matches"] == .int(5))
    }

    @Test func anAtSignInTheTextIsJustTheCharacterAndNotAnAppFilter() {
        let mail = item(.text("write to ann@example.com"))
        let other = item(.text("nothing here"), app: "Mail", bundleID: "com.apple.mail")
        #expect(ids(of: answer(search("ann@example.com"), [other, mail])) == [mail.id.uuidString])
        #expect(ids(of: answer(search("@mail"), [other, mail])).isEmpty)
    }

    @Test func aKindOnlyGivesItsOwnItemsAndCodeIsNotText() {
        let prose = item(.text("hello world"))
        let code = item(.text("let x = 1"), code: .code(.swift))
        let link = item(.link(URL(string: "https://example.com")!))
        let color = item(.color(hex: "#FF8800"))
        let image = item(ClipboardModuleTests.image("a"))
        let files = item(.files([URL(filePath: "/tmp/a.txt")]))
        let all = [prose, code, link, color, image, files]
        #expect(ids(of: answer(search(kind: .text), all)) == [prose.id.uuidString])
        #expect(ids(of: answer(search(kind: .code), all)) == [code.id.uuidString])
        #expect(ids(of: answer(search(kind: .link), all)) == [link.id.uuidString])
        #expect(ids(of: answer(search(kind: .color), all)) == [color.id.uuidString])
        #expect(ids(of: answer(search(kind: .image), all)) == [image.id.uuidString])
        #expect(ids(of: answer(search(kind: .file), all)) == [files.id.uuidString])
    }

    @Test func anItemNotYetClassifiedCountsAsText() {
        let old = item(.text("let x = 1"), code: nil)
        #expect(ids(of: answer(search(kind: .text), [old])) == [old.id.uuidString])
    }

    @Test func anAppMatchesPartOfItsNameOrItsBundleIDIgnoringCase() {
        let chrome = item(.text("a"), app: "Google Chrome", bundleID: "com.google.Chrome")
        let safari = item(.text("b"))
        let unnamed = item(.text("c"), app: nil, bundleID: "com.example.Notes")
        let all = [chrome, safari, unnamed]
        #expect(ids(of: answer(search(app: "chrome"), all)) == [chrome.id.uuidString])
        #expect(ids(of: answer(search(app: "GOOGLE"), all)) == [chrome.id.uuidString])
        #expect(ids(of: answer(search(app: "com.example"), all)) == [unnamed.id.uuidString])
        #expect(ids(of: answer(search(app: "xcode"), all)).isEmpty)
    }

    @Test func sinceDaysKeepsWhatWasCopiedInTheLastDays() {
        let today = item(.text("t"), daysAgo: 0)
        let twoDays = item(.text("w"), daysAgo: 2)
        let tenDays = item(.text("x"), daysAgo: 10)
        #expect(ids(of: answer(search(sinceDays: 1), [today, twoDays, tenDays])) == [today.id.uuidString])
        #expect(ids(of: answer(search(sinceDays: 3), [today, twoDays, tenDays])) == [today.id.uuidString, twoDays.id.uuidString])
        #expect(ids(of: answer(search(sinceDays: 2), [twoDays])) == [twoDays.id.uuidString])
    }

    @Test func theFiltersWorkTogether() {
        let wanted = item(.link(URL(string: "https://example.com/invoice")!), daysAgo: 1, app: "Safari")
        let wrongApp = item(.link(URL(string: "https://example.com/invoice")!), daysAgo: 1, app: "Mail", bundleID: "com.apple.mail")
        let wrongKind = item(.text("example invoice"), daysAgo: 1)
        let tooOld = item(.link(URL(string: "https://example.com/invoice")!), daysAgo: 9)
        let found = answer(search("invoice", kind: .link, app: "safari", sinceDays: 3), [wrongApp, wrongKind, wanted, tooOld])
        #expect(ids(of: found) == [wanted.id.uuidString])
    }

    // MARK: What is never returned

    @Test func anItemMarkedSensitiveIsNeverFoundWhateverTheSearch() {
        let secret = item(.text("hunter2 password"), sensitive: true)
        let plain = item(.text("hunter2 recipe"))
        let all = [secret, plain]
        for request in [search("hunter2"), search("", limit: 50), search(kind: .text), search(app: "safari"), search(sinceDays: 5)] {
            let found = answer(request, all)
            #expect(!ids(of: found).contains(secret.id.uuidString), "\(request)")
            #expect(ids(of: found).contains(plain.id.uuidString))
        }
        #expect(result(answer(search("hunter2"), all))?["matches"] == .int(1))
    }

    @Test func anItemNotKnownToBeASecretIsReturnedSinceOnlyTheFlaggedOnesAreHeld() {
        let unknown = item(.text("old copy"), sensitive: nil)
        #expect(ids(of: answer(search(), [unknown])) == [unknown.id.uuidString])
    }

    @Test func anItemOfALockedBoardIsNeverFoundEvenWhenAnOpenBoardHoldsItToo() {
        let kept = item(.text("kept in a locked board"))
        let both = item(.text("in both boards"))
        let free = item(.text("free"))
        let locked = ClipboardBoard(id: UUID(), name: "Riêng tư", systemImage: "lock", itemIDs: [kept.id, both.id])
        let open = ClipboardBoard(id: UUID(), name: "Công việc", systemImage: "folder", itemIDs: [both.id, free.id])
        let found = answer(search(), [kept, both, free], boards: [locked, open], locked: [locked.id])
        #expect(ids(of: found) == [free.id.uuidString])
        #expect(result(found)?["matches"] == .int(1))
        // Nothing is locked while no board is named as locked, which is how things are until boards can be locked.
        #expect(ids(of: answer(search(), [kept, both, free], boards: [locked, open])).count == 3)
    }

    @Test func aSensitiveItemOrOneInALockedBoardIsNotFoundByIdAndLooksLikeAnItemThatIsNotThere() {
        let secret = item(.text("s"), sensitive: true)
        let hidden = item(.text("h"))
        let locked = ClipboardBoard(id: UUID(), name: "L", systemImage: "lock", itemIDs: [hidden.id])
        let missing = answer(.item(UUID()), [secret, hidden], boards: [locked], locked: [locked.id])
        let secretAnswer = answer(.item(secret.id), [secret, hidden], boards: [locked], locked: [locked.id])
        let hiddenAnswer = answer(.item(hidden.id), [secret, hidden], boards: [locked], locked: [locked.id])
        #expect(secretAnswer == missing)
        #expect(hiddenAnswer == missing)
        guard case .failure(let reason, let message) = missing.reply else {
            Issue.record("not a failure")
            return
        }
        #expect(reason == .notFound)
        #expect(message.contains("search_clipboard"))
        #expect(missing.resultCount == 0)
    }

    // MARK: One item

    @Test func anItemIsReturnedByItsId() {
        let wanted = item(.text("body"), app: "Notes", bundleID: "com.apple.Notes")
        let found = answer(.item(wanted.id), [item(.text("other")), wanted])
        #expect(found.resultCount == 1)
        guard case .success(let json) = found.reply else {
            Issue.record("not found")
            return
        }
        #expect(json["id"] == .string(wanted.id.uuidString))
        #expect(json["text"] == .string("body"))
        #expect(json["app"] == .string("Notes"))
    }

    // MARK: Shape

    @Test func aTextItemCarriesItsKindAppDateAndSize() {
        let text = item(.text("héllo"), daysAgo: 1, app: "Notes", bundleID: "com.apple.Notes")
        let json = items(of: answer(search(), [text])).first
        #expect(json?["kind"] == .string("text"))
        #expect(json?["text"] == .string("héllo"))
        #expect(json?["bytes"] == .int(6))
        #expect(json?["truncated"] == .bool(false))
        #expect(json?["app"] == .string("Notes"))
        #expect(json?["copiedAt"] == .string("2027-01-14T08:00:00Z"))
        #expect(json?["language"] == nil)
        #expect(json?["image"] == nil)
    }

    @Test func codeSaysItsLanguageExceptWhenItIsNoLanguageInParticular() {
        let swift = item(.text("let x = 1"), code: .code(.swift))
        let generic = item(.text("???"), code: .code(.generic))
        let found = items(of: answer(search(kind: .code), [swift, generic]))
        #expect(found.map { $0["kind"] } == [.string("code"), .string("code")])
        #expect(found.map { $0["language"] } == [.string("swift"), nil])
    }

    @Test func eachKindGivesItsTextForm() {
        let link = item(.link(URL(string: "https://example.com/a?b=1")!))
        let hex = item(.color(hex: "#FF8800"))
        let rgb = item(.color(hex: "#FF8800", original: "rgb(255, 136, 0)"))
        let rich = item(.richText(plain: "plain words", rtf: Data("{\\rtf1 rich}".utf8)))
        let files = item(.files([URL(filePath: "/tmp/a.txt"), URL(filePath: "/tmp/b.txt")]))
        let texts = items(of: answer(search(limit: 10), [link, hex, rgb, rich, files])).map { $0["text"] }
        #expect(texts == [
            .string("https://example.com/a?b=1"), .string("#FF8800"), .string("rgb(255, 136, 0)"), .string("plain words"), .string("/tmp/a.txt\n/tmp/b.txt"),
        ])
    }

    @Test func anImageIsOnlyItsSizeAndNeverItsBytesOrItsFile() throws {
        let image = item(.image(ClipboardImage(fileName: "abcdef.png", pixelWidth: 640, pixelHeight: 480, byteCount: 12_345)))
        let json = try #require(items(of: answer(search(), [image])).first)
        #expect(json["kind"] == .string("image"))
        #expect(json["image"] == .object(["width": .int(640), "height": .int(480), "bytes": .int(12_345)]))
        #expect(json["text"] == nil)
        #expect(json["truncated"] == nil)
        let encoded = String(decoding: try json.encoded(), as: UTF8.self)
        #expect(!encoded.contains("abcdef"))
    }

    @Test func anItemWithNoAppNameFallsBackToItsBundleIDOrLeavesTheAppOut() {
        let bundleOnly = item(.text("a"), app: nil, bundleID: "com.example.Notes")
        let neither = item(.text("b"), app: nil, bundleID: nil)
        let found = items(of: answer(search(), [bundleOnly, neither]))
        #expect(found.map { $0["app"] } == [.string("com.example.Notes"), nil])
    }

    // MARK: Size

    @Test func aTextOverEightKilobytesIsCutAndSaysSo() throws {
        let long = String(repeating: "a", count: 20_000)
        let json = try #require(items(of: answer(search(), [item(.text(long))])).first)
        #expect(json["truncated"] == .bool(true))
        #expect(json["bytes"] == .int(20_000))
        #expect(json["text"]?.string?.utf8.count == 8 * 1024)
    }

    @Test func aTextOfExactlyEightKilobytesIsNotCut() throws {
        let json = try #require(items(of: answer(search(), [item(.text(String(repeating: "a", count: 8 * 1024)))])).first)
        #expect(json["truncated"] == .bool(false))
        #expect(json["text"]?.string?.utf8.count == 8 * 1024)
    }

    @Test func theCutNeverSplitsACharacter() throws {
        // Two-byte letters from byte 1: the limit falls in the middle of one.
        let text = "a" + String(repeating: "đ", count: 6_000)
        let json = try #require(items(of: answer(search(), [item(.text(text))])).first)
        let cut = try #require(json["text"]?.string)
        #expect(json["truncated"] == .bool(true))
        #expect(cut.utf8.count == 8 * 1024 - 1)
        #expect(cut == "a" + String(repeating: "đ", count: 4_095))
        // A family emoji is one character of several scalars; it is dropped whole, not left in pieces.
        let family = String(repeating: "a", count: 8 * 1024 - 5) + "👨‍👩‍👧‍👦"
        let cutFamily = try #require(items(of: answer(search(), [item(.text(family))])).first?["text"]?.string)
        #expect(cutFamily == String(repeating: "a", count: 8 * 1024 - 5))
    }

    @Test func theAnswerHoldsAtMostAFixedAmountOfTextAndSaysHowManyItLeftOut() throws {
        let all = (0..<30).map { item(.text(String(repeating: "x", count: 10_000) + "\($0)"), daysAgo: Double($0) / 100) }
        let found = answer(search(limit: 50), all)
        let kept = items(of: found)
        // 8 KB each, and 128 KB in all: sixteen items.
        #expect(kept.count == 16)
        #expect(found.resultCount == 16)
        #expect(result(found)?["count"] == .int(16))
        #expect(result(found)?["matches"] == .int(30))
        #expect(result(found)?["omitted"] == .int(14))
        #expect(kept.compactMap { $0["text"]?.string?.utf8.count }.reduce(0, +) <= ClipboardMCPLimits.maxTotalTextBytes)
    }

    @Test func nothingIsLeftOutWhenTheLimitIsTheOnlyCut() {
        let found = answer(search(limit: 2), (0..<5).map { item(.text("n\($0)")) })
        #expect(result(found)?["omitted"] == nil)
    }

    // MARK: Nothing found

    @Test func nothingFoundIsAnAnswerWithNoItems() {
        let found = answer(search("zzz"), [item(.text("a"))])
        #expect(found.resultCount == 0)
        #expect(result(found)?["count"] == .int(0))
        #expect(result(found)?["items"] == .array([]))
        #expect(result(found)?["matches"] == .int(0))
    }
}
