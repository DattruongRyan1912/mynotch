import AppKit
import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import ClipboardModule

/// Link previews in the running module: when a page is read, when it never is, and what is kept.
@Suite final class ClipboardLinkPreviewModuleTests {
    let fixture: OptionalFeaturesFixture
    let transport: FakeLinkTransport
    var module: ClipboardModule { fixture.module }

    init() {
        transport = FakeLinkTransport()
        fixture = OptionalFeaturesFixture(transport: transport)
    }

    let url = "https://www.example.com/bai-viet"

    /// A link copied, and its card shown: the module is asked to read it.
    @discardableResult
    func show(_ link: String) async throws -> ClipboardItem {
        fixture.copy(link)
        let item = try fixture.item(link)
        module.requestLinkPreview(for: item)
        return item
    }

    func current(_ link: String) throws -> ClipboardItem { try fixture.item(link) }

    // MARK: Never

    @Test func thereIsNoFetchWhileTheSettingIsOff() async throws {
        fixture.servePage(url)
        await fixture.start()
        let (settings, keys) = try fixture.settings()
        #expect(settings.value(keys.linkPreviews) == false)
        try await show(url)
        await fixture.waitForLinks()
        #expect(transport.requests.isEmpty)
        #expect(transport.lookups.isEmpty)
        #expect(module.linkPreviews.startedCount == 0)
        #expect(try current(url).linkPreview == nil)
        #expect(module.linkPreviewDisplay(for: try current(url)) == nil)
    }

    @Test func thereIsNoFetchForAStoppedModule() async throws {
        try fixture.setLinkPreviews(true)
        fixture.servePage(url)
        let item = ClipboardModuleTests.item(.link(URL(string: url)!), copiedAt: fixture.system.now)
        module.requestLinkPreview(for: item)
        #expect(transport.requests.isEmpty)
    }

    /// Opening MyNotch with a history full of links reads nothing: only a card that is shown asks.
    @Test func nothingIsReadAtLaunchOrInBulk() async throws {
        try fixture.setLinkPreviews(true)
        var history = ClipboardHistory()
        for number in 1...40 {
            let content = ClipboardContent.link(URL(string: "https://www.example.com/trang-\(number)")!)
            history.add(content, hash: ClipboardContent.hash(of: content), source: (nil, nil), at: fixture.system.now.addingTimeInterval(Double(-number)))
        }
        let store = ClipboardStore(directory: fixture.directory, scheduler: ManualScheduler(), logger: Log.logger(category: "test"))
        _ = store.load()
        store.scheduleSave(history)
        await store.flush()
        await fixture.start()
        await fixture.waitForLinks()
        fixture.harness.scheduler.advance(by: .seconds(30))
        #expect(fixture.items.count == 40)
        #expect(transport.requests.isEmpty)
        #expect(transport.lookups.isEmpty)
        // One shown card reads one page, and only that one.
        module.requestLinkPreview(for: try #require(fixture.items.first))
        await fixture.waitForLinks()
        #expect(transport.requestedURLs.filter { $0.hasPrefix("https://www.example.com/trang-") }.count == 1)
    }

    @Test(arguments: [
        "http://localhost:8080/admin", "http://127.0.0.1/", "http://192.168.1.1/login", "http://10.0.0.5/", "http://169.254.169.254/latest/meta-data/",
        "http://[::1]/", "http://[fd00::1]/", "http://router/", "http://printer.local/", "http://nas.lan/status", "https://user:secret@example.com/",
        "http://2130706433/",
    ])
    func aLinkTheGuardRefusesIsNeverRead(_ address: String) async throws {
        try fixture.setLinkPreviews(true)
        await fixture.start()
        // A row that is not copied as a link would pass without testing anything, so it fails instead.
        let parsed = try #require(URL(string: address), "\(address) is not an address")
        try #require(ClipboardClassifier.link(address) != nil, "\(address) is not copied as a link")
        let item = try await show(address)
        await fixture.waitForLinks()
        #expect(transport.requests.isEmpty, "\(parsed)")
        #expect(transport.lookups.isEmpty, "\(parsed)")
        #expect(module.linkPreviewDisplay(for: item) == nil)
    }

    @Test func aSecretIsNeverRead() async throws {
        try fixture.setLinkPreviews(true)
        await fixture.start()
        let (settings, keys) = try fixture.settings()
        settings.set(false, for: keys.ignoreSensitive)
        // Marked by the app that copied it, and kept because the user chose to keep such copies.
        fixture.servePage("https://www.example.com/marked")
        fixture.copy("https://www.example.com/marked", extraTypes: ["org.nspasteboard.ConcealedType"])
        module.requestLinkPreview(for: try current("https://www.example.com/marked"))
        // Looking like one: a token in the address.
        for secret in [
            "https://www.example.com/reset?token=abcdef1234567890", "https://www.example.com/cb?access_token=zyxwvu987654321", "https://hooks.slack.com/services/T0000000/B0000000/XXXXXXXXXXXXXXXXXXXXXXXX",
        ] {
            fixture.servePage(secret)
            try await show(secret)
        }
        await fixture.waitForLinks()
        #expect(transport.requests.isEmpty)
        #expect(module.linkPreviewDisplay(for: try current("https://www.example.com/marked")) == nil)
    }

    @Test func anItemOfALockedBoardIsNeverRead() async throws {
        try fixture.setLinkPreviews(true)
        await fixture.start()
        fixture.copy(url)
        let item = try current(url)
        _ = try await fixture.pinToOpenLockedBoard(item)
        let open = try current(url)
        module.requestLinkPreview(for: open)
        await fixture.waitForLinks()
        #expect(transport.requests.isEmpty)
        #expect(module.linkPreviewDisplay(for: open) == nil)
    }

    // MARK: Reading

    @Test func aShownLinkIsReadAndItsTitleAndPictureAreKept() async throws {
        try fixture.setLinkPreviews(true)
        fixture.servePage(url, title: "Bài viết &amp; hình")
        await fixture.start()
        let shown = try await show(url)
        #expect(module.linkPreviewDisplay(for: shown) == ClipboardLinkPreviewDisplay(title: nil, imageURL: nil))
        await fixture.waitForLinks()

        let item = try current(url)
        #expect(item.linkPreview == ClipboardLinkPreview(title: "Bài viết & hình", hasImage: true))
        let file = try fixture.previewFile(of: item)
        #expect(fixture.exists(file))
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
        let folder = try FileManager.default.attributesOfItem(atPath: fixture.linkPreviewsDirectory.path(percentEncoded: false))
        #expect((folder[.posixPermissions] as? Int) == 0o700)
        let size = try #require(TestPictures.size(of: Data(contentsOf: file)))
        #expect(size.width == 256)
        // The files of the history's own images are not touched or mixed with.
        let images = fixture.directory.appending(path: "images")
        #expect(!((try? FileManager.default.contentsOfDirectory(atPath: images.path(percentEncoded: false)))?.contains(file.lastPathComponent) ?? false))

        let display = try #require(module.linkPreviewDisplay(for: item))
        #expect(display.title == "Bài viết & hình")
        #expect(display.imageURL == file)
    }

    @Test func whatWasReadStaysAfterARestart() async throws {
        try fixture.setLinkPreviews(true)
        fixture.servePage(url)
        await fixture.start()
        try await show(url)
        await fixture.waitForLinks()
        let before = try current(url)
        await fixture.restart()
        let after = try current(url)
        #expect(after.linkPreview == before.linkPreview)
        #expect(fixture.exists(try fixture.previewFile(of: after)))
        // Not read again.
        let requests = transport.requests.count
        module.requestLinkPreview(for: after)
        await fixture.waitForLinks()
        #expect(transport.requests.count == requests)
    }

    @Test func aPageWithNothingToShowIsRememberedAsThat() async throws {
        try fixture.setLinkPreviews(true)
        transport.set(url, .html("<html><head></head><body>trống</body></html>"))
        await fixture.start()
        try await show(url)
        await fixture.waitForLinks()
        let item = try current(url)
        #expect(item.linkPreview == ClipboardLinkPreview(title: nil, hasImage: false))
        let requests = transport.requests.count
        module.requestLinkPreview(for: item)
        await fixture.waitForLinks()
        #expect(transport.requests.count == requests)
    }

    // MARK: Once

    @Test func aLinkIsReadOnceHoweverOftenItsCardAsks() async throws {
        try fixture.setLinkPreviews(true)
        fixture.servePage(url)
        await fixture.start()
        let item = try await show(url)
        for _ in 0..<6 { module.requestLinkPreview(for: item) }
        await fixture.waitForLinks()
        #expect(transport.requestedURLs.filter { $0 == url }.count == 1)
        #expect(module.linkPreviews.startedCount == 1)
        for _ in 0..<3 { module.requestLinkPreview(for: try current(url)) }
        await fixture.waitForLinks()
        #expect(transport.requestedURLs.filter { $0 == url }.count == 1)
    }

    @Test func aFailureIsRememberedForTheSession() async throws {
        try fixture.setLinkPreviews(true)
        transport.set(url, .status(503))
        await fixture.start()
        let item = try await show(url)
        await fixture.waitForLinks()
        #expect(transport.requestedURLs.filter { $0 == url }.count == 1)
        #expect(try current(url).linkPreview == nil)
        // Asked again, and again: nothing more is sent.
        for _ in 0..<3 {
            module.requestLinkPreview(for: item)
            await fixture.waitForLinks()
        }
        #expect(transport.requestedURLs.filter { $0 == url }.count == 1)
        #expect(module.linkPreviewDisplay(for: try current(url)) == ClipboardLinkPreviewDisplay(title: nil, imageURL: nil))

        // A new run is a new session: it may try again.
        transport.set(url, .html("<head><title>Đã sửa</title></head>"))
        await fixture.restart()
        module.requestLinkPreview(for: try current(url))
        await fixture.waitForLinks()
        #expect(try current(url).linkPreview?.title == "Đã sửa")
    }

    @Test(.timeLimit(.minutes(1))) func aTimeOutIsAFailureToo() async throws {
        let hanging = LinkFlag()
        let slow = FakeLinkTransport { _ in
            hanging.raise()
            try await Task.sleep(for: .seconds(3600))
            return .status(200)
        }
        let request = Duration.milliseconds(5)
        let local = OptionalFeaturesFixture(
            transport: slow, timeouts: (request, .seconds(20)), sleep: LinkTimers.runningOut([request], after: hanging)
        )
        try local.setLinkPreviews(true)
        await local.start()
        local.copy(url)
        local.module.requestLinkPreview(for: try local.item(url))
        await local.waitForLinks()
        #expect(slow.requests.count == 1)
        local.module.requestLinkPreview(for: try local.item(url))
        await local.waitForLinks()
        #expect(slow.requests.count == 1)
        #expect(try local.item(url).linkPreview == nil)
    }

    // MARK: Things that change while it is on its way

    @Test func turningTheSettingOffStopsWhatIsOnItsWay() async throws {
        try fixture.setLinkPreviews(true)
        let cancelled = LinkFlag()
        transport.setHandler { _ in
            do {
                try await Task.sleep(for: .seconds(3600))
            } catch {
                cancelled.raise()
                throw error
            }
            return .status(200)
        }
        await fixture.start()
        try await show(url)
        await fixture.wait { !transport.requests.isEmpty }
        #expect(module.linkPreviews.running.count == 1)
        try fixture.setLinkPreviews(false)
        // The request itself is called off, not just its answer ignored.
        await fixture.wait { cancelled.isRaised }
        #expect(cancelled.isRaised)
        #expect(module.linkPreviews.running.isEmpty)
        #expect(module.linkPreviews.queue.isEmpty)
        await fixture.waitForLinks()
        #expect(try current(url).linkPreview == nil)
        #expect(!fixture.exists(fixture.linkPreviewsDirectory))
    }

    @Test func anItemDeletedMeanwhileKeepsNothing() async throws {
        try fixture.setLinkPreviews(true)
        let gate = LinkGate()
        fixture.servePage(url)
        let table = transport
        transport.setHandler { request in
            await gate.wait()
            return table.tableAnswer(for: request)
        }
        await fixture.start()
        let item = try await show(url)
        await fixture.wait { !transport.requests.isEmpty }
        module.delete(item)
        gate.open()
        await fixture.waitForLinks()
        #expect(fixture.items.isEmpty)
        #expect(!fixture.exists(fixture.linkPreviewsDirectory) || ((try? FileManager.default.contentsOfDirectory(atPath: fixture.linkPreviewsDirectory.path(percentEncoded: false)))?.isEmpty ?? true))
    }

    @Test func anItemPinnedToALockedBoardMeanwhileKeepsNothing() async throws {
        try fixture.setLinkPreviews(true)
        let gate = LinkGate()
        fixture.servePage(url)
        let table = transport
        transport.setHandler { request in
            await gate.wait()
            return table.tableAnswer(for: request)
        }
        await fixture.start()
        let item = try await show(url)
        await fixture.wait { !transport.requests.isEmpty }
        let board = try #require(module.createBoard(named: "Két"))
        module.pin(item, to: board)
        try await module.lockBoard(board, setup: .password(OptionalFeaturesFixture.password))
        try await module.unlockBoard(board, credential: .password(OptionalFeaturesFixture.password))
        gate.open()
        await fixture.waitForLinks()
        #expect(try current(url).linkPreview == nil)
        #expect(!fixture.exists(fixture.linkPreviewsDirectory) || ((try? FileManager.default.contentsOfDirectory(atPath: fixture.linkPreviewsDirectory.path(percentEncoded: false)))?.isEmpty ?? true))
    }

    /// A link waiting for its turn is looked at again when the turn comes: what changed meanwhile decides whether anything is sent.
    @Test func aQueuedLinkThatIsNoLongerWantedIsNeverSent() async throws {
        try fixture.setLinkPreviews(true)
        let gate = LinkGate()
        transport.setHandler { request in
            await gate.wait()
            return request.kind == .page ? .html("<head><title>Trang</title></head>") : .status(404)
        }
        await fixture.start()
        let busy = (1...ClipboardModule.linkFetchLimit).map { "https://www.example.com/ban-\($0)" }
        for link in busy { try await show(link) }
        await fixture.wait { transport.mostAtOnce >= ClipboardModule.linkFetchLimit }
        let deleted = "https://www.example.com/se-bi-xoa", locked = "https://www.example.com/se-vao-ket", kept = "https://www.example.com/van-con"
        for link in [deleted, locked, kept] { try await show(link) }
        #expect(module.linkPreviews.queue.count == 3)

        module.delete(try current(deleted))
        _ = try await fixture.pinToOpenLockedBoard(try current(locked))
        gate.open()
        await fixture.waitForLinks()
        #expect(transport.requestedURLs.contains(kept))
        #expect(!transport.requestedURLs.contains(deleted))
        #expect(!transport.requestedURLs.contains(locked))
        #expect(try current(locked).linkPreview == nil)
    }

    @Test func stoppingTheModuleStopsWhatIsOnItsWay() async throws {
        try fixture.setLinkPreviews(true)
        let cancelled = LinkFlag()
        transport.setHandler { _ in
            do {
                try await Task.sleep(for: .seconds(3600))
            } catch {
                cancelled.raise()
                throw error
            }
            return .status(200)
        }
        await fixture.start()
        try await show(url)
        await fixture.wait { !transport.requests.isEmpty }
        await fixture.harness.registry.setEnabled(false, for: "clipboard")
        #expect(module.linkPreviews.running.isEmpty)
        #expect(module.linkPreviews.queue.isEmpty)
        await fixture.wait { cancelled.isRaised }
        #expect(cancelled.isRaised)
    }

    // MARK: How many at once

    @Test func onlyAFewPagesAreReadAtTheSameTime() async throws {
        try fixture.setLinkPreviews(true)
        let gate = LinkGate()
        transport.setHandler { request in
            await gate.wait()
            return request.kind == .page ? .html("<head><title>Trang</title></head>") : .status(404)
        }
        await fixture.start()
        let links = (1...10).map { "https://www.example.com/dong-\($0)" }
        for link in links { fixture.copy(link) }
        for link in links { module.requestLinkPreview(for: try current(link)) }
        await fixture.wait { transport.mostAtOnce >= ClipboardModule.linkFetchLimit }
        #expect(module.linkPreviews.running.count == ClipboardModule.linkFetchLimit)
        #expect(module.linkPreviews.queue.count == 10 - ClipboardModule.linkFetchLimit)
        gate.open()
        await fixture.waitForLinks()
        #expect(transport.mostAtOnce <= ClipboardModule.linkFetchLimit)
        #expect(links.allSatisfy { (try? current($0).linkPreview?.title) == "Trang" })
        #expect(ClipboardModule.linkFetchLimit == 3)
    }

    // MARK: What is removed with the item

    @Test func thePictureGoesWithItsItem() async throws {
        try fixture.setLinkPreviews(true)
        fixture.servePage(url)
        await fixture.start()
        try await show(url)
        await fixture.waitForLinks()
        let item = try current(url)
        let file = try fixture.previewFile(of: item)
        #expect(fixture.exists(file))
        module.delete(item)
        #expect(!fixture.exists(file))
    }

    @Test func thePictureGoesWhenTheHistoryIsPrunedOrCleared() async throws {
        try fixture.setLinkPreviews(true)
        let (settings, keys) = try fixture.settings()
        settings.set(ClipboardSettingKeys.historyLimitRange.lowerBound, for: keys.historyLimit)
        fixture.servePage(url)
        await fixture.start()
        try await show(url)
        await fixture.waitForLinks()
        let file = try fixture.previewFile(of: try current(url))
        #expect(fixture.exists(file))
        // Pushed out by newer copies.
        for number in 0..<(ClipboardSettingKeys.historyLimitRange.lowerBound + 2) { fixture.copy("mục thường số \(number)") }
        #expect(fixture.items.allSatisfy { $0.content.plainText != url })
        #expect(!fixture.exists(file))

        // And by clearing.
        let other = "https://www.example.com/khac"
        fixture.servePage(other, image: "https://cdn.example.com/q.png")
        try await show(other)
        await fixture.waitForLinks()
        let otherFile = try fixture.previewFile(of: try current(other))
        #expect(fixture.exists(otherFile))
        module.clearHistory(.all)
        #expect(!fixture.exists(otherFile))
    }

    @Test func clearingWhileTheModuleIsStoppedRemovesThePicturesToo() async throws {
        try fixture.setLinkPreviews(true)
        fixture.servePage(url)
        await fixture.start()
        try await show(url)
        await fixture.waitForLinks()
        let file = try fixture.previewFile(of: try current(url))
        await fixture.harness.registry.setEnabled(false, for: "clipboard")
        #expect(fixture.exists(file))
        await module.clearHistory(.all, directory: fixture.directory).value
        #expect(!fixture.exists(file))
    }

    @Test func editingTheWordsDropsWhatWasReadOfTheOldAddress() async throws {
        try fixture.setLinkPreviews(true)
        fixture.servePage(url)
        await fixture.start()
        let item = try await show(url)
        await fixture.waitForLinks()
        let file = try fixture.previewFile(of: try current(url))
        #expect(fixture.exists(file))
        let edited = ClipboardContent.link(URL(string: "https://www.example.com/dia-chi-moi")!)
        var outcome: ClipboardEditOutcome?
        module.update { history in
            outcome = history.applyEdit(to: item.id, content: edited, mode: .replace, at: fixture.system.now)
            return []
        }
        #expect(outcome == .saved(item.id))
        let after = try #require(fixture.items.first { $0.id == item.id })
        #expect(after.linkPreview == nil)
        #expect(!fixture.exists(file))
    }

    @Test func aPictureNoItemNamesIsRemovedAtStart() async throws {
        try fixture.setLinkPreviews(true)
        fixture.servePage(url)
        await fixture.start()
        try await show(url)
        await fixture.waitForLinks()
        let kept = try fixture.previewFile(of: try current(url))
        let stray = fixture.linkPreviewsDirectory.appending(path: "link-\(String(repeating: "a", count: 64)).png")
        let junk = fixture.linkPreviewsDirectory.appending(path: "notes.txt")
        try Data([1, 2, 3]).write(to: stray)
        try Data([4]).write(to: junk)
        await fixture.restart()
        #expect(fixture.exists(kept))
        #expect(!fixture.exists(stray))
        #expect(!fixture.exists(junk))
    }

    @Test func aBoardThatLocksTakesThePictureAndTheTitleWithIt() async throws {
        try fixture.setLinkPreviews(true)
        fixture.servePage(url)
        await fixture.start()
        let item = try await show(url)
        await fixture.waitForLinks()
        let file = try fixture.previewFile(of: try current(url))
        #expect(fixture.exists(file))
        let board = try #require(module.createBoard(named: "Két"))
        module.pin(try current(url), to: board)
        // Pinned to an ordinary board, it keeps what it has.
        #expect(try current(url).linkPreview?.title == "Trang thử")
        try await module.lockBoard(board, setup: .password(OptionalFeaturesFixture.password))
        #expect(fixture.items.isEmpty)
        #expect(!fixture.exists(file))
        // Nothing of the page is in the module's folder: the vault holds the item sealed, without it.
        for needle in ["Trang thử", "cdn.example.com"] {
            let found = filesHolding(needle)
            #expect(found.isEmpty, "\(needle) in \(found)")
        }
        try await module.unlockBoard(board, credential: .password(OptionalFeaturesFixture.password))
        let reopened = try #require(fixture.items.first { $0.content.plainText == url })
        #expect(reopened.id == item.id)
        #expect(reopened.linkPreview == nil)
        #expect(!fixture.exists(file))
        module.requestLinkPreview(for: reopened)
        await fixture.waitForLinks()
        #expect(reopened.linkPreview == nil)
        #expect(transport.requestedURLs.filter { $0 == url }.count == 1)
    }

    @Test func pinningToAnOpenLockedBoardDropsWhatWasRead() async throws {
        try fixture.setLinkPreviews(true)
        fixture.servePage(url)
        await fixture.start()
        try await show(url)
        await fixture.waitForLinks()
        let file = try fixture.previewFile(of: try current(url))
        #expect(fixture.exists(file))
        // A board that has a lock, open: what is pinned to it is for what must stay private.
        let board = try #require(module.createBoard(named: "Két"))
        fixture.copy("một mục để khoá")
        module.pin(try fixture.item("một mục để khoá"), to: board)
        try await module.lockBoard(board, setup: .password(OptionalFeaturesFixture.password))
        try await module.unlockBoard(board, credential: .password(OptionalFeaturesFixture.password))
        module.pin(try current(url), to: board)
        #expect(try current(url).linkPreview == nil)
        #expect(!fixture.exists(file))
        #expect(module.linkPreviewDisplay(for: try current(url)) == nil)
    }

    // MARK: What a card draws

    @Test func aCardDrawsNothingExtraWhileTheSettingIsOff() async throws {
        try fixture.setLinkPreviews(true)
        fixture.servePage(url)
        await fixture.start()
        try await show(url)
        await fixture.waitForLinks()
        #expect(module.linkPreviewDisplay(for: try current(url)) != nil)
        try fixture.setLinkPreviews(false)
        #expect(module.linkPreviewDisplay(for: try current(url)) == nil)
        // What was read is kept, and shows again when the setting does.
        try fixture.setLinkPreviews(true)
        #expect(module.linkPreviewDisplay(for: try current(url))?.title == "Trang thử")
    }

    @Test func onlyLinksHaveAPreview() async throws {
        try fixture.setLinkPreviews(true)
        await fixture.start()
        fixture.copy("chỉ là chữ")
        let text = try current("chỉ là chữ")
        module.requestLinkPreview(for: text)
        #expect(module.linkPreviewDisplay(for: text) == nil)
        #expect(transport.requests.isEmpty)
        // A mail link is a link and still not a page.
        fixture.copy("mailto:ai-do@example.com")
        let mail = try current("mailto:ai-do@example.com")
        module.requestLinkPreview(for: mail)
        #expect(module.linkPreviewDisplay(for: mail) == nil)
        #expect(transport.requests.isEmpty)
    }

    // MARK: Files

    /// Every file under the module's folder whose bytes hold `needle`.
    func filesHolding(_ needle: String) -> [String] {
        guard let walker = FileManager.default.enumerator(at: fixture.directory, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var found: [String] = []
        for case let file as URL in walker {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true, let data = try? Data(contentsOf: file) else { continue }
            if data.range(of: Data(needle.utf8)) != nil { found.append(file.lastPathComponent) }
        }
        return found
    }
}

extension FakeLinkTransport {
    /// What the table answers for a request, for a handler that waits first and then answers as the table does.
    func tableAnswer(for request: ClipboardLinkRequest) -> ClipboardLinkResponse {
        tableLookup(request.url.absoluteString) ?? .status(404)
    }
}
