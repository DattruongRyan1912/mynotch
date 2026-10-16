import CryptoKit
import Foundation
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import ClipboardModule

/// The rules of link previews that need no module: what an item holds, where its picture is kept, what a board that has a lock does to both.
@Suite struct ClipboardLinkPreviewModelTests {
    let date = Date(timeIntervalSince1970: 1_800_000_000)

    func linkItem(_ address: String = "https://www.example.com/a", preview: ClipboardLinkPreview? = nil) -> ClipboardItem {
        var item = ClipboardModuleTests.item(.link(URL(string: address)!), copiedAt: date)
        item.linkPreview = preview
        return item
    }

    // MARK: The item

    @Test func anItemHoldsItsPreviewAndAnOlderFileStillReads() throws {
        let item = linkItem(preview: ClipboardLinkPreview(title: "Tiêu đề", hasImage: true))
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: JSONEncoder().encode(item))
        #expect(decoded == item)
        #expect(decoded.linkPreview?.title == "Tiêu đề")

        // A history saved before there was a preview has no such key.
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(linkItem())) as? [String: Any])
        object["linkPreview"] = nil
        let old = try JSONDecoder().decode(ClipboardItem.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.linkPreview == nil)
        // And an item with none writes none.
        let text = String(decoding: try JSONEncoder().encode(linkItem()), as: UTF8.self)
        #expect(!text.contains("linkPreview"))
    }

    @Test func aHandEditedPreviewIsReadWithCare() throws {
        func decode(_ json: String) throws -> ClipboardLinkPreview {
            try JSONDecoder().decode(ClipboardLinkPreview.self, from: Data(json.utf8))
        }
        #expect(try decode("{}") == ClipboardLinkPreview(title: nil, hasImage: false))
        #expect(try decode("{\"title\":\"Có chữ\"}") == ClipboardLinkPreview(title: "Có chữ", hasImage: false))
        #expect(try decode("{\"hasImage\":true}") == ClipboardLinkPreview(title: nil, hasImage: true))
        #expect(try decode("{\"title\":7,\"hasImage\":\"yes\"}") == ClipboardLinkPreview(title: nil, hasImage: false))
        // A title that is not plain, or that is far too long, is made plain and cut as it was when it was read.
        let long = String(repeating: "x", count: 1_000_000)
        let title = try #require(decode("{\"title\":\"a\\u0007\\u202Eb \(long)\"}").title)
        #expect(title.count == 200)
        #expect(title.hasPrefix("ab xxx"))
    }

    @Test func thePicturesFileIsNamedAfterTheLinkAndOnlyThat() {
        let item = linkItem()
        let name = ClipboardLinkPreview.imageFileName(forHash: item.contentHash)
        #expect(item.linkPreviewFileName == name)
        #expect(name == "link-\(item.contentHash).png")
        #expect(ClipboardLinkPreview.isImageFileName(name))
        // Not the name of an image item's file, and not a way out of the folder.
        #expect(!ClipboardLinkPreview.isImageFileName(item.contentHash + ".png"))
        #expect(!ClipboardLinkPreview.isImageFileName("link-../../history.json"))
        #expect(!ClipboardLinkPreview.isImageFileName("link-\(item.contentHash).png/../x"))
        #expect(!ClipboardLinkPreview.isImageFileName("link-ABC.png"))
        #expect(ClipboardModuleTests.item(.text("a"), copiedAt: date).linkPreviewFileName == nil)
    }

    @Test func settingAPreviewHasRules() {
        var history = ClipboardHistory(items: [linkItem(), ClipboardModuleTests.item(.text("chữ"), copiedAt: date)])
        let link = history.items[0], text = history.items[1]
        let preview = ClipboardLinkPreview(title: "x", hasImage: false)
        let forLink = history.setLinkPreview(preview, for: link.id)
        #expect(forLink)
        #expect(history.items[0].linkPreview?.title == "x")
        // Not a link, and not there.
        let forText = history.setLinkPreview(preview, for: text.id)
        let forNobody = history.setLinkPreview(preview, for: UUID())
        #expect(!forText)
        #expect(!forNobody)
        #expect(history.items[1].linkPreview == nil)
    }

    @Test func aBoardThatHasALockTakesNoPreview() {
        var history = ClipboardHistory(items: [linkItem()])
        let id = history.items[0].id
        let board = history.createBoard(name: "Két")
        history.boards[0].lock = ClipboardBoardLock(method: .password, itemCount: 0, isUnlocked: true)
        history.items[0].linkPreview = ClipboardLinkPreview(title: "t", hasImage: true)
        history.boards[0].lock = nil
        history.pin(itemID: id, to: board)
        // An ordinary board keeps what the item has.
        #expect(history.items[0].linkPreview?.title == "t")
        history.unpin(itemID: id, from: board)
        history.boards[0].lock = ClipboardBoardLock(method: .password, itemCount: 0, isUnlocked: true)
        history.pin(itemID: id, to: board)
        #expect(history.items[0].linkPreview == nil)
        let again = history.setLinkPreview(ClipboardLinkPreview(title: "again", hasImage: false), for: id)
        #expect(!again)
        #expect(history.items[0].linkPreview == nil)
    }

    @Test func theFilesThatItemsHoldAreTheOnesThatAreNotInAProtectedBoard() {
        var held = linkItem("https://www.example.com/held", preview: ClipboardLinkPreview(title: "a", hasImage: true))
        let hidden = linkItem("https://www.example.com/hidden", preview: ClipboardLinkPreview(title: "b", hasImage: true))
        let titleOnly = linkItem("https://www.example.com/title", preview: ClipboardLinkPreview(title: "c", hasImage: false))
        held.linkPreview = ClipboardLinkPreview(title: "a", hasImage: true)
        var history = ClipboardHistory(items: [held, hidden, titleOnly, ClipboardModuleTests.item(.text("chữ"), copiedAt: date)])
        #expect(history.linkPreviewFileNames == [held.linkPreviewFileName!, hidden.linkPreviewFileName!])
        // A board that has a lock holds `hidden`, whatever put it there.
        let board = history.createBoard(name: "Két")
        history.boards[0].itemIDs = [hidden.id]
        history.boards[0].lock = ClipboardBoardLock(method: .password, itemCount: 1, isUnlocked: true)
        #expect(history.linkPreviewFileNames == [held.linkPreviewFileName!])
        _ = board
        #expect(ClipboardHistory().linkPreviewFileNames.isEmpty)
    }

    @Test func replacingTheWordsOfALinkDropsItsPreview() {
        var history = ClipboardHistory(items: [linkItem(preview: ClipboardLinkPreview(title: "t", hasImage: true))])
        let id = history.items[0].id
        let content = ClipboardContent.link(URL(string: "https://www.example.com/b")!)
        let outcome = history.applyEdit(to: id, content: content, mode: .replace, at: date)
        #expect(outcome == .saved(id))
        #expect(history.items[0].linkPreview == nil)
        #expect(history.items[0].contentHash == ClipboardContent.hash(of: content))
    }

    @Test func aRecopyKeepsWhatWasRead() {
        var history = ClipboardHistory(items: [linkItem(preview: ClipboardLinkPreview(title: "t", hasImage: true))])
        let item = history.items[0]
        history.add(item.content, hash: item.contentHash, source: ("com.apple.Safari", "Safari"), at: date.addingTimeInterval(60))
        #expect(history.items.count == 1)
        #expect(history.items[0].linkPreview?.title == "t")
    }

    // MARK: The seal

    @Test func aSealHoldsNoPreview() throws {
        let item = linkItem(preview: ClipboardLinkPreview(title: "Tiêu đề bí mật", hasImage: true))
        let key = ClipboardVaultCrypto.randomKey()
        let board = UUID()
        let sealed = try ClipboardVaultSealer.sealNow(items: [item], images: [:], key: key, boardID: board)
        let plaintext = try ClipboardVaultCrypto.open(sealed, using: key, boardID: board, itemCount: 1)
        let opened = try ClipboardVaultPayload.decode(plaintext)
        #expect(opened.items.count == 1)
        #expect(opened.items[0].id == item.id)
        #expect(opened.items[0].linkPreview == nil)
        #expect(plaintext.range(of: Data("Tiêu đề bí mật".utf8)) == nil)
    }

    // MARK: The files

    func makeStore() throws -> (ClipboardStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "mn-linkstore-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (ClipboardStore(directory: directory, scheduler: ManualScheduler(), logger: Log.logger(category: "ClipboardLinkPreviewModelTests")), directory)
    }

    @Test func aPictureIsKeptApartFromImagesAndOnlyUnderItsOwnName() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let name = ClipboardLinkPreview.imageFileName(forHash: String(repeating: "ab", count: 32))
        try store.saveLinkPreviewImage(Data([1, 2, 3]), fileName: name)
        let url = try #require(store.linkPreviewURL(fileName: name))
        #expect(url.deletingLastPathComponent().lastPathComponent == "linkpreviews")
        #expect(url.path(percentEncoded: false).hasPrefix(directory.path(percentEncoded: false)))
        #expect(try Data(contentsOf: url) == Data([1, 2, 3]))
        #expect(!FileManager.default.fileExists(atPath: store.imagesDirectory.appending(path: name).path(percentEncoded: false)))
        // Never a name that is not one of ours, and never a way out of the folder.
        for bad in ["../history.json", "link-../x.png", "notes.txt", String(repeating: "ab", count: 32) + ".png", ""] {
            #expect(store.linkPreviewURL(fileName: bad) == nil, "\(bad)")
            #expect(throws: (any Error).self) { try store.saveLinkPreviewImage(Data([9]), fileName: bad) }
        }
    }

    @Test func theImagesFolderSweepLeavesLinkPicturesAlone() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let name = ClipboardLinkPreview.imageFileName(forHash: String(repeating: "cd", count: 32))
        try store.saveLinkPreviewImage(Data([1]), fileName: name)
        // A start sweeps `images/` of what no image item names; the link pictures are not in it.
        _ = store.load()
        #expect(FileManager.default.fileExists(atPath: directory.appending(components: "linkpreviews", name).path(percentEncoded: false)))
    }

    @Test func orphansAreSweptAndTheRestKept() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let kept = ClipboardLinkPreview.imageFileName(forHash: String(repeating: "11", count: 32))
        let gone = ClipboardLinkPreview.imageFileName(forHash: String(repeating: "22", count: 32))
        try store.saveLinkPreviewImage(Data([1]), fileName: kept)
        try store.saveLinkPreviewImage(Data([2]), fileName: gone)
        try Data([3]).write(to: store.linkPreviewsDirectory.appending(path: "other.txt"))
        store.deleteOrphanLinkPreviews(keeping: [kept])
        let left = try FileManager.default.contentsOfDirectory(atPath: store.linkPreviewsDirectory.path(percentEncoded: false))
        #expect(left == [kept])
        // Nothing to sweep is not an error, and neither is deleting what is not there.
        store.deleteLinkPreviewImages(named: [gone, "not-a-name"])
        store.deleteLinkPreviewImages(named: [kept])
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.linkPreviewsDirectory.path(percentEncoded: false)).isEmpty)
        let (fresh, other) = try makeStore()
        defer { try? FileManager.default.removeItem(at: other) }
        fresh.deleteOrphanLinkPreviews(keeping: [])
    }
}

/// What the cards and panes say and draw for a link whose page was read.
@Suite struct ClipboardLinkPreviewViewTests {
    let address = URL(string: "https://www.example.com/bai-viet/mot")!

    @Test func aRowIsNamedByTheTitleOfItsPage() {
        let content = ClipboardContent.link(address)
        #expect(ClipboardCardText.rowTitle(of: content) == "www.example.com /bai-viet/mot")
        #expect(ClipboardCardText.rowTitle(of: content, linkTitle: "Bài viết một") == "Bài viết một")
        #expect(ClipboardCardText.rowTitle(of: content, linkTitle: nil) == "www.example.com /bai-viet/mot")
        // Only a link has a title from a page.
        #expect(ClipboardCardText.rowTitle(of: .text("chữ"), linkTitle: "Tiêu đề") == "chữ")
    }

    @Test func theLargePreviewSaysWhereTheTitleCameFrom() {
        let link = ClipboardPreviewLink(address)
        #expect(ClipboardPreviewLinkPane(link: link, display: nil).note == "Chỉ hiện địa chỉ: MyNotch không mở trang này.")
        #expect(ClipboardPreviewLinkPane(link: link, display: ClipboardLinkPreviewDisplay(title: "Tiêu đề", imageURL: nil)).note
            == "Tiêu đề và ảnh lấy từ trang của link.")
        // Nothing read yet: it neither says it will not open the page, nor claims what it has not got.
        #expect(ClipboardPreviewLinkPane(link: link, display: ClipboardLinkPreviewDisplay(title: nil, imageURL: nil)).note == nil)
        #expect(ClipboardLinkPreviewDisplay(title: nil, imageURL: nil).isEmpty)
        #expect(!ClipboardLinkPreviewDisplay(title: "x", imageURL: nil).isEmpty)
        #expect(!ClipboardLinkPreviewDisplay(title: nil, imageURL: URL(fileURLWithPath: "/tmp/x.png")).isEmpty)
    }

    @Test func theCaptionsSayWhatTheyAreFor() {
        #expect(ClipboardSettingsView.linkPreviewsNote.contains("mở trang của link"))
        #expect(ClipboardSettingsView.linkPreviewsNote.contains("tiêu đề"))
        #expect(ClipboardSettingsView.linkPreviewsNote.contains("địa chỉ IP"))
        #expect(ClipboardSettingsView.soundsNote.contains("khi MyNotch ghi lại"))
        #expect(ClipboardSettingsView.soundsNote.contains("dán"))
    }

    @Test func bothSettingsAreOffByDefaultAndKeepTheirNames() throws {
        let harness = RegistryHarness([ClipboardIDModule()])
        let settings = try #require(harness.settingsEnvironment(for: "clipboard")).settings
        let keys = ClipboardSettingKeys(settings)
        #expect(keys.playSounds.name == "module.clipboard.playSounds")
        #expect(keys.linkPreviews.name == "module.clipboard.linkPreviews")
        #expect(settings.value(keys.playSounds) == false)
        #expect(settings.value(keys.linkPreviews) == false)
        settings.set(true, for: keys.playSounds)
        settings.set(true, for: keys.linkPreviews)
        #expect(settings.value(keys.playSounds))
        #expect(settings.value(keys.linkPreviews))
    }

    // MARK: Drawn

    /// What a view draws, as the bytes of an offscreen picture, so two drawings can be told apart.
    @MainActor func drawing(_ view: some View, size: CGSize = CGSize(width: 150, height: 110)) throws -> Data {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height, alignment: .topLeading).environment(\.colorScheme, .dark))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    @MainActor @Test func aCardWithATitleDrawsDifferentlyFromOneWithout() throws {
        let thumbnails = ClipboardThumbnailCache()
        func card(_ link: ClipboardLinkPreviewDisplay?) -> some View {
            ClipboardContentPreview(
                content: .link(address), imageURL: nil, thumbnails: thumbnails, style: .notch(onGlass: false), link: link
            )
        }
        let plain = try drawing(card(nil))
        let empty = try drawing(card(ClipboardLinkPreviewDisplay(title: nil, imageURL: nil)))
        let titled = try drawing(card(ClipboardLinkPreviewDisplay(title: "Bài viết số một về chủ đề dài", imageURL: nil)))
        // Nothing read yet: the card is the card it always was.
        #expect(plain == empty)
        #expect(plain != titled)
    }

    @MainActor @Test func everyStyleDrawsTheRichLinkAndDrawsItDifferently() throws {
        let thumbnails = ClipboardThumbnailCache()
        let display = ClipboardLinkPreviewDisplay(title: "Một tiêu đề khá là dài để chiếm hai dòng của thẻ", imageURL: nil)
        let styles: [ClipboardContentPreview.Style] = [.notch(onGlass: false), .notch(onGlass: true), .panel, .library(.small), .library(.medium), .library(.large)]
        for style in styles {
            let rich = try drawing(ClipboardContentPreview(content: .link(address), imageURL: nil, thumbnails: thumbnails, style: style, link: display))
            let plain = try drawing(ClipboardContentPreview(content: .link(address), imageURL: nil, thumbnails: thumbnails, style: style))
            #expect(rich != plain)
        }
        #expect(ClipboardLibraryCardSize.allCases.map(\.linkTitleLines) == [1, 2, 3])
        #expect(ClipboardLibraryCardSize.allCases.map(\.linkImageHeight) == [22, 36, 60])
    }
}
