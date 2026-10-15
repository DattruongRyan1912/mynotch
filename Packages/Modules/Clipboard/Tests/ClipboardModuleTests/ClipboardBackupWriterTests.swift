import Foundation
import Testing
@testable import ClipboardModule

/// What an export writes: the archive's parts, what is left out and why, and that a failed or cancelled export leaves nothing.
@Suite final class ClipboardBackupWriterTests {
    let world: BackupWorld

    init() throws {
        world = try BackupWorld()
    }

    func texts(_ payloads: [String: Data]) -> [String] {
        payloads.keys.sorted()
    }

    func decode(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    // MARK: What the archive holds

    @Test func theArchiveHasAManifestAndOnePayloadPerTextRichTextAndImage() async throws {
        let (url, summary) = try await world.export()
        let contents = try world.contents(of: url)

        var expected = [
            ClipboardBackupFormat.manifestName,
            BackupWorld.payload(world.id("text"), "txt"),
            BackupWorld.payload(world.id("rich"), "txt"), BackupWorld.payload(world.id("rich"), "rtf"),
            BackupWorld.payload(world.id("code"), "txt"),
            BackupWorld.payload(world.id("image"), "png"), BackupWorld.payload(world.id("image2"), "png"),
        ]
        expected.sort()
        #expect(contents.names.sorted() == expected)
        // A link, a colour and a file list are small enough to live in the manifest.
        #expect(summary.itemCount == 9)
    }

    @Test func thePayloadsAreTheTextTheRTFAndThePNGOfTheItems() async throws {
        let (url, _) = try await world.export()
        let payloads = try world.contents(of: url).payloads

        #expect(decode(try #require(payloads[BackupWorld.payload(world.id("text"), "txt")])) == "Xin chào")
        #expect(decode(try #require(payloads[BackupWorld.payload(world.id("rich"), "txt")])) == "Bold line")
        #expect(payloads[BackupWorld.payload(world.id("rich"), "rtf")] == Data(#"{\rtf1\ansi {\b Bold} line}"#.utf8))
        #expect(payloads[BackupWorld.payload(world.id("image"), "png")] == world.firstPNG)
        #expect(payloads[BackupWorld.payload(world.id("image2"), "png")] == world.secondPNG)
    }

    @Test func theManifestIsVersionedAndCarriesEveryItemAndBoard() async throws {
        let (url, summary) = try await world.export()
        let manifest = try world.contents(of: url).manifest

        #expect(manifest["format"] as? String == "mynotchclip")
        #expect(manifest["version"] as? Int == 1)
        #expect(manifest["scope"] as? String == "all")
        #expect(manifest["includesSensitive"] as? Bool == false)
        #expect(manifest["createdAt"] as? Double == BackupWorld.base.timeIntervalSince1970 + 10_000)
        let items = world.manifestItems(manifest)
        #expect(items.count == 9)
        // Newest first, the order of the history, with the id, kind, time and source of each.
        #expect(items.map { $0["id"] as? String } == world.history.items.filter { !$0.isSensitive }.map(\.id.uuidString))
        #expect(items.map { $0["kind"] as? String } == ["text", "files", "image", "image", "color", "color", "link", "richText", "text"])
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0["id"] as! String, $0) })
        let link = try #require(byID[world.id("link").uuidString])
        #expect(link["kind"] as? String == "link" && link["link"] as? String == "https://example.com/a?b=1")
        #expect(link["sourceAppName"] as? String == "Chrome" && link["sourceBundleID"] as? String == "com.google.Chrome")
        #expect(link["copiedAt"] as? Double == world.item("link").copiedAt.timeIntervalSince1970)
        let rgb = try #require(byID[world.id("rgb").uuidString])
        #expect(rgb["color"] as? String == "#33669980" && rgb["colorOriginal"] as? String == "rgba(51, 102, 153, 0.5)")
        let hex = try #require(byID[world.id("hex").uuidString])
        #expect(hex["color"] as? String == "#FF8800" && hex["colorOriginal"] == nil)
        let image = try #require(byID[world.id("image").uuidString])
        #expect(image["kind"] as? String == "image")
        let boards = try #require(manifest["boards"] as? [[String: Any]])
        #expect(boards.map { $0["name"] as? String } == ["Công việc", "Ảnh", "Trống", "Bí mật"])
        #expect(boards.map { $0["icon"] as? String } == ["briefcase", "photo", "star", "lock"])
        #expect(boards[0]["color"] as? String == "orange" && boards[1]["color"] == nil && boards[2]["color"] as? String == "pink")
        #expect(summary.boardCount == 4)
    }

    @Test func theTextKindsCarryTheirCodeAnswer() async throws {
        let (url, _) = try await world.export()
        let items = world.manifestItems(try world.contents(of: url).manifest)
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0["id"] as! String, $0) })

        #expect(byID[world.id("code").uuidString]?["code"] as? String == "swift")
        #expect(byID[world.id("text").uuidString]?["code"] as? String == "text")
        #expect(byID[world.id("link").uuidString]?["code"] == nil)
    }

    @Test func theBoardsListTheirItemsInTheirOrderAndNothingElse() async throws {
        let (url, _) = try await world.export()
        let boards = try #require(try world.contents(of: url).manifest["boards"] as? [[String: Any]])
        let work = try #require(boards.first { $0["name"] as? String == "Công việc" })

        #expect(work["items"] as? [String] == [world.id("code").uuidString, world.id("text").uuidString])
        #expect((boards[2]["items"] as? [String]) == [])
    }

    @Test func aFileItemKeepsItsPathAndABookmarkWhenTheFileIsThere() async throws {
        let (url, summary) = try await world.export()
        let items = world.manifestItems(try world.contents(of: url).manifest)
        let files = try #require(items.first { $0["id"] as? String == world.id("files").uuidString })
        let refs = try #require(files["files"] as? [[String: Any]])

        #expect(refs.count == 2)
        #expect(refs[0]["path"] as? String == world.presentFile.path(percentEncoded: false))
        #expect((refs[0]["bookmark"] as? String).flatMap { Data(base64Encoded: $0) }?.isEmpty == false)
        #expect(refs[1]["path"] as? String == "/nonexistent-mynotch-test/b.txt")
        #expect(refs[1]["bookmark"] == nil)
        #expect(summary.fileItemCount == 1)
        #expect(summary.text.contains("có thể không khôi phục được"))
    }

    // MARK: Sensitive items

    @Test func aSecretIsLeftOutByDefaultAndNowhereInTheArchive() async throws {
        let (url, summary) = try await world.export()
        let reader = try ZipReader(url: url, limits: .unlimited)

        #expect(summary.skippedSensitive == 1 && summary.itemCount == 9)
        for entry in reader.entries {
            #expect(!decode(try reader.data(of: entry)).contains(BackupWorld.secretText), "\(entry.name)")
            #expect(!entry.name.contains(world.id("secret").uuidString))
        }
        let manifest = try world.contents(of: url).manifest
        #expect(manifest["includesSensitive"] as? Bool == false)
        let boards = try #require(manifest["boards"] as? [[String: Any]])
        #expect((boards[3]["items"] as? [String]) == [])
        #expect(boards[3]["name"] as? String == "Bí mật")
    }

    @Test func aSecretIsExportedMarkedWhenTheUserAllowsIt() async throws {
        let (url, summary) = try await world.export(ClipboardBackupOptions(skipSensitive: false))
        let contents = try world.contents(of: url)

        #expect(summary.skippedSensitive == 0 && summary.itemCount == 10)
        #expect(contents.manifest["includesSensitive"] as? Bool == true)
        #expect(decode(try #require(contents.payloads[BackupWorld.payload(world.id("secret"), "txt")])) == BackupWorld.secretText)
        let item = try #require(world.manifestItems(contents.manifest).first { $0["id"] as? String == world.id("secret").uuidString })
        #expect(item["sensitive"] as? Bool == true)
        let boards = try #require(contents.manifest["boards"] as? [[String: Any]])
        #expect((boards[3]["items"] as? [String]) == [world.id("secret").uuidString])
    }

    @Test func onlyAnItemFlaggedAsSecretIsLeftOutNotOneThatLooksLikeIt() async throws {
        var history = world.history
        // An item from before the flag existed, with a password-like text: not known to be a secret.
        let content = ClipboardContent.text("password: hunter2")
        history.items.insert(
            ClipboardItem(id: UUID(), content: content, contentHash: ClipboardContent.hash(of: content), copiedAt: BackupWorld.base, sourceBundleID: nil, sourceAppName: nil),
            at: 0
        )
        let (_, summary) = try await world.export(history: history)
        #expect(summary.itemCount == 10 && summary.skippedSensitive == 1)
    }

    // MARK: Scope

    @Test func pinnedOnlyTakesTheItemsOfBoardsAndEveryBoard() async throws {
        let (url, summary) = try await world.export(ClipboardBackupOptions(scope: .pinnedOnly))
        let manifest = try world.contents(of: url).manifest
        let ids = Set(world.manifestItems(manifest).compactMap { $0["id"] as? String })

        #expect(manifest["scope"] as? String == "pinned")
        // The secret is pinned too, and still left out.
        #expect(ids == Set([world.id("text"), world.id("code"), world.id("image")].map(\.uuidString)))
        #expect(summary.itemCount == 3 && summary.boardCount == 4 && summary.skippedSensitive == 1)
        #expect((manifest["boards"] as? [[String: Any]])?.count == 4)
    }

    @Test func pinnedOnlyWithSecretsAllowedTakesThePinnedSecretToo() async throws {
        let (_, summary) = try await world.export(ClipboardBackupOptions(scope: .pinnedOnly, skipSensitive: false))
        #expect(summary.itemCount == 4 && summary.skippedSensitive == 0)
    }

    @Test func aHistoryWithNothingToExportStillMakesAValidArchive() async throws {
        let (url, summary) = try await world.export(history: ClipboardHistory())
        #expect(summary.itemCount == 0 && summary.boardCount == 0)
        #expect(try world.contents(of: url).names == [ClipboardBackupFormat.manifestName])
    }

    // MARK: What cannot be exported

    @Test func anImageWhoseFileIsGoneIsLeftOutAndCounted() async throws {
        try FileManager.default.removeItem(at: world.imageURLs[world.firstPNG.sha256Hex + ".png"]!)
        let (url, summary) = try await world.export()

        #expect(summary.skippedUnreadable == 1 && summary.itemCount == 8)
        let names = try world.contents(of: url).names
        #expect(!names.contains(BackupWorld.payload(world.id("image"), "png")))
        #expect(names.contains(BackupWorld.payload(world.id("image2"), "png")))
        let boards = try #require(try world.contents(of: url).manifest["boards"] as? [[String: Any]])
        #expect((boards[1]["items"] as? [String]) == [])
    }

    @Test func anItemWithAPayloadOverTheItemLimitIsLeftOutAndCounted() async throws {
        // The code (52 bytes), the rich text (a 27-byte RTF) and both images are over 10 bytes; the 9-byte text is not.
        let (url, summary) = try await world.export(limits: ZipLimits(perEntry: 10, total: 100_000))
        let ids = Set(world.manifestItems(try world.contents(of: url).manifest).compactMap { $0["id"] as? String })

        #expect(summary.skippedTooLarge == 4 && summary.itemCount == 5)
        #expect(ids == Set(["text", "link", "hex", "rgb", "files"].map { world.id($0).uuidString }))
    }

    @Test func anItemThatWouldTakeTheArchiveOverTheTotalIsLeftOutAndASmallerOneAfterItStillFits() async throws {
        // The manifest takes its part of the total first, as large as it could be; 40 bytes are left for payloads. Newest first:
        // the code (52 bytes) does not fit; the files, colours and link need none; the rich text takes 36; the text (9) would
        // make 45; the images do not fit either.
        let (full, _) = try await world.export(as: "full.mynotchclip")
        let manifestSize = try #require(ZipReader(url: full, limits: .unlimited).entries.first { $0.name == "manifest.json" }).size
        let limits = ZipLimits(perEntry: 1_000_000, total: manifestSize + 40)

        let (url, summary) = try await world.export(limits: limits)
        let ids = Set(world.manifestItems(try world.contents(of: url).manifest).compactMap { $0["id"] as? String })
        #expect(summary.skippedTooLarge == 4 && summary.itemCount == 5)
        #expect(ids == Set(["rich", "link", "hex", "rgb", "files"].map { world.id($0).uuidString }))
        // However much was left out, what is written is never over the total.
        #expect(try ZipReader(url: url, limits: limits).entries.count == 3)
    }

    @Test func aTotalSmallerThanTheManifestAloneIsTooLarge() async throws {
        await #expect(throws: ClipboardBackupError.tooLarge) { try await world.export(limits: ZipLimits(perEntry: 1_000_000, total: 100)) }
        #expect(!FileManager.default.fileExists(atPath: world.file("backup.mynotchclip").path(percentEncoded: false)))
    }

    // MARK: Progress, cancelling and failing

    nonisolated final class Progress: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Double] = []

        func record(_ value: Double) {
            lock.lock()
            values.append(value)
            lock.unlock()
        }

        var all: [Double] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }
    }

    @Test func progressGoesUpToOneAndNeverBack() async throws {
        let progress = Progress()
        _ = try await world.export(progress: { progress.record($0) })

        let values = progress.all
        #expect(values.count >= 2)
        #expect(values.last == 1)
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(values.allSatisfy { (0...1).contains($0) })
    }

    @Test func cancellingLeavesNothingAtTheDestinationOrBesideIt() async throws {
        let destination = world.file("cancelled.mynotchclip")
        let before = try FileManager.default.contentsOfDirectory(atPath: world.root.path(percentEncoded: false)).sorted()

        let task = Task {
            try await ClipboardBackupWriter.write(
                history: world.history, options: ClipboardBackupOptions(), imageURLs: world.imageURLs, to: destination,
                progress: { _ in withUnsafeCurrentTask { $0?.cancel() } }
            )
        }
        await #expect(throws: CancellationError.self) { try await task.value }

        #expect(!FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)))
        #expect(try FileManager.default.contentsOfDirectory(atPath: world.root.path(percentEncoded: false)).sorted() == before)
    }

    @Test func aCancelledExportKeepsTheFileItWouldHaveReplaced() async throws {
        let destination = world.file("keep.mynotchclip")
        try Data("older backup".utf8).write(to: destination)

        let task = Task {
            try await ClipboardBackupWriter.write(
                history: world.history, options: ClipboardBackupOptions(), imageURLs: world.imageURLs, to: destination,
                progress: { _ in withUnsafeCurrentTask { $0?.cancel() } }
            )
        }
        await #expect(throws: CancellationError.self) { try await task.value }

        #expect(try Data(contentsOf: destination) == Data("older backup".utf8))
    }

    @Test func aFinishedExportReplacesAnOlderFile() async throws {
        let destination = world.file("replace.mynotchclip")
        try Data("older backup".utf8).write(to: destination)

        _ = try await world.export(as: "replace.mynotchclip")

        #expect(try ZipReader(url: destination, limits: .unlimited).entries.count == 7)
    }

    @Test func aFolderThatCannotBeWrittenIsAnErrorAndLeavesNothing() async throws {
        let destination = world.root.appending(path: "missing/folder/backup.mynotchclip")
        await #expect(throws: ClipboardBackupError.self) {
            try await ClipboardBackupWriter.write(
                history: world.history, options: ClipboardBackupOptions(), imageURLs: world.imageURLs, to: destination
            )
        }
        #expect(!FileManager.default.fileExists(atPath: world.root.appending(path: "missing").path(percentEncoded: false)))
    }

    @Test func theArchiveIsOneTheReaderAcceptsUnderTheRealLimits() async throws {
        let (url, _) = try await world.export(ClipboardBackupOptions(skipSensitive: false))
        let reader = try ZipReader(url: url, limits: ClipboardBackupFormat.limits)
        for entry in reader.entries { _ = try reader.data(of: entry) }
        #expect(ClipboardBackupFormat.fileExtension == "mynotchclip")
        #expect(ClipboardBackupFormat.maxItemBytes == 50 * 1024 * 1024)
        #expect(ClipboardBackupFormat.maxTotalBytes == 2 * 1024 * 1024 * 1024)
    }

    // MARK: Words

    @Test func theSummaryTellsWhatWasWrittenAndLeftOut() {
        let plain = ClipboardBackupExportSummary(itemCount: 520, boardCount: 4)
        #expect(plain.text == "Đã sao lưu 520 mục và 4 board.")
        let more = ClipboardBackupExportSummary(itemCount: 5, boardCount: 1, skippedSensitive: 3, skippedTooLarge: 2, skippedUnreadable: 1, fileItemCount: 2)
        #expect(more.text.hasPrefix("Đã sao lưu 5 mục và 1 board"))
        #expect(more.text.contains("bỏ qua 3 mục nhạy cảm"))
        #expect(more.text.contains("2 mục quá lớn"))
        #expect(more.text.contains("1 mục không đọc được"))
        #expect(more.text.contains("2 mục file"))
    }
}
