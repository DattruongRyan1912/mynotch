import Compression
import Foundation

/// Why an archive was not used. The associated names are the entry's name as the archive spells it.
nonisolated enum ZipError: Error, Equatable {
    /// No end-of-archive record: not a zip file, or cut short.
    case notAnArchive
    /// Encryption, a method other than stored or deflated, zip64 or several disks.
    case unsupported(String)
    /// A name that could leave the folder it is unpacked into, or that is not a name at all.
    case unsafeName(String)
    case duplicateName(String)
    /// A symbolic link, device, pipe or socket: only plain files are used.
    case notARegularFile(String)
    case entryTooLarge(name: String, size: Int)
    case archiveTooLarge(total: Int)
    case tooManyEntries
    /// The headers disagree with each other or with the data, or the data does not match its checksum.
    case corrupt(String)
}

/// How much a reader accepts, checked against the sizes the headers claim before any data is read, and against the data as
/// it is expanded, so a header that lies cannot make it allocate more.
nonisolated struct ZipLimits: Sendable {
    var perEntry: Int
    var total: Int
    /// The size of the directory of entries, which is read whole before anything is checked.
    var directory: Int = 16 * 1024 * 1024

    static let unlimited = ZipLimits(perEntry: .max, total: .max, directory: .max)
}

/// One file of an archive. Folders are never listed.
nonisolated struct ZipEntry: Sendable, Equatable {
    let name: String
    /// 0 stored, 8 deflated.
    let method: UInt16
    let compressedSize: Int
    let size: Int
    let crc32: UInt32
    /// The UNIX mode the archive carries (type and permissions), 0 when it carries none.
    let mode: UInt16
    let localHeaderOffset: Int
}

/// What makes an entry name safe: it names a file inside the archive and nothing else.
nonisolated enum ZipEntryName {
    static let maxLength = 512

    /// nil when `name` is fine, otherwise why not. A name is unsafe when it is empty or very long, holds a control
    /// character, starts at the root (`/` or `\`) or with a drive (`C:`), or has a `..` part between `/` or `\`.
    static func problem(with name: String) -> String? {
        if name.isEmpty { return "empty" }
        if name.utf8.count > maxLength { return "long" }
        if name.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) { return "control character" }
        if name.hasPrefix("/") || name.hasPrefix("\\") { return "absolute" }
        let scalars = Array(name.unicodeScalars)
        if scalars.count >= 2, scalars[1] == ":", scalars[0].properties.isAlphabetic, scalars[0].isASCII { return "drive" }
        if name.split(whereSeparator: { $0 == "/" || $0 == "\\" }).contains("..") { return "parent folder" }
        return nil
    }
}

/// CRC-32 (the zip one), table driven.
nonisolated enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        (0..<8).reduce(UInt32(index)) { value, _ in value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
    }

    static func checksum(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { buffer in
            ~buffer.reduce(UInt32.max) { crc, byte in table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        }
    }
}

// MARK: - Writing

/// Writes a zip archive one entry at a time, so a large backup is never held in memory whole. Entries are deflated when that
/// makes them smaller and stored otherwise. The sizes it can write are those of a plain zip (no zip64): 65,535 entries,
/// 4 GB. It checks nothing about names or modes, since tests use it to make archives that are meant to be refused; the
/// backup writer only gives it names of its own.
nonisolated final class ZipWriter {
    private struct Record {
        let name: Data
        let method: UInt16
        let crc: UInt32
        let compressedSize: Int
        let size: Int
        let mode: UInt16
        let offset: Int
        let dosTime: UInt16
        let dosDate: UInt16
    }

    private let handle: FileHandle
    private var records: [Record] = []
    private var offset = 0

    /// Creates (or replaces) the file, readable by its owner only from the moment it exists: what goes in may be private.
    init(url: URL) throws {
        guard FileManager.default.createFile(
            atPath: url.path(percentEncoded: false), contents: nil, attributes: [.posixPermissions: 0o600]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        handle = try FileHandle(forWritingTo: url)
    }

    deinit {
        try? handle.close()
    }

    /// `compress: false` stores the data as it is, which saves the time of trying to shrink what is already compressed (a PNG).
    func add(name: String, data: Data, mode: UInt16 = 0o100644, modified: Date = .now, compress: Bool = true) throws {
        guard records.count < Int(UInt16.max) else { throw ZipError.tooManyEntries }
        let nameBytes = Data(name.utf8)
        guard nameBytes.count <= Int(UInt16.max), data.count <= Int(UInt32.max) else { throw ZipError.unsupported(name) }
        let deflated = compress ? ZipCompression.deflate(data) : nil
        let stored = deflated ?? data
        let (dosTime, dosDate) = Self.dosTimestamp(modified)
        let record = Record(
            name: nameBytes, method: deflated == nil ? 0 : 8, crc: CRC32.checksum(data), compressedSize: stored.count, size: data.count,
            mode: mode, offset: offset, dosTime: dosTime, dosDate: dosDate
        )
        guard offset + 30 + nameBytes.count + stored.count <= Int(UInt32.max) else { throw ZipError.unsupported(name) }
        var header = ZipBytes()
        header.append32(0x0403_4B50)
        header.append16(record.method == 0 ? 10 : 20)
        header.append16(0x0800)
        header.append16(record.method)
        header.append16(dosTime)
        header.append16(dosDate)
        header.append32(record.crc)
        header.append32(UInt32(record.compressedSize))
        header.append32(UInt32(record.size))
        header.append16(UInt16(nameBytes.count))
        header.append16(0)
        try handle.write(contentsOf: header.data + nameBytes)
        try handle.write(contentsOf: stored)
        offset += 30 + nameBytes.count + stored.count
        records.append(record)
    }

    /// Writes the directory of entries that ends the archive, and closes the file.
    func finish() throws {
        let directoryStart = offset
        var directory = ZipBytes()
        for record in records {
            directory.append32(0x0201_4B50)
            directory.append16(UInt16(3) << 8 | 20)
            directory.append16(record.method == 0 ? 10 : 20)
            directory.append16(0x0800)
            directory.append16(record.method)
            directory.append16(record.dosTime)
            directory.append16(record.dosDate)
            directory.append32(record.crc)
            directory.append32(UInt32(record.compressedSize))
            directory.append32(UInt32(record.size))
            directory.append16(UInt16(record.name.count))
            directory.append16(0)
            directory.append16(0)
            directory.append16(0)
            directory.append16(0)
            directory.append32(UInt32(record.mode) << 16)
            directory.append32(UInt32(record.offset))
            directory.data.append(record.name)
        }
        let directorySize = directory.data.count
        guard directoryStart + directorySize <= Int(UInt32.max) else { throw ZipError.unsupported("") }
        directory.append32(0x0605_4B50)
        directory.append16(0)
        directory.append16(0)
        directory.append16(UInt16(records.count))
        directory.append16(UInt16(records.count))
        directory.append32(UInt32(directorySize))
        directory.append32(UInt32(directoryStart))
        directory.append16(0)
        try handle.write(contentsOf: directory.data)
        try handle.close()
    }

    /// MS-DOS time and date, which have a two-second step and start in 1980.
    private static func dosTimestamp(_ date: Date) -> (time: UInt16, date: UInt16) {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = min(max((parts.year ?? 1980) - 1980, 0), 127)
        let time = (parts.hour ?? 0) << 11 | (parts.minute ?? 0) << 5 | (parts.second ?? 0) / 2
        let day = year << 9 | (parts.month ?? 1) << 5 | (parts.day ?? 1)
        return (UInt16(time), UInt16(day))
    }
}

// MARK: - Reading

/// Reads the files of a zip archive without unpacking it: the directory at the end is read and checked whole first (names,
/// kinds, sizes, limits), and each entry's data is read, expanded and checked against its checksum only when asked for,
/// into memory and never to disk, so nothing in an archive can name a place to write.
nonisolated final class ZipReader {
    private static let localHeaderSize = 30
    private static let endRecordSize = 22

    /// In archive order; folders left out.
    let entries: [ZipEntry]
    private let index: [String: ZipEntry]
    private let handle: FileHandle
    private let fileSize: Int

    /// Throws a `ZipError` for an archive that is not one, is unsafe, uses features this does not read or goes over
    /// `limits`; nothing of its data has been read by then. Throws the system's error for a file that cannot be opened.
    init(url: URL, limits: ZipLimits) throws {
        let handle = try FileHandle(forReadingFrom: url)
        let size = Int(try handle.seekToEnd())
        self.handle = handle
        fileSize = size
        let entries = try Self.readDirectory(handle: handle, fileSize: size, limits: limits)
        self.entries = entries
        // Names are unique by now, so the lookup keeps every entry.
        index = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0) })
    }

    deinit {
        try? handle.close()
    }

    /// The expanded data of `entry`, checked against its size and checksum.
    func data(of entry: ZipEntry) throws -> Data {
        let corrupt = ZipError.corrupt(entry.name)
        let header = try Self.read(handle, fileSize: fileSize, at: entry.localHeaderOffset, count: Self.localHeaderSize, name: entry.name)
        let bytes = ZipBytes(header)
        guard bytes.read32(at: 0) == 0x0403_4B50, bytes.read16(at: 8) == entry.method else { throw corrupt }
        let nameLength = Int(bytes.read16(at: 26)), extraLength = Int(bytes.read16(at: 28))
        let name = try Self.read(handle, fileSize: fileSize, at: entry.localHeaderOffset + Self.localHeaderSize, count: nameLength, name: entry.name)
        guard name == Data(entry.name.utf8) else { throw corrupt }
        let dataStart = entry.localHeaderOffset + Self.localHeaderSize + nameLength + extraLength
        let stored = try Self.read(handle, fileSize: fileSize, at: dataStart, count: entry.compressedSize, name: entry.name)
        let data: Data
        if entry.method == 0 {
            data = stored
        } else {
            guard let expanded = ZipCompression.inflate(stored, expectedSize: entry.size) else { throw corrupt }
            data = expanded
        }
        guard data.count == entry.size, CRC32.checksum(data) == entry.crc32 else { throw corrupt }
        return data
    }

    func entry(named name: String) -> ZipEntry? {
        index[name]
    }

    /// nil when there is no entry of that name.
    func data(named name: String) throws -> Data? {
        try index[name].map(data(of:))
    }

    // MARK: Directory

    private static func readDirectory(handle: FileHandle, fileSize: Int, limits: ZipLimits) throws -> [ZipEntry] {
        let end = try endRecord(handle: handle, fileSize: fileSize)
        guard end.directorySize <= limits.directory else { throw ZipError.tooManyEntries }
        let bytes = ZipBytes(try read(handle, fileSize: fileSize, at: end.directoryOffset, count: end.directorySize, name: ""))
        var entries: [ZipEntry] = []
        var names = Set<String>()
        var total = 0
        var position = 0
        for _ in 0..<end.entryCount {
            guard position + 46 <= bytes.data.count, bytes.read32(at: position) == 0x0201_4B50 else { throw ZipError.corrupt("") }
            let madeBy = bytes.read16(at: position + 4)
            let flags = bytes.read16(at: position + 8)
            let method = bytes.read16(at: position + 10)
            let crc = bytes.read32(at: position + 16)
            let compressedSize = bytes.read32(at: position + 20)
            let size = bytes.read32(at: position + 24)
            let nameLength = Int(bytes.read16(at: position + 28))
            let extraLength = Int(bytes.read16(at: position + 30)), commentLength = Int(bytes.read16(at: position + 32))
            let disk = bytes.read16(at: position + 34)
            let attributes = bytes.read32(at: position + 38)
            let localOffset = bytes.read32(at: position + 42)
            let recordEnd = position + 46 + nameLength + extraLength + commentLength
            guard recordEnd <= bytes.data.count else { throw ZipError.corrupt("") }
            let nameBytes = bytes.data.subdata(in: (position + 46)..<(position + 46 + nameLength))
            position = recordEnd
            guard let name = String(data: nameBytes, encoding: .utf8) else {
                throw ZipError.unsafeName(String(decoding: nameBytes, as: UTF8.self))
            }
            if ZipEntryName.problem(with: name) != nil { throw ZipError.unsafeName(name) }
            // Encrypted, strongly encrypted, an unknown method, zip64 markers or a file split over disks.
            if flags & 0x0041 != 0 || (method != 0 && method != 8) || disk != 0
                || compressedSize == UInt32.max || size == UInt32.max || localOffset == UInt32.max {
                throw ZipError.unsupported(name)
            }
            // The UNIX mode is only meaningful when a UNIX system made the archive (macOS says 3, or 19).
            let mode: UInt16 = (madeBy >> 8 == 3 || madeBy >> 8 == 19) ? UInt16(truncatingIfNeeded: attributes >> 16) : 0
            let isFolder = name.hasSuffix("/") || mode & 0o170000 == 0o040000
            if !isFolder, [0o120000, 0o020000, 0o060000, 0o010000, 0o140000].contains(mode & 0o170000) {
                throw ZipError.notARegularFile(name)
            }
            guard names.insert(name).inserted else { throw ZipError.duplicateName(name) }
            if isFolder {
                guard size == 0, compressedSize <= 2 else { throw ZipError.corrupt(name) }
                continue
            }
            let (claimed, overflow) = total.addingReportingOverflow(Int(size))
            if Int(size) > limits.perEntry { throw ZipError.entryTooLarge(name: name, size: Int(size)) }
            if overflow || claimed > limits.total { throw ZipError.archiveTooLarge(total: overflow ? .max : claimed) }
            total = claimed
            if method == 0, compressedSize != size { throw ZipError.corrupt(name) }
            // Deflate gives about the size back at the worst (a few bytes per 64 KB when nothing shrinks), and what is read
            // into memory is this many bytes, so a header that claims far more is lying.
            if method == 8, Int(compressedSize) > Int(size) + Int(size) / 1000 + 64 { throw ZipError.corrupt(name) }
            guard Int(localOffset) + localHeaderSize + Int(compressedSize) <= fileSize else { throw ZipError.corrupt(name) }
            entries.append(ZipEntry(
                name: name, method: method, compressedSize: Int(compressedSize), size: Int(size), crc32: crc,
                mode: mode, localHeaderOffset: Int(localOffset)
            ))
        }
        return entries
    }

    /// The end-of-archive record, searched from the end of the file (a comment may follow it). A candidate counts only if the
    /// comment length it states reaches exactly the end of the file and its directory lies before it.
    private static func endRecord(handle: FileHandle, fileSize: Int) throws -> (entryCount: Int, directorySize: Int, directoryOffset: Int) {
        guard fileSize >= endRecordSize else { throw ZipError.notAnArchive }
        let tailSize = min(fileSize, endRecordSize + Int(UInt16.max))
        let tailStart = fileSize - tailSize
        let tail = ZipBytes(try read(handle, fileSize: fileSize, at: tailStart, count: tailSize, name: ""))
        for candidate in stride(from: tailSize - endRecordSize, through: 0, by: -1) where tail.read32(at: candidate) == 0x0605_4B50 {
            let commentLength = Int(tail.read16(at: candidate + 20))
            guard candidate + endRecordSize + commentLength == tailSize else { continue }
            let disk = tail.read16(at: candidate + 4), directoryDisk = tail.read16(at: candidate + 6)
            let onDisk = tail.read16(at: candidate + 8), count = tail.read16(at: candidate + 10)
            let size = tail.read32(at: candidate + 12), offset = tail.read32(at: candidate + 16)
            let hasZip64Locator = candidate >= 20 && tail.read32(at: candidate - 20) == 0x0706_4B50
            if disk != 0 || directoryDisk != 0 || onDisk != count || count == UInt16.max || size == UInt32.max || offset == UInt32.max
                || hasZip64Locator {
                throw ZipError.unsupported("")
            }
            guard Int(offset) + Int(size) <= tailStart + candidate else { continue }
            return (Int(count), Int(size), Int(offset))
        }
        throw ZipError.notAnArchive
    }

    /// Exactly `count` bytes at `offset`, or `corrupt` when the file is shorter.
    private static func read(_ handle: FileHandle, fileSize: Int, at offset: Int, count: Int, name: String) throws -> Data {
        guard offset >= 0, count >= 0, offset <= fileSize, count <= fileSize - offset else { throw ZipError.corrupt(name) }
        if count == 0 { return Data() }
        try handle.seek(toOffset: UInt64(offset))
        guard let data = try handle.read(upToCount: count), data.count == count else { throw ZipError.corrupt(name) }
        return data
    }
}

// MARK: - Bytes and compression

/// Little-endian integers in a buffer, which is how a zip stores every number.
nonisolated struct ZipBytes {
    var data: Data

    init(_ data: Data = Data()) {
        self.data = data
    }

    mutating func append16(_ value: UInt16) {
        data.append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    mutating func append32(_ value: UInt32) {
        data.append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * UInt32($0))) })
    }

    func read16(at offset: Int) -> UInt16 {
        let start = data.startIndex + offset
        return UInt16(data[start]) | UInt16(data[start + 1]) << 8
    }

    func read32(at offset: Int) -> UInt32 {
        let start = data.startIndex + offset
        return (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[start + $1]) << (8 * UInt32($1)) }
    }
}

/// Raw deflate, which is what a zip's method 8 holds.
nonisolated enum ZipCompression {
    /// nil when the data is empty or does not get smaller, so the entry is stored as it is.
    static func deflate(_ data: Data) -> Data? {
        guard data.count > 1 else { return nil }
        var output = Data(count: data.count - 1)
        let written = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compression_encode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, destination.count,
                    source.bindMemory(to: UInt8.self).baseAddress!, source.count, nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { return nil }
        output.removeSubrange(written...)
        return output
    }

    /// nil unless the data expands to exactly `expectedSize` bytes. At most one byte more than that is ever produced, so a
    /// stream that expands to far more than its header says costs nothing extra.
    static func inflate(_ data: Data, expectedSize: Int) -> Data? {
        if expectedSize == 0 { return data.count <= 2 ? Data() : nil }
        guard !data.isEmpty, expectedSize < Int.max else { return nil }
        var output = Data(count: expectedSize + 1)
        let written = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, destination.count,
                    source.bindMemory(to: UInt8.self).baseAddress!, source.count, nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == expectedSize else { return nil }
        output.removeLast()
        return output
    }
}
