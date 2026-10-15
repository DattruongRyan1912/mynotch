import CryptoKit
import Foundation
import MyNotchTestSupport
import Testing
@testable import ClipboardModule

/// What a locked board keeps on disk: the file (a readable header with the board's id, method and item count, then the sealed
/// bytes) and the payload inside the seal (the items and their image bytes).
@Suite struct ClipboardVaultFormatTests {
    static let boardID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    static func text(_ text: String, at offset: TimeInterval = 0) -> ClipboardItem {
        let content = ClipboardContent.text(text)
        return ClipboardItem(
            id: UUID(), content: content, contentHash: ClipboardContent.hash(of: content), copiedAt: start + offset,
            sourceBundleID: "com.apple.Safari", sourceAppName: "Safari"
        )
    }

    static func image(_ seed: String) -> (item: ClipboardItem, bytes: Data) {
        let bytes = Data(seed.utf8)
        let content = ClipboardContent.image(ClipboardImage(fileName: bytes.sha256Hex + ".png", pixelWidth: 2, pixelHeight: 3, byteCount: bytes.count))
        let item = ClipboardItem(
            id: UUID(), content: content, contentHash: ClipboardContent.hash(of: content), copiedAt: start, sourceBundleID: nil, sourceAppName: nil
        )
        return (item, bytes)
    }

    func folder() -> URL {
        let url = ScratchFolders.shared.reserve("vault")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Payload

    @Test func aPayloadRoundTripsItemsAndImages() throws {
        let picture = Self.image("png bytes 1")
        let other = Self.image("png bytes 2")
        let contents = ClipboardVaultPayload.Contents(
            items: [Self.text("mật khẩu ngân hàng"), picture.item, Self.text("hai", at: 5), other.item],
            images: [picture.item.imageName!: picture.bytes, other.item.imageName!: other.bytes]
        )
        let decoded = try ClipboardVaultPayload.decode(ClipboardVaultPayload.encode(contents))
        #expect(decoded == contents)
    }

    @Test func anEmptyPayloadRoundTrips() throws {
        let contents = ClipboardVaultPayload.Contents(items: [], images: [:])
        #expect(try ClipboardVaultPayload.decode(ClipboardVaultPayload.encode(contents)) == contents)
    }

    @Test func theItemsKeepTheirOrderAndDates() throws {
        let items = (0..<20).map { Self.text("mục \($0)", at: Double($0) + 0.25) }
        let decoded = try ClipboardVaultPayload.decode(ClipboardVaultPayload.encode(.init(items: items, images: [:])))
        #expect(decoded.items == items)
    }

    @Test func anImageWhoseBytesAreMissingIsRefused() throws {
        let picture = Self.image("png bytes 1")
        #expect(throws: ClipboardVaultError.damaged) {
            _ = try ClipboardVaultPayload.encode(.init(items: [picture.item], images: [:]))
        }
    }

    @Test func imageBytesThatAreNotTheirNamesHashAreRefused() throws {
        let picture = Self.image("png bytes 1")
        var data = try ClipboardVaultPayload.encode(.init(items: [picture.item], images: [picture.item.imageName!: picture.bytes]))
        data[data.count - 1] ^= 0x01
        #expect(throws: ClipboardVaultError.damaged) { _ = try ClipboardVaultPayload.decode(data) }
    }

    @Test func anImageNamedToLeaveItsFolderIsRefused() throws {
        // A payload made by someone who knows its password (a backup passed around) must not write outside `images/`.
        let evil = Data("evil".utf8)
        let name = "../../" + evil.sha256Hex + ".png"
        let content = ClipboardContent.image(ClipboardImage(fileName: name, pixelWidth: 1, pixelHeight: 1, byteCount: 4))
        let item = ClipboardItem(
            id: UUID(), content: content, contentHash: "h", copiedAt: Self.start, sourceBundleID: nil, sourceAppName: nil
        )
        #expect(throws: ClipboardVaultError.damaged) { _ = try ClipboardVaultPayload.encode(.init(items: [item], images: [name: evil])) }
    }

    @Test(arguments: [
        Data(),
        Data([0, 0]),
        Data([0, 0, 0, 5]),
        Data([0xFF, 0xFF, 0xFF, 0xFF, 1, 2, 3]),
        Data([0, 0, 0, 2, 0x7B, 0x7D]),
        Data([0, 0, 0, 14] + Array(#"{"items":null}"#.utf8)),
    ])
    func malformedPayloadsAreRefused(data: Data) {
        #expect(throws: ClipboardVaultError.damaged) { _ = try ClipboardVaultPayload.decode(data) }
    }

    @Test func aPayloadWithTrailingBytesIsRefused() throws {
        var data = try ClipboardVaultPayload.encode(.init(items: [Self.text("x")], images: [:]))
        data.append(0)
        #expect(throws: ClipboardVaultError.damaged) { _ = try ClipboardVaultPayload.decode(data) }
    }

    // MARK: Header and file

    func envelope(_ method: ClipboardLockMethod = .password, count: Int = 3) -> ClipboardVaultEnvelope {
        ClipboardVaultEnvelope(
            boardID: Self.boardID, method: method, itemCount: count,
            derivation: method == .password ? .init(iterations: 600_000, salt: Data(repeating: 9, count: 32)) : nil,
            wrappedKey: method == .password ? Data(repeating: 5, count: 60) : nil
        )
    }

    @Test func aFileRoundTrips() throws {
        let file = ClipboardVaultFile(envelope: envelope(), sealed: Data((0..<2000).map { UInt8($0 % 251) }))
        #expect(try ClipboardVaultFile.decode(file.encoded()) == file)
        let touch = ClipboardVaultFile(envelope: envelope(.touchID), sealed: Data([1, 2, 3]))
        #expect(try ClipboardVaultFile.decode(touch.encoded()) == touch)
    }

    @Test func theHeaderIsOneReadableLineWithNoSecrets() throws {
        let file = ClipboardVaultFile(envelope: envelope(), sealed: Data([1, 2, 3]))
        let encoded = file.encoded()
        let newline = try #require(encoded.firstIndex(of: 0x0A))
        let header = String(decoding: encoded[..<newline], as: UTF8.self)
        #expect(header.contains("\"itemCount\":3"))
        #expect(header.contains(Self.boardID.uuidString))
        #expect(header.contains("\"method\":\"password\""))
        #expect(!header.contains("name") && !header.contains("Safari"))
        #expect(encoded[(newline + 1)...] == Data([1, 2, 3]))
    }

    @Test func aFileIsWrittenPrivatelyAndRead() throws {
        let url = folder().appending(path: "a.vault")
        let file = ClipboardVaultFile(envelope: envelope(), sealed: Data(repeating: 7, count: 500))
        try file.write(to: url)

        let permissions = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        #expect(try ClipboardVaultFile.read(at: url) == file)
        #expect(try ClipboardVaultFile.readHeader(at: url) == file.envelope)
    }

    @Test func replacingAFileKeepsItPrivateAndLeavesNoTemporaryFile() throws {
        let directory = folder()
        let url = directory.appending(path: "a.vault")
        try ClipboardVaultFile(envelope: envelope(count: 1), sealed: Data([1])).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path(percentEncoded: false))

        let second = ClipboardVaultFile(envelope: envelope(count: 2), sealed: Data([2]))
        try second.write(to: url)

        let permissions = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        #expect(try ClipboardVaultFile.read(at: url) == second)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)) == ["a.vault"])
    }

    @Test func theHeaderCanBeReadWithoutReadingTheRest() throws {
        let url = folder().appending(path: "big.vault")
        try ClipboardVaultFile(envelope: envelope(count: 7), sealed: Data(repeating: 1, count: 3_000_000)).write(to: url)
        #expect(try ClipboardVaultFile.readHeader(at: url).itemCount == 7)
    }

    @Test func aFileThatIsNotAVaultIsRefused() throws {
        let directory = folder()
        let url = directory.appending(path: "x.vault")
        for content in [Data(), Data("hello".utf8), Data("{}\n".utf8), Data("not json\n1234".utf8), Data(repeating: 0x41, count: 40_000)] {
            try content.write(to: url)
            #expect(throws: ClipboardVaultError.self) { _ = try ClipboardVaultFile.read(at: url) }
            #expect(throws: ClipboardVaultError.self) { _ = try ClipboardVaultFile.readHeader(at: url) }
        }
    }

    @Test func aHeaderThatContradictsItselfIsRefused() throws {
        func header(_ edit: (inout ClipboardVaultEnvelope) -> Void) throws -> Data {
            var value = envelope()
            edit(&value)
            return ClipboardVaultFile(envelope: value, sealed: Data([1])).encoded()
        }
        // A password lock with no derivation or wrapped key, a Touch ID lock that has them, a negative or absurd count.
        for data in [
            try header { $0.derivation = nil },
            try header { $0.wrappedKey = nil },
            try header { $0.method = .touchID },
            try header { $0.itemCount = -1 },
            try header { $0.itemCount = ClipboardVaultPayload.maxItems + 1 },
            try header { $0.format = "other" },
            try header { $0.version = 0 },
        ] {
            #expect(throws: ClipboardVaultError.damaged) { _ = try ClipboardVaultFile.decode(data) }
        }
    }

    @Test func aNewerVersionIsToldApart() throws {
        var value = envelope()
        value.version = ClipboardVaultEnvelope.currentVersion + 1
        let data = ClipboardVaultFile(envelope: value, sealed: Data([1])).encoded()
        #expect(throws: ClipboardVaultError.unsupportedVersion(ClipboardVaultEnvelope.currentVersion + 1)) {
            _ = try ClipboardVaultFile.decode(data)
        }
    }

    @Test func aSummaryIsReadEvenFromAFileThisVersionCannotOpen() throws {
        let url = folder().appending(path: "newer.vault")
        var value = envelope(count: 9)
        value.version = 7
        try ClipboardVaultFile(envelope: value, sealed: Data([1])).write(to: url)
        let summary = try #require(ClipboardVaultFile.summary(at: url))
        #expect(summary.boardID == Self.boardID)
        #expect(summary.itemCount == 9)
        #expect(summary.method == .password)
    }

    @Test func noSummaryForGarbage() throws {
        let url = folder().appending(path: "x.vault")
        try Data("garbage".utf8).write(to: url)
        #expect(ClipboardVaultFile.summary(at: url) == nil)
        #expect(ClipboardVaultFile.summary(at: folder().appending(path: "missing.vault")) == nil)
    }
}

extension ClipboardItem {
    var imageName: String? {
        if case .image(let image) = content { image.fileName } else { nil }
    }
}

/// The folder the vault files live in.
@Suite struct ClipboardVaultFilesTests {
    func files() -> ClipboardVaultFiles {
        ClipboardVaultFiles(directory: ScratchFolders.shared.reserve("vault-files").appending(path: "vault", directoryHint: .isDirectory))
    }

    func vault(_ id: UUID, count: Int = 1) -> ClipboardVaultFile {
        ClipboardVaultFile(
            envelope: ClipboardVaultEnvelope(
                boardID: id, method: .password, itemCount: count,
                derivation: .init(iterations: 600_000, salt: Data(repeating: 1, count: 32)), wrappedKey: Data(repeating: 2, count: 60)
            ),
            sealed: Data([1, 2, 3])
        )
    }

    @Test func theFolderIsMadePrivateWhetherItWasThereOrNot() throws {
        let files = files()
        try files.prepare()
        let mode = { try FileManager.default.attributesOfItem(atPath: files.directory.path(percentEncoded: false))[.posixPermissions] as? Int }
        #expect(try mode() == 0o700)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: files.directory.path(percentEncoded: false))
        try files.prepare()
        #expect(try mode() == 0o700)
    }

    @Test func theSummariesAreOfTheFilesThatAreVaultsOfTheirOwnBoard() throws {
        let files = files()
        try files.prepare()
        let mine = UUID(), other = UUID()
        try vault(mine, count: 4).write(to: files.url(for: mine))
        // A file named for one board that says it is another's, a file with no header, and files that are not vaults at all.
        try vault(other).write(to: files.url(for: UUID()))
        try Data("rác".utf8).write(to: files.url(for: UUID()))
        try Data("x".utf8).write(to: files.directory.appending(path: "notes.txt"))
        try Data("x".utf8).write(to: files.directory.appending(path: "\(mine.uuidString).vault.unreadable-1"))

        #expect(files.summaries() == [ClipboardVaultFile.Summary(boardID: mine, method: .password, itemCount: 4)])
    }

    @Test func aMissingFolderHasNoSummaries() {
        #expect(files().summaries().isEmpty)
    }

    @Test func removingAFileThatIsNotThereIsFine() throws {
        let files = files()
        try files.prepare()
        let id = UUID()
        try files.remove(for: id)
        try vault(id).write(to: files.url(for: id))
        #expect(files.exists(for: id))
        try files.remove(for: id)
        #expect(!files.exists(for: id))
    }

    @Test func aFileThatCannotBeReadIsSetAsideNotDestroyed() throws {
        let files = files()
        try files.prepare()
        let id = UUID()
        try Data("hỏng".utf8).write(to: files.url(for: id))
        files.moveAside(for: id)
        #expect(!files.exists(for: id))
        let names = try FileManager.default.contentsOfDirectory(atPath: files.directory.path(percentEncoded: false))
        #expect(names.count == 1 && names[0].hasPrefix("\(id.uuidString).vault.unreadable-"))
        #expect(try Data(contentsOf: files.directory.appending(path: names[0])) == Data("hỏng".utf8))
    }
}
