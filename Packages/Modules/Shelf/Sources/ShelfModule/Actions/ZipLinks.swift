import Foundation

/// A symbolic link to keep in a zip as a link: its place in the archive and what it points at, as text. A link is
/// never followed, so the archive holds the path and not what is behind it.
nonisolated struct ZipLink: Equatable, Sendable {
    /// Inside the archive: `Dự án/con/lên`.
    let path: String
    /// Where the link points, as it is written (relative stays relative).
    let target: String
    /// Where the link is on disk, for the message when it cannot be stored.
    let source: URL
}

/// Adds links to a finished zip. The system's zip (`.forUploading`) fails on any folder that holds a link and cannot
/// store one, so the folder is zipped without its links and they are added here, as entries that Finder and `unzip`
/// unpack as links (Unix mode `lrwxrwxrwx` in the external attributes, the target stored as the entry's data).
nonisolated enum ZipLinks {
    enum Failure: Error {
        /// The archive is not one this can extend (not a zip, or zip64). Nothing was changed.
        case unsupported
    }

    /// Extends `zip` in place: the new entries go where the central directory was, and the directory follows them.
    /// Throws `Failure.unsupported` before touching the file, and `FileActionError.cannotWrite` when writing fails.
    static func append(_ links: [ZipLink], to zip: URL, modified: Date = .now) throws {
        guard !links.isEmpty else { return }
        let handle: FileHandle
        do {
            handle = try FileHandle(forUpdating: zip)
        } catch {
            throw FileActionError.cannotWrite
        }
        defer { try? handle.close() }

        let (directoryOffset, directory, entries) = try readEnd(of: handle)
        let (dosDate, dosTime) = dosStamp(modified)
        var locals = Data(), added = Data()
        for link in links {
            let name = Array(link.path.utf8), target = Array(link.target.utf8)
            let offset = directoryOffset + UInt64(locals.count)
            guard offset < 0xFFFF_FFFF, name.count < 0xFFFF else { throw Failure.unsupported }
            let crc = CRC32.checksum(target)
            locals += le32(0x0403_4B50) + le16(20) + le16(0x0800) + le16(0) + le16(dosTime) + le16(dosDate)
                + le32(crc) + le32(UInt32(target.count)) + le32(UInt32(target.count)) + le16(UInt16(name.count)) + le16(0) + name + target
            added += le32(0x0201_4B50) + le16(0x0314) + le16(20) + le16(0x0800) + le16(0) + le16(dosTime) + le16(dosDate)
                + le32(crc) + le32(UInt32(target.count)) + le32(UInt32(target.count)) + le16(UInt16(name.count))
                + le16(0) + le16(0) + le16(0) + le16(0) + le32(0xA1FF_0000) + le32(UInt32(offset)) + name
        }
        let total = entries + links.count
        let directorySize = UInt64(directory.count + added.count), newDirectoryOffset = directoryOffset + UInt64(locals.count)
        guard total < 0xFFFF, newDirectoryOffset + directorySize + 22 < 0xFFFF_FFFF else { throw Failure.unsupported }
        let end = le32(0x0605_4B50) + le16(0) + le16(0) + le16(UInt16(total)) + le16(UInt16(total))
            + le32(UInt32(directorySize)) + le32(UInt32(newDirectoryOffset)) + le16(0)
        var tail = locals
        tail.append(directory)
        tail.append(added)
        tail.append(Data(end))
        do {
            try handle.seek(toOffset: directoryOffset)
            try handle.write(contentsOf: tail)
            try handle.truncate(atOffset: directoryOffset + UInt64(tail.count))
        } catch {
            throw FileActionError.cannotWrite
        }
    }

    /// Where the central directory starts, its bytes and the number of entries in it.
    private static func readEnd(of handle: FileHandle) throws -> (offset: UInt64, directory: Data, entries: Int) {
        do {
            let size = try handle.seekToEnd()
            let length = min(size, 65_557)
            try handle.seek(toOffset: size - length)
            guard let tail = try handle.read(upToCount: Int(length)).map({ [UInt8]($0) }), tail.count >= 22 else { throw Failure.unsupported }
            func u16(_ at: Int) -> Int { Int(tail[at]) | Int(tail[at + 1]) << 8 }
            func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
            guard let end = (0...(tail.count - 22)).reversed().first(where: { u32($0) == 0x0605_4B50 }) else { throw Failure.unsupported }
            let entries = u16(end + 10), directorySize = u32(end + 12), directoryOffset = u32(end + 16)
            // 0xFFFF and 0xFFFFFFFF say "look in the zip64 record"; a zip64 locator sits just before the end record.
            let isZip64 = entries == 0xFFFF || directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF
                || (end >= 20 && u32(end - 20) == 0x0706_4B50)
            guard !isZip64, u16(end + 4) == 0, u16(end + 6) == 0, u16(end + 8) == entries,
                  UInt64(directoryOffset + directorySize) <= size else { throw Failure.unsupported }
            try handle.seek(toOffset: UInt64(directoryOffset))
            // An archive of an empty folder is only an end record.
            let directory = directorySize == 0 ? Data() : try handle.read(upToCount: directorySize) ?? Data()
            guard directory.count == directorySize else { throw Failure.unsupported }
            return (UInt64(directoryOffset), directory, entries)
        } catch let failure as Failure {
            throw failure
        } catch {
            throw FileActionError.cannotWrite
        }
    }

    private static func dosStamp(_ date: Date) -> (date: UInt16, time: UInt16) {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max(1980, parts.year ?? 1980) - 1980
        return (
            UInt16(year << 9 | (parts.month ?? 1) << 5 | (parts.day ?? 1)),
            UInt16((parts.hour ?? 0) << 11 | (parts.minute ?? 0) << 5 | (parts.second ?? 0) / 2)
        )
    }

    private static func le16(_ value: UInt16) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8)] }
    private static func le32(_ value: UInt32) -> [UInt8] { [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 24)] }
}

/// CRC-32 as zip stores it (the polynomial 0xEDB88320).
nonisolated enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        (0..<8).reduce(UInt32(index)) { value, _ in value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
    }

    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        ~bytes.reduce(UInt32.max) { crc, byte in table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
    }
}
