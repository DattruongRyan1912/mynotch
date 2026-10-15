import AppKit
import CoreText
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers

/// Images, PDFs and folders built in code, so no test needs a file from the repository or from the user.
enum SyntheticFiles {
    /// The left half is red and the right half blue, so a test can tell whether the image was turned.
    static func image(width: Int, height: Int, alpha: Bool = false) -> CGImage {
        let info = alpha ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info.rawValue
        )!
        if alpha { context.clear(CGRect(x: 0, y: 0, width: width, height: height)) }
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: alpha ? height / 2 : height))
        return context.makeImage()!
    }

    /// Writes `image` as `type`; `properties` are image properties such as orientation or a GPS dictionary.
    @discardableResult
    static func write(_ image: CGImage, as type: UTType, named name: String, in folder: URL, properties: [CFString: Any] = [:]) throws -> URL {
        let url = folder.appending(path: name)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    static let gps: [CFString: Any] = [
        kCGImagePropertyGPSLatitude: 10.77, kCGImagePropertyGPSLatitudeRef: "N",
        kCGImagePropertyGPSLongitude: 106.7, kCGImagePropertyGPSLongitudeRef: "E",
    ]

    static func properties(of url: URL) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    static func decoded(_ url: URL) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    static func decoded(_ data: Data) throws -> CGImage {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// The format ImageIO finds in the file, whatever its extension says.
    static func type(of url: URL) throws -> UTType {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require((CGImageSourceGetType(source) as String?).flatMap(UTType.init))
    }

    /// Red, green, blue and alpha (0...255, not premultiplied) of the pixel `x` from the left and `y` from the top.
    static func pixel(of image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let offset = (y * image.width + x) * 4
        let alpha = Int(bytes[offset + 3])
        func straight(_ value: UInt8) -> Int { alpha == 0 ? 0 : min(255, Int(value) * 255 / alpha) }
        return (straight(bytes[offset]), straight(bytes[offset + 1]), straight(bytes[offset + 2]), alpha)
    }

    /// A PDF of `pages` pages, each `size` points, with a black square on a white page.
    @discardableResult
    static func pdf(pages: Int, size: CGSize = CGSize(width: 200, height: 300), named name: String = "tài liệu.pdf", in folder: URL) throws -> URL {
        let document = PDFDocument()
        for index in 0..<pages {
            let image = NSImage(size: size, flipped: false) { rect in
                NSColor.white.setFill()
                rect.fill()
                NSColor.black.setFill()
                NSRect(x: 20, y: 20, width: 60, height: 60).fill()
                return true
            }
            let page = try #require(PDFPage(image: image))
            document.insert(page, at: index)
        }
        let url = folder.appending(path: name)
        #expect(document.write(to: url))
        return url
    }

    /// One entry of a zip file as its central directory and local header describe it.
    struct ZipRecord {
        let name: String
        /// The Unix mode in the high half of the external attributes; 0 when the archive gives none.
        let mode: Int
        /// The stored bytes of an entry that is not compressed (a link's target is stored this way).
        let stored: Data?

        var isLink: Bool { mode & 0o170000 == 0o120000 }
    }

    static func zipRecords(_ url: URL) throws -> [ZipRecord] {
        let data = try Data(contentsOf: url)
        func u16(_ offset: Int) -> Int { Int(data[offset]) | Int(data[offset + 1]) << 8 }
        func u32(_ offset: Int) -> Int { u16(offset) | u16(offset + 2) << 16 }
        var end = data.count - 22
        while end >= 0, u32(end) != 0x0605_4b50 { end -= 1 }
        try #require(end >= 0, "not a zip file")
        var offset = u32(end + 16)
        var records: [ZipRecord] = []
        for _ in 0..<u16(end + 10) {
            let method = u16(offset + 10), size = u32(offset + 20)
            let nameLength = u16(offset + 28), extraLength = u16(offset + 30), commentLength = u16(offset + 32)
            let local = u32(offset + 42)
            let name = String(decoding: data[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            var stored: Data?
            if method == 0 {
                let start = local + 30 + u16(local + 26) + u16(local + 28)
                stored = data[start..<(start + size)]
            }
            records.append(ZipRecord(name: name, mode: u32(offset + 38) >> 16, stored: stored))
            offset += 46 + nameLength + extraLength + commentLength
        }
        return records
    }

    /// The names of the entries of a zip file, read from its central directory.
    static func zipEntries(_ url: URL) throws -> [String] {
        let data = try Data(contentsOf: url)
        func u16(_ offset: Int) -> Int { Int(data[offset]) | Int(data[offset + 1]) << 8 }
        func u32(_ offset: Int) -> Int { u16(offset) | u16(offset + 2) << 16 }
        var end = data.count - 22
        while end >= 0, u32(end) != 0x0605_4b50 { end -= 1 }
        try #require(end >= 0, "not a zip file")
        var offset = u32(end + 16)
        var names: [String] = []
        for _ in 0..<u16(end + 10) {
            let nameLength = u16(offset + 28), extraLength = u16(offset + 30), commentLength = u16(offset + 32)
            names.append(String(decoding: data[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self))
            offset += 46 + nameLength + extraLength + commentLength
        }
        return names
    }
}

extension SyntheticFiles {
    /// Black text on white, large and clean enough for Vision to read the same way every time.
    static func textImage(_ string: String, size: CGFloat = 64) -> CGImage {
        let width = 1100, height = 200
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let text = NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.black])
        context.textPosition = CGPoint(x: 30, y: 70)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
        return context.makeImage()!
    }
}

extension SyntheticFiles {
    /// One grey all over, which has nothing in it for Vision to call a subject.
    static func flat(width: Int, height: Int, gray: CGFloat = 0.5) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(gray: gray, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}
