import AppKit
import Foundation
import Testing
@testable import ClipboardModule

/// What an import accepts and refuses. Every refusal happens before anything is written: the archive is checked whole first,
/// and an item that cannot be read is left out and counted without taking the others with it.
@Suite final class ClipboardBackupReaderTests {
    let world: BackupWorld

    init() throws {
        world = try BackupWorld()
    }

    func failure(of url: URL, limits: ZipLimits = ClipboardBackupFormat.limits) async -> ClipboardBackupError? {
        do {
            _ = try await world.plan(url, limits: limits)
            return nil
        } catch {
            return error as? ClipboardBackupError
        }
    }

    /// A text item with its payload, for crafting a manifest.
    func textEntry(_ text: String, id: UUID = UUID(), extra: [String: Any] = [:]) -> (item: [String: Any], payloads: [(name: String, data: Data, mode: UInt16)]) {
        (BackupWorld.manifestItem(id, kind: "text", extra: extra), [(BackupWorld.payload(id, "txt"), Data(text.utf8), 0o100644)])
    }

    func restoredFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: world.restoredImages.path(percentEncoded: false)).sorted()
    }

    // MARK: Not a backup

    @Test func aFileThatIsNoArchiveIsNotABackup() async throws {
        let url = world.file("text.mynotchclip")
        try Data("not a zip".utf8).write(to: url)
        #expect(await failure(of: url) == .notABackup)
    }

    @Test func anArchiveWithoutAManifestIsNotABackup() async throws {
        let url = world.file("nomanifest.mynotchclip")
        let writer = try ZipWriter(url: url)
        try writer.add(name: "readme.txt", data: Data("hi".utf8))
        try writer.finish()
        #expect(await failure(of: url) == .notABackup)
    }

    @Test func aManifestOfAnotherFormatIsNotABackup() async throws {
        let url = try world.craft(manifest: BackupWorld.manifest(format: "something-else"))
        #expect(await failure(of: url) == .notABackup)
    }

    @Test func aFileThatCannotBeOpenedIsAReadError() async {
        let error = await failure(of: world.file("missing.mynotchclip"))
        guard case .cannotRead = error else {
            Issue.record("expected cannotRead, got \(String(describing: error))")
            return
        }
    }

    // MARK: Version and shape

    @Test func aNewerVersionIsRefusedBeforeItsShapeIsLookedAt() async throws {
        // Even a manifest that no longer has an `items` list says what is wrong: the file is from a later MyNotch.
        let url = try world.craft(manifest: try JSONSerialization.data(withJSONObject: ["format": "mynotchclip", "version": 2, "stuff": "new"]))
        #expect(await failure(of: url) == .newerVersion(2))
        let far = try world.craft(manifest: BackupWorld.manifest(version: 99), as: "far.mynotchclip")
        #expect(await failure(of: far) == .newerVersion(99))
    }

    @Test func versionZeroNegativeOrMissingIsMalformed() async throws {
        for version in [0, -1] {
            let url = try world.craft(manifest: BackupWorld.manifest(version: version), as: "v\(version).mynotchclip")
            #expect(await failure(of: url) == .malformed)
        }
        let missing = try world.craft(manifest: try JSONSerialization.data(withJSONObject: ["format": "mynotchclip", "items": []]), as: "none.mynotchclip")
        #expect(await failure(of: missing) == .malformed)
    }

    @Test func manifestsThatAreNotTheRightJSONAreMalformed() async throws {
        let cases: [(String, Data)] = [
            ("truncated", Data(#"{"format": "mynotchclip", "version": 1, "items": ["#.utf8)),
            ("empty", Data()),
            ("array", Data("[1, 2]".utf8)),
            ("itemsNotAList", BackupWorld.manifest(extra: ["items": "many"])),
            ("itemWithoutID", BackupWorld.manifest(items: [["kind": "text", "copiedAt": 1.0]])),
            ("badID", BackupWorld.manifest(items: [["id": "not-a-uuid", "kind": "text", "copiedAt": 1.0]])),
            ("badDate", BackupWorld.manifest(items: [["id": UUID().uuidString, "kind": "text", "copiedAt": "yesterday"]])),
            ("boardWithoutItems", BackupWorld.manifest(boards: [["name": "A", "icon": "star"]])),
        ]
        for (name, manifest) in cases {
            let url = try world.craft(manifest: manifest, as: "\(name).mynotchclip")
            #expect(await failure(of: url) == .malformed, "\(name)")
        }
    }

    @Test func aManifestWithNoItemsAndNoBoardsImportsNothing() async throws {
        let plan = try await world.plan(try world.craft())
        #expect(plan.items.isEmpty && plan.boards.isEmpty && plan.duplicates == 0 && plan.unreadable == 0)
    }

    @Test func aManifestKeyFromALaterMinorVersionIsIgnored() async throws {
        let entry = textEntry("giữ lại", extra: ["futureField": [1, 2, 3]])
        let url = try world.craft(manifest: BackupWorld.manifest(items: [entry.item], extra: ["futureTop": true]), entries: entry.payloads)
        #expect(try await world.plan(url).items.map(\.content) == [.text("giữ lại")])
    }

    // MARK: Unsafe archives

    @Test func anEntryNamedToLeaveTheFolderRefusesTheWholeBackup() async throws {
        let entry = textEntry("an toàn")
        for name in ["../x", "items/../../x", "/etc/passwd", "C:\\Windows\\x", "items\\..\\x"] {
            let url = try world.craft(
                manifest: BackupWorld.manifest(items: [entry.item]), entries: entry.payloads + [(name, Data("x".utf8), 0o100644)],
                as: "unsafe.mynotchclip"
            )
            #expect(await failure(of: url) == .unsafeEntry(name), "\(name)")
        }
        // Nothing was written, whatever the archive held before the bad entry.
        #expect(try restoredFiles().isEmpty)
    }

    @Test func aSymbolicLinkInsideTheBackupRefusesTheWholeBackup() async throws {
        let url = try world.craft(entries: [("items/link.txt", Data("/etc/passwd".utf8), 0o120755)])
        #expect(await failure(of: url) == .unsafeEntry("items/link.txt"))
    }

    @Test func twoEntriesWithOneNameRefuseTheWholeBackup() async throws {
        let id = UUID()
        let url = try world.craft(
            manifest: BackupWorld.manifest(items: [BackupWorld.manifestItem(id)]),
            entries: [(BackupWorld.payload(id, "txt"), Data("a".utf8), 0o100644), (BackupWorld.payload(id, "txt"), Data("b".utf8), 0o100644)]
        )
        #expect(await failure(of: url) == .unsafeEntry(BackupWorld.payload(id, "txt")))
    }

    @Test func aDeviceOrPipeEntryRefusesTheWholeBackup() async throws {
        let url = try world.craft(entries: [("items/dev", Data(), 0o060644)])
        #expect(await failure(of: url) == .unsafeEntry("items/dev"))
    }

    // MARK: Sizes

    /// The offsets of every central-directory record of the archive at `url`.
    func centralRecords(_ data: Data) -> [Int] {
        let bytes = [UInt8](data)
        return bytes.indices.dropLast(46).filter { bytes[$0] == 0x50 && bytes[$0 + 1] == 0x4B && bytes[$0 + 2] == 0x01 && bytes[$0 + 3] == 0x02 }
    }

    /// Rewrites the size each central-directory record claims, starting after the first `skipping` records.
    func claim(sizes: [UInt32], in url: URL, as name: String, skipping: Int = 0) throws -> URL {
        var data = try Data(contentsOf: url)
        for (offset, size) in zip(centralRecords(data).dropFirst(skipping), sizes) {
            for index in 0..<4 { data[offset + 24 + index] = UInt8((size >> (8 * UInt32(index))) & 0xFF) }
        }
        let patched = world.file(name)
        try data.write(to: patched)
        return patched
    }

    @Test func anItemClaimingMoreThanFiftyMegabytesRefusesTheWholeBackup() async throws {
        let entry = textEntry("nhỏ")
        let url = try world.craft(manifest: BackupWorld.manifest(items: [entry.item]), entries: entry.payloads)
        // The manifest is the first record. A header that claims 50 MB + 1 is refused before anything is read.
        let claimed = try claim(sizes: [UInt32(ClipboardBackupFormat.maxItemBytes + 1)], in: url, as: "big.mynotchclip")
        let error = await failure(of: claimed)
        guard case .itemTooLarge = error else {
            Issue.record("expected itemTooLarge, got \(String(describing: error))")
            return
        }
    }

    @Test func entriesThatTogetherClaimMoreThanTwoGigabytesRefuseTheWholeBackup() async throws {
        // Zeros deflate to a few bytes, so a header claiming more than the data is not caught by the stored-size rule.
        let entries = (0..<45).map { (name: "items/\($0).bin", data: Data(count: 1_000), mode: UInt16(0o100644)) }
        let url = try world.craft(entries: entries)
        // 45 headers of 50 MB each (the limit for one) are 2.25 GB together.
        let claimed = try claim(
            sizes: Array(repeating: UInt32(ClipboardBackupFormat.maxItemBytes), count: 45), in: url, as: "huge.mynotchclip", skipping: 1
        )
        #expect(await failure(of: claimed) == .tooLarge)
    }

    @Test func aPayloadWhoseDataDoesNotMatchItsChecksumIsLeftOutAndTheOthersStay() async throws {
        let good = textEntry("còn nguyên", id: UUID())
        let bad = textEntry("sẽ hỏng", id: UUID())
        let url = try world.craft(manifest: BackupWorld.manifest(items: [bad.item, good.item]), entries: bad.payloads + good.payloads)
        var data = try Data(contentsOf: url)
        // Flip the first byte of the bad payload, which is stored (it is too short to deflate).
        let marker = [UInt8](bad.payloads[0].data.prefix(4))
        let position = try #require([UInt8](data).indices.dropLast(4).first { Array(data[$0..<$0 + 4]) == marker })
        data[position] ^= 0xFF
        let damaged = world.file("flipped.mynotchclip")
        try data.write(to: damaged)

        let plan = try await world.plan(damaged)

        #expect(plan.items.map(\.content) == [.text("còn nguyên")])
        #expect(plan.unreadable == 1)
    }

    // MARK: Items that cannot be read

    @Test func anItemWithNoPayloadIsLeftOutAndCounted() async throws {
        let present = textEntry("có")
        let url = try world.craft(
            manifest: BackupWorld.manifest(items: [BackupWorld.manifestItem(UUID()), present.item]), entries: present.payloads
        )
        let plan = try await world.plan(url)
        #expect(plan.items.map(\.content) == [.text("có")] && plan.unreadable == 1)
    }

    @Test func textThatIsNotUTF8EmptyOrTooLongIsLeftOut() async throws {
        let bad = UUID(), blank = UUID(), long = UUID()
        let url = try world.craft(
            manifest: BackupWorld.manifest(items: [bad, blank, long].map { BackupWorld.manifestItem($0) }),
            entries: [
                (BackupWorld.payload(bad, "txt"), Data([0xFF, 0xFE, 0x41]), 0o100644),
                (BackupWorld.payload(blank, "txt"), Data("  \n ".utf8), 0o100644),
                (BackupWorld.payload(long, "txt"), Data(repeating: 0x61, count: ClipboardClassifier.maxTextBytes + 1), 0o100644),
            ]
        )
        let plan = try await world.plan(url)
        #expect(plan.items.isEmpty && plan.unreadable == 3)
    }

    @Test func aTextExactlyAtTheCaptureLimitIsKept() async throws {
        let entry = textEntry(String(repeating: "a", count: ClipboardClassifier.maxTextBytes))
        let url = try world.craft(manifest: BackupWorld.manifest(items: [entry.item]), entries: entry.payloads)
        #expect(try await world.plan(url).items.count == 1)
    }

    @Test func aKindThisVersionDoesNotKnowIsLeftOut() async throws {
        let url = try world.craft(manifest: BackupWorld.manifest(items: [BackupWorld.manifestItem(UUID(), kind: "hologram")]))
        let plan = try await world.plan(url)
        #expect(plan.items.isEmpty && plan.unreadable == 1)
    }

    @Test func linksAndColoursAreCheckedForShape() async throws {
        let good = [
            BackupWorld.manifestItem(UUID(), kind: "link", extra: ["link": "https://example.com/x"]),
            BackupWorld.manifestItem(UUID(), kind: "color", extra: ["color": "#abcdef"]),
            BackupWorld.manifestItem(UUID(), kind: "color", extra: ["color": "#112233CC", "colorOriginal": "rgba(17, 34, 51, 0.8)"]),
        ]
        let bad = [
            BackupWorld.manifestItem(UUID(), kind: "link", extra: ["link": "not a url"]),
            BackupWorld.manifestItem(UUID(), kind: "link", extra: ["link": "example.com"]),
            BackupWorld.manifestItem(UUID(), kind: "link"),
            BackupWorld.manifestItem(UUID(), kind: "color", extra: ["color": "red"]),
            BackupWorld.manifestItem(UUID(), kind: "color", extra: ["color": "#12345"]),
            BackupWorld.manifestItem(UUID(), kind: "color", extra: ["color": "#GGGGGG"]),
            BackupWorld.manifestItem(UUID(), kind: "color"),
        ]
        let plan = try await world.plan(try world.craft(manifest: BackupWorld.manifest(items: good + bad)))

        #expect(plan.items.map(\.content) == [
            .link(URL(string: "https://example.com/x")!), .color(hex: "#ABCDEF"), .color(hex: "#112233CC", original: "rgba(17, 34, 51, 0.8)"),
        ])
        #expect(plan.unreadable == 7)
    }

    @Test func fileItemsNeedAbsolutePathsAndAtLeastOneFile() async throws {
        let items = [
            BackupWorld.manifestItem(UUID(), kind: "files", extra: ["files": [["path": "/Users/x/a.txt"]]]),
            BackupWorld.manifestItem(UUID(), kind: "files", extra: ["files": [["path": "relative/a.txt"]]]),
            BackupWorld.manifestItem(UUID(), kind: "files", extra: ["files": [["path": "/ok/a"], ["path": "../b"]]]),
            BackupWorld.manifestItem(UUID(), kind: "files", extra: ["files": []]),
            BackupWorld.manifestItem(UUID(), kind: "files"),
        ]
        let plan = try await world.plan(try world.craft(manifest: BackupWorld.manifest(items: items)))
        #expect(plan.items.map(\.content) == [.files([URL(fileURLWithPath: "/Users/x/a.txt")])])
        #expect(plan.unreadable == 4)
    }

    @Test func anImageMustBeAPNGAndIsHashedFromItsBytes() async throws {
        let png = UUID(), notPNG = UUID(), jpeg = UUID(), truncated = UUID()
        let jpegData = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3, pixelsHigh: 3, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            .representation(using: .jpeg, properties: [:])!
        let url = try world.craft(
            manifest: BackupWorld.manifest(items: [png, notPNG, jpeg, truncated].map { BackupWorld.manifestItem($0, kind: "image") }),
            entries: [
                (BackupWorld.payload(png, "png"), world.firstPNG, 0o100644),
                (BackupWorld.payload(notPNG, "png"), Data("this is not an image".utf8), 0o100644),
                (BackupWorld.payload(jpeg, "png"), jpegData, 0o100644),
                (BackupWorld.payload(truncated, "png"), world.firstPNG.prefix(20), 0o100644),
            ]
        )

        let plan = try await world.plan(url)

        let name = world.firstPNG.sha256Hex + ".png"
        #expect(plan.items.map(\.content) == [.image(ClipboardImage(fileName: name, pixelWidth: 2, pixelHeight: 3, byteCount: world.firstPNG.count))])
        #expect(plan.items.first?.contentHash == ClipboardContent.hash(of: plan.items[0].content))
        #expect(plan.unreadable == 3)
        // Only the readable image was written, under its own hash.
        #expect(try restoredFiles() == [name])
        #expect(try Data(contentsOf: world.restoredImages.appending(path: name)) == world.firstPNG)
    }

    @Test func aDateInTheFutureIsHeldAtNow() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entry = textEntry("tương lai", extra: ["copiedAt": 9_999_999_999.0])
        let past = textEntry("quá khứ", extra: ["copiedAt": 1_000_000_000.25])
        let url = try world.craft(manifest: BackupWorld.manifest(items: [entry.item, past.item]), entries: entry.payloads + past.payloads)

        let plan = try await world.plan(url, now: now)

        #expect(plan.items.map(\.copiedAt) == [now, Date(timeIntervalSince1970: 1_000_000_000.25)])
    }

    @Test func aTextWithoutACodeAnswerGetsOneAndAnAnswerInTheFileIsKept() async throws {
        let none = textEntry(BackupWorld.swiftCode)
        let marked = textEntry("hello world", extra: ["code": "python"])
        let prose = textEntry("Hôm nay trời đẹp quá.")
        let url = try world.craft(
            manifest: BackupWorld.manifest(items: [none.item, marked.item, prose.item]), entries: none.payloads + marked.payloads + prose.payloads
        )

        let plan = try await world.plan(url)

        #expect(plan.items.map(\.codeDetection) == [.code(.swift), .code(.python), .notCode])
    }

    @Test func aLanguageFromALaterVersionReadsAsCodeInGeneral() async throws {
        let entry = textEntry("x", extra: ["code": "brainfuck"])
        let url = try world.craft(manifest: BackupWorld.manifest(items: [entry.item]), entries: entry.payloads)
        #expect(try await world.plan(url).items.first?.codeDetection == .code(.generic))
    }

    @Test func theSecretFlagIsReadOnlyAsTrue() async throws {
        let secret = textEntry("bí mật", extra: ["sensitive": true])
        let plain = textEntry("công khai", extra: ["sensitive": false])
        let unmarked = textEntry("không đánh dấu")
        let url = try world.craft(
            manifest: BackupWorld.manifest(items: [secret.item, plain.item, unmarked.item]),
            entries: secret.payloads + plain.payloads + unmarked.payloads
        )
        #expect(try await world.plan(url).items.map(\.sensitive) == [true, nil, nil])
    }

    // MARK: Boards of the file

    @Test func aBoardWithAnOddIconOrColourGetsTheDefaultsAndAnEmptyNameIsDropped() async throws {
        let one = textEntry("một")
        let id = one.item["id"] as! String
        let boards: [[String: Any]] = [
            ["name": "  Việc  ", "icon": "briefcase", "color": "teal", "items": [id, UUID().uuidString]],
            ["name": "Lạ", "icon": "../etc/passwd", "color": "ultraviolet", "items": []],
            ["name": "   ", "icon": "star", "items": [id]],
            ["name": "Số", "icon": 7, "color": 3, "items": []],
        ]
        let url = try world.craft(manifest: BackupWorld.manifest(items: [one.item], boards: boards), entries: one.payloads)

        let plan = try await world.plan(url)

        let hash = ClipboardContent.hash(of: .text("một"))
        #expect(plan.boards == [
            ClipboardRestorePlan.Board(name: "Việc", systemImage: "briefcase", color: .teal, itemHashes: [hash]),
            ClipboardRestorePlan.Board(name: "Lạ", systemImage: "tray.full", color: .accent, itemHashes: []),
            ClipboardRestorePlan.Board(name: "Số", systemImage: "tray.full", color: .accent, itemHashes: []),
        ])
    }

    // MARK: Duplicates

    @Test func anItemWeAlreadyHaveIsCountedAndNotAddedOrWritten() async throws {
        let (url, _) = try await world.export(ClipboardBackupOptions(skipSensitive: false))
        let known = Set([world.item("text"), world.item("image"), world.item("link")].map(\.contentHash))

        let plan = try await world.plan(url, known: known)

        #expect(plan.items.count == 7 && plan.duplicates == 3 && plan.unreadable == 0)
        #expect(try restoredFiles() == [world.secondPNG.sha256Hex + ".png"])
    }

    @Test func theSameItemTwiceInOneFileIsAddedOnce() async throws {
        let first = textEntry("lặp"), second = textEntry("lặp")
        let url = try world.craft(
            manifest: BackupWorld.manifest(items: [first.item, second.item]), entries: first.payloads + second.payloads
        )
        let plan = try await world.plan(url)
        #expect(plan.items.count == 1 && plan.duplicates == 1)
    }

    // MARK: Files

    @Test func aFileThatStillExistsKeepsItsOwnPathSoItsHashDoesNotChange() async throws {
        let (url, _) = try await world.export(ClipboardBackupOptions(skipSensitive: false))
        let plan = try await world.plan(url)
        let files = try #require(plan.items.first { $0.content.kind == .file })
        #expect(files.content == world.item("files").content)
        #expect(files.contentHash == world.item("files").contentHash)
    }

    @Test func aFileThatMovedIsFoundThroughItsBookmark() async throws {
        let (url, _) = try await world.export(ClipboardBackupOptions(skipSensitive: false))
        let moved = world.file("moved-away.txt")
        try FileManager.default.moveItem(at: world.presentFile, to: moved)

        let plan = try await world.plan(url)

        guard case .files(let urls) = try #require(plan.items.first { $0.content.kind == .file }).content else {
            Issue.record("expected a file item")
            return
        }
        #expect(urls.count == 2)
        #expect(urls[0].resolvingSymlinksInPath().path == moved.resolvingSymlinksInPath().path)
        // The one that was never there keeps the path it had.
        #expect(urls[1] == world.missingFile)
    }

    @Test func aFileThatVanishedKeepsItsPath() async throws {
        let (url, _) = try await world.export(ClipboardBackupOptions(skipSensitive: false))
        try FileManager.default.removeItem(at: world.presentFile)

        let plan = try await world.plan(url)

        #expect(try #require(plan.items.first { $0.content.kind == .file }).content == .files([world.presentFile, world.missingFile]))
    }

    // MARK: Progress

    @Test func progressGoesUpToOne() async throws {
        let (url, _) = try await world.export(ClipboardBackupOptions(skipSensitive: false))
        let progress = ClipboardBackupWriterTests.Progress()

        _ = try await world.plan(url, progress: { progress.record($0) })

        let values = progress.all
        #expect(values.last == 1)
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func cancellingStopsTheReadAndWritesNoMoreImages() async throws {
        let (url, _) = try await world.export(ClipboardBackupOptions(skipSensitive: false))
        let task = Task {
            try await world.plan(url, progress: { _ in withUnsafeCurrentTask { $0?.cancel() } })
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try restoredFiles().count <= 1)
    }
}
