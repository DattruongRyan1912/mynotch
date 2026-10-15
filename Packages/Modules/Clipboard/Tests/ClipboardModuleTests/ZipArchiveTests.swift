import Foundation
import Testing
@testable import ClipboardModule

/// The zip reader and writer the backup file is made of: what they write and read back, what other programs' archives look like
/// to them, and every way an archive can be unsafe, damaged or too big, which must be refused before anything is used.
@Suite final class ZipArchiveTests {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "ZipArchiveTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func file(_ name: String = "archive.zip") -> URL {
        directory.appending(path: name)
    }

    typealias Entry = (name: String, data: Data, mode: UInt16)

    static func entry(_ name: String, _ data: Data = Data("x".utf8), mode: UInt16 = 0o100644) -> Entry {
        (name, data, mode)
    }

    /// Writes an archive holding `entries` in order and returns its file.
    @discardableResult
    func write(_ entries: [Entry], to name: String = "archive.zip") throws -> URL {
        let url = file(name)
        let writer = try ZipWriter(url: url)
        for entry in entries { try writer.add(name: entry.name, data: entry.data, mode: entry.mode) }
        try writer.finish()
        return url
    }

    func read(_ url: URL, limits: ZipLimits = .unlimited) throws -> ZipReader {
        try ZipReader(url: url, limits: limits)
    }

    /// Bytes that look random and do not shrink, the same for the same count.
    static func pattern(_ count: Int) -> Data {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        return Data((0..<count).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return UInt8(truncatingIfNeeded: state >> 33)
        })
    }

    // MARK: Writing and reading back

    @Test func whatIsWrittenIsReadBackEntryByEntry() throws {
        let text = Data(String(repeating: "Xin chào thế giới. ", count: 200).utf8)
        let random = Self.pattern(5_000)
        let url = try write([
            Self.entry("manifest.json", Data("{}".utf8)), Self.entry("items/a.txt", text), Self.entry("items/b.png", random),
            Self.entry("empty", Data()), Self.entry("ghi chú/ảnh đẹp.txt", Data("ngắn".utf8)),
        ])

        let reader = try read(url)

        #expect(reader.entries.map(\.name) == ["manifest.json", "items/a.txt", "items/b.png", "empty", "ghi chú/ảnh đẹp.txt"])
        #expect(reader.entries.map(\.size) == [2, text.count, 5_000, 0, 6])
        for (entry, expected) in zip(reader.entries, [Data("{}".utf8), text, random, Data(), Data("ngắn".utf8)]) {
            #expect(try reader.data(of: entry) == expected)
        }
        #expect(try reader.data(named: "items/a.txt") == text)
        #expect(try reader.data(named: "nothing") == nil)
    }

    @Test func aRepeatingEntryIsDeflatedAndOneThatWillNotShrinkIsStored() throws {
        let text = Data(String(repeating: "abc ", count: 5_000).utf8)
        let url = try write([Self.entry("text", text), Self.entry("noise", Self.pattern(3_000)), Self.entry("tiny", Data("a".utf8))])

        let entries = try read(url).entries

        #expect(entries[0].method == 8 && entries[0].compressedSize < 200)
        #expect(entries[1].method == 0 && entries[1].compressedSize == 3_000)
        #expect(entries[2].method == 0)
    }

    @Test func anArchiveWithNoEntriesReadsAsEmpty() throws {
        let url = try write([])
        #expect(try read(url).entries.isEmpty)
    }

    @Test func aLargeEntryComesBackWhole() throws {
        let big = Data((0..<2_000_000).map { UInt8(truncatingIfNeeded: ($0 / 7) &+ ($0 % 13)) })
        let url = try write([Self.entry("big", big)])
        #expect(try read(url).data(named: "big") == big)
    }

    @Test func theNamesAreStoredAsUTF8AndTheModeIsKept() throws {
        let url = try write([Self.entry("tên.txt", mode: 0o100600)])
        let entry = try #require(read(url).entries.first)
        #expect(entry.name == "tên.txt" && entry.mode == 0o100600)
    }

    @Test func theChecksumIsTheStandardCRC32() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(CRC32.checksum(Data()) == 0)
    }

    // MARK: Archives made by other programs

    func sample(_ data: Data) throws -> URL {
        let url = file("sample.zip")
        try data.write(to: url)
        return url
    }

    @Test func anArchiveFromInfoZipIsRead() throws {
        let reader = try read(sample(ZipSamples.infoZip))
        let sentence = String(repeating: "Xin chào, đây là một đoạn văn bản được lặp lại để nén được. ", count: 40)

        // The two folders are not entries.
        #expect(reader.entries.map(\.name) == ["src/empty.txt", "src/b.txt", "src/items/a.txt"])
        #expect(try reader.data(named: "src/empty.txt") == Data())
        #expect(try reader.data(named: "src/b.txt") == Data("ngắn".utf8))
        #expect(try reader.data(named: "src/items/a.txt") == Data(sentence.utf8))
        #expect(reader.entries.map(\.method) == [0, 0, 8])
    }

    @Test func anArchiveFromFinderWithDataDescriptorsAndMacOSXEntriesIsRead() throws {
        let reader = try read(sample(ZipSamples.dittoZip))
        let sentence = String(repeating: "Xin chào, đây là một đoạn văn bản được lặp lại để nén được. ", count: 40)

        #expect(try reader.data(named: "b.txt") == Data("ngắn".utf8))
        #expect(try reader.data(named: "items/a.txt") == Data(sentence.utf8))
        #expect(try reader.data(named: "empty.txt") == Data())
        #expect(reader.entries.contains { $0.name == "__MACOSX/._b.txt" })
        for entry in reader.entries { _ = try reader.data(of: entry) }
    }

    @Test func theArchivesThisWritesAreValidForTheStrictChecks() throws {
        // The writer sets what the reader demands of every archive, so a round trip is also a check of the reader's rules.
        let url = try write([Self.entry("a"), Self.entry("b/c", Self.pattern(300))])
        let reader = try read(url, limits: ZipLimits(perEntry: 300, total: 301))
        #expect(reader.entries.count == 2)
    }

    // MARK: Names

    @Test func aNameThatLeavesTheFolderIsUnsafe() {
        for name in ["../x", "a/../../x", "a/..", "..", "a/../b", "..\\x", "a\\..\\x", "/etc/passwd", "\\share\\x", "C:\\x", "c:/x", "a\u{0}b", "", "a\nb"] {
            #expect(ZipEntryName.problem(with: name) != nil, "\(name.debugDescription) should be unsafe")
        }
        #expect(ZipEntryName.problem(with: String(repeating: "a", count: 600)) != nil)
    }

    @Test func ordinaryNamesAreSafe() {
        for name in ["manifest.json", "items/00000000-0000-0000-0000-000000000001.txt", "a..b/c", "..a", "a../b", ".../x", "./x", "ghi chú/ảnh.png", "__MACOSX/._a", "dir/"] {
            #expect(ZipEntryName.problem(with: name) == nil, "\(name.debugDescription) should be safe")
        }
    }

    @Test func anArchiveWithAnUnsafeNameIsRefusedWhole() throws {
        for name in ["../x", "a/../../x", "/etc/passwd", "C:\\x", "..\\x"] {
            let url = try write([Self.entry("manifest.json"), Self.entry(name)])
            #expect(throws: ZipError.unsafeName(name)) { try read(url) }
        }
    }

    @Test func aSymbolicLinkInsideTheArchiveIsRefused() throws {
        let url = try write([Self.entry("manifest.json"), Self.entry("link", Data("/etc/passwd".utf8), mode: 0o120755)])
        #expect(throws: ZipError.notARegularFile("link")) { try read(url) }
    }

    @Test func otherSpecialFilesAreRefusedToo() throws {
        for mode: UInt16 in [0o020644, 0o060644, 0o010644, 0o140644] {
            let url = try write([Self.entry("special", Data(), mode: mode)])
            #expect(throws: ZipError.notARegularFile("special")) { try read(url) }
        }
    }

    @Test func aFolderEntryIsFineAndIsNotListed() throws {
        let url = try write([Self.entry("dir/", Data(), mode: 0o040755), Self.entry("dir/a")])
        #expect(try read(url).entries.map(\.name) == ["dir/a"])
    }

    @Test func aFolderEntryThatCarriesDataIsRefused() throws {
        let url = try write([Self.entry("dir/", Data("data".utf8), mode: 0o040755)])
        #expect(throws: ZipError.corrupt("dir/")) { try read(url) }
    }

    @Test func twoEntriesWithOneNameAreRefused() throws {
        let url = try write([Self.entry("a"), Self.entry("b"), Self.entry("a", Data("other".utf8))])
        #expect(throws: ZipError.duplicateName("a")) { try read(url) }
    }

    // MARK: Not an archive, or not one this reads

    @Test func somethingThatIsNotAnArchiveIsRefused() throws {
        for data in [Data(), Data("PK".utf8), Data(String(repeating: "hello ", count: 100).utf8), Data(count: 22), Data(count: 70_000)] {
            let url = try sample(data)
            #expect(throws: ZipError.notAnArchive) { try read(url) }
        }
    }

    @Test func aFileThatIsMissingIsAnIOError() {
        #expect(throws: CocoaError.self) { try read(file("missing.zip")) }
    }

    @Test func aTruncatedArchiveIsRefused() throws {
        let whole = try Data(contentsOf: write([Self.entry("a", Self.pattern(500)), Self.entry("b", Self.pattern(500))]))
        for length in [whole.count - 1, whole.count - 30, whole.count / 2, 100, 30] {
            let url = try sample(whole.prefix(length))
            #expect(throws: ZipError.self) { try read(url) }
        }
    }

    // MARK: Patched archives

    /// The offsets of the first central-directory record and of the first local header, in `data`.
    func firstRecords(_ data: Data) throws -> (central: Int, local: Int) {
        let central = try #require(find([0x50, 0x4B, 0x01, 0x02], in: data))
        let local = try #require(find([0x50, 0x4B, 0x03, 0x04], in: data))
        return (central, local)
    }

    func find(_ signature: [UInt8], in data: Data, from start: Int = 0) -> Int? {
        let bytes = [UInt8](data)
        guard bytes.count >= signature.count else { return nil }
        return (start...(bytes.count - signature.count)).first { Array(bytes[$0..<$0 + signature.count]) == signature }
    }

    func patched(_ url: URL, _ edits: [(offset: Int, bytes: [UInt8])]) throws -> URL {
        var data = try Data(contentsOf: url)
        for edit in edits {
            for (index, byte) in edit.bytes.enumerated() { data[edit.offset + index] = byte }
        }
        return try sample(data)
    }

    func le32(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
    }

    @Test func anEncryptedEntryIsRefused() throws {
        let url = try write([Self.entry("a")])
        let central = try firstRecords(Data(contentsOf: url)).central
        let patched = try patched(url, [(central + 8, [0x01])])
        #expect(throws: ZipError.unsupported("a")) { try read(patched) }
    }

    @Test func anUnknownMethodIsRefused() throws {
        let url = try write([Self.entry("a")])
        let central = try firstRecords(Data(contentsOf: url)).central
        let patched = try patched(url, [(central + 10, [14])])
        #expect(throws: ZipError.unsupported("a")) { try read(patched) }
    }

    @Test func zip64MarkersAreRefusedBecauseNoBackupNeedsThem() throws {
        let url = try write([Self.entry("a")])
        let central = try firstRecords(Data(contentsOf: url)).central
        for offset in [20, 24, 42] {
            let patched = try patched(url, [(central + offset, [0xFF, 0xFF, 0xFF, 0xFF])])
            #expect(throws: ZipError.unsupported("a")) { try read(patched) }
        }
    }

    @Test func aStoredEntryWhoseTwoSizesDifferIsRefused() throws {
        let url = try write([Self.entry("a", Data("hello".utf8))])
        let central = try firstRecords(Data(contentsOf: url)).central
        let patched = try patched(url, [(central + 24, le32(9))])
        #expect(throws: ZipError.corrupt("a")) { try read(patched) }
    }

    @Test func aFlippedByteIsFoundByTheChecksum() throws {
        let url = try write([Self.entry("a", Data("hello world".utf8))])
        let local = try firstRecords(Data(contentsOf: url)).local
        let patched = try patched(url, [(local + 30 + 1, [0x7A])])
        let reader = try read(patched)
        #expect(throws: ZipError.corrupt("a")) { try reader.data(named: "a") }
    }

    @Test func aLocalHeaderThatNamesAnotherFileIsRefusedOnReading() throws {
        let url = try write([Self.entry("aaa", Data("hello".utf8))])
        let local = try firstRecords(Data(contentsOf: url)).local
        let patched = try patched(url, [(local + 30, [0x62])])
        let reader = try read(patched)
        #expect(throws: ZipError.corrupt("aaa")) { try reader.data(named: "aaa") }
    }

    @Test func anOffsetOutsideTheFileIsRefused() throws {
        let url = try write([Self.entry("a")])
        let central = try firstRecords(Data(contentsOf: url)).central
        let patched = try patched(url, [(central + 42, le32(9_999_999))])
        #expect(throws: ZipError.corrupt("a")) { try read(patched) }
    }

    @Test func aCompressedSizeBeyondTheFileIsRefused() throws {
        let url = try write([Self.entry("a", Data(String(repeating: "abc ", count: 1_000).utf8))])
        let central = try firstRecords(Data(contentsOf: url)).central
        let patched = try patched(url, [(central + 20, le32(90_000_000))])
        let outcome = Result { try read(patched).data(named: "a") }
        guard case .failure(let error) = outcome else {
            Issue.record("a size beyond the file was accepted")
            return
        }
        #expect(error as? ZipError == .corrupt("a"))
    }

    @Test func aDeflatedEntryThatSaysItIsSmallerThanItIsIsRefusedWithoutBeingExpanded() throws {
        // 10 MB of zeros deflate to a few kilobytes: the headers claim 100 bytes, so reading must stop at the claim.
        let url = try write([Self.entry("bomb", Data(count: 10_000_000))])
        let data = try Data(contentsOf: url)
        let (central, local) = try firstRecords(data)
        let patched = try patched(url, [(central + 24, le32(100)), (local + 22, le32(100))])

        let reader = try read(patched)

        #expect(reader.entries.first?.size == 100)
        #expect(throws: ZipError.corrupt("bomb")) { try reader.data(named: "bomb") }
    }

    @Test func aDeflatedEntryThatSaysItIsBiggerThanItIsIsRefused() throws {
        let url = try write([Self.entry("a", Data(String(repeating: "abc ", count: 1_000).utf8))])
        let data = try Data(contentsOf: url)
        let (central, local) = try firstRecords(data)
        let patched = try patched(url, [(central + 24, le32(9_000)), (local + 22, le32(9_000))])
        let reader = try read(patched)
        #expect(throws: ZipError.corrupt("a")) { try reader.data(named: "a") }
    }

    // MARK: Limits

    @Test func anEntryOverTheLimitIsRefusedBeforeAnythingIsRead() throws {
        let url = try write([Self.entry("a", Self.pattern(100)), Self.entry("big", Self.pattern(1_001))])
        #expect(throws: ZipError.entryTooLarge(name: "big", size: 1_001)) {
            try read(url, limits: ZipLimits(perEntry: 1_000, total: 10_000))
        }
    }

    @Test func anEntryExactlyAtTheLimitIsAccepted() throws {
        let url = try write([Self.entry("a", Self.pattern(1_000))])
        #expect(try read(url, limits: ZipLimits(perEntry: 1_000, total: 1_000)).entries.count == 1)
    }

    @Test func entriesThatTogetherPassTheTotalAreRefused() throws {
        let url = try write([Self.entry("a", Self.pattern(600)), Self.entry("b", Self.pattern(600))])
        #expect(throws: ZipError.archiveTooLarge(total: 1_200)) {
            try read(url, limits: ZipLimits(perEntry: 1_000, total: 1_199))
        }
        #expect(try read(url, limits: ZipLimits(perEntry: 1_000, total: 1_200)).entries.count == 2)
    }

    @Test func theSizeClaimedByAHeaderIsWhatCountsEvenWhenTheDataIsSmaller() throws {
        // An archive claiming 4 GB in one entry is refused by its header, however small the file is.
        let url = try write([Self.entry("a", Self.pattern(500))])
        let central = try firstRecords(Data(contentsOf: url)).central
        let patched = try patched(url, [(central + 24, le32(0xFFFF_FF00))])
        #expect(throws: ZipError.self) { try read(patched, limits: ZipLimits(perEntry: 50_000_000, total: 2_147_483_648)) }
    }

    @Test func theWriterRefusesWhatAZip64WouldBeNeededFor() throws {
        let writer = try ZipWriter(url: file())
        #expect(throws: ZipError.tooManyEntries) {
            for index in 0...65_535 { try writer.add(name: "e\(index)", data: Data()) }
        }
    }
}
