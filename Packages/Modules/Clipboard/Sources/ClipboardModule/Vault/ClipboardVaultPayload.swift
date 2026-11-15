import Foundation

/// What is inside the seal of a vault: the items of the board, whole (their dates, apps and text too, so nothing about them
/// is visible while locked), and the bytes of their images. Framed as a 4-byte length, a JSON header (the items and the images'
/// names and lengths) and the image bytes one after the other.
nonisolated enum ClipboardVaultPayload {
    static let maxItems = 50_000

    struct Contents: Equatable, Sendable {
        var items: [ClipboardItem]
        /// PNG bytes by file name, for every image item.
        var images: [String: Data]
    }

    private struct Header: Codable {
        struct Image: Codable {
            var fileName: String
            var length: Int
        }

        var items: [ClipboardItem]
        var images: [Image]
    }

    /// Throws `.damaged` for an image item whose bytes are missing, or whose name is not the hash of its bytes: a restore must
    /// never write a file whose name it did not compute.
    static func encode(_ contents: Contents) throws -> Data {
        guard contents.items.count <= maxItems else { throw ClipboardVaultError.damaged }
        let names = contents.items.compactMap { item -> String? in
            if case .image(let image) = item.content { image.fileName } else { nil }
        }
        for name in names {
            guard let bytes = contents.images[name], isStoredName(name, for: bytes) else { throw ClipboardVaultError.damaged }
        }
        for (name, bytes) in contents.images where !isStoredName(name, for: bytes) { throw ClipboardVaultError.damaged }
        let ordered = contents.images.sorted { $0.key < $1.key }
        let header = Header(items: contents.items, images: ordered.map { Header.Image(fileName: $0.key, length: $0.value.count) })
        let json = try JSONEncoder().encode(header)
        var data = Data()
        data.reserveCapacity(4 + json.count + ordered.reduce(0) { $0 + $1.value.count })
        withUnsafeBytes(of: UInt32(json.count).bigEndian) { data.append(contentsOf: $0) }
        data.append(json)
        for (_, bytes) in ordered { data.append(bytes) }
        return data
    }

    static func decode(_ data: Data) throws -> Contents {
        guard data.count >= 4 else { throw ClipboardVaultError.damaged }
        let base = data.startIndex
        let length = data[base..<base + 4].reduce(0) { ($0 << 8) | Int($1) }
        guard length <= data.count - 4 else { throw ClipboardVaultError.damaged }
        guard let header = try? JSONDecoder().decode(Header.self, from: data[(base + 4)..<(base + 4 + length)]),
              header.items.count <= maxItems else { throw ClipboardVaultError.damaged }
        var images: [String: Data] = [:]
        var offset = base + 4 + length
        for image in header.images {
            guard image.length >= 0, image.length <= data.endIndex - offset, images[image.fileName] == nil else { throw ClipboardVaultError.damaged }
            let bytes = Data(data[offset..<offset + image.length])
            guard isStoredName(image.fileName, for: bytes) else { throw ClipboardVaultError.damaged }
            images[image.fileName] = bytes
            offset += image.length
        }
        guard offset == data.endIndex else { throw ClipboardVaultError.damaged }
        for item in header.items {
            if case .image(let image) = item.content, images[image.fileName] == nil { throw ClipboardVaultError.damaged }
        }
        return Contents(items: header.items, images: images)
    }

    /// "<SHA-256 of the bytes>.png": how images are stored, so the name is proof of the content.
    private static func isStoredName(_ name: String, for bytes: Data) -> Bool {
        name.wholeMatch(of: /[0-9a-f]{64}\.png/) != nil && bytes.sha256Hex + ".png" == name
    }
}
