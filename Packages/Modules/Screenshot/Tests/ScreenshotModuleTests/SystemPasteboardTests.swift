import AppKit
import Foundation
import ImageIO
import MyNotchCore
import Testing
@testable import ScreenshotModule

/// Only a private named pasteboard is ever written, never the general one.
@Suite final class SystemPasteboardTests {
    let board = NSPasteboard(name: NSPasteboard.Name("MyNotchTests.\(UUID().uuidString)"))
    var writer: SystemPasteboard { SystemPasteboard(pasteboard: board) }

    isolated deinit { board.releaseGlobally() }

    func size(of data: Data) throws -> CGSize {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return CGSize(width: image.width, height: image.height)
    }

    @Test func writesAPNGAndATIFFOfTheImage() async throws {
        let image = try CaptureStoreTests.image(width: 30, height: 20)
        #expect(await writer.write(image, scale: 2))
        #expect(try size(of: #require(board.data(forType: .png))) == CGSize(width: 30, height: 20))
        #expect(try size(of: #require(board.data(forType: .tiff))) == CGSize(width: 30, height: 20))
    }

    @Test func theImageCarriesItsScaleAsDPI() async throws {
        #expect(await writer.write(try CaptureStoreTests.image(width: 30, height: 20), scale: 2))
        let png = try #require(board.data(forType: .png))
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect((properties[kCGImagePropertyDPIWidth] as? Double)?.rounded() == 144)
    }

    @Test func neverMarksTheWriteAsMyNotchsOwn() async throws {
        #expect(await writer.write(try CaptureStoreTests.image(width: 4, height: 4), scale: 1))
        let types = (board.types ?? []).map(\.rawValue)
        #expect(!types.isEmpty)
        #expect(!types.contains { $0.contains("mynotch") || $0.hasPrefix("org.nspasteboard") })
    }

    @Test func aMarkedWriteCarriesMyNotchsOwnWriteTypeBesideTheImage() async throws {
        #expect(await writer.write(try CaptureStoreTests.image(width: 30, height: 20), scale: 2, markedAsOwn: true))
        let types = (board.types ?? []).map(\.rawValue)
        #expect(types.contains(OwnPasteboardWrite.typeIdentifier))
        #expect(types.contains("io.lucasvu.mynotch.clipboard"))
        #expect(try size(of: #require(board.data(forType: .png))) == CGSize(width: 30, height: 20))
        #expect(try size(of: #require(board.data(forType: .tiff))) == CGSize(width: 30, height: 20))
    }

    @Test func anUnmarkedWriteStaysUnmarkedWhenAskedExplicitly() async throws {
        #expect(await writer.write(try CaptureStoreTests.image(width: 4, height: 4), scale: 1, markedAsOwn: false))
        #expect(!(board.types ?? []).contains(OwnPasteboardWrite.pasteboardType))
    }

    @Test func aFileGoesOnTheBoardAsAFileURLThatAFileTargetCanRead() throws {
        let url = URL(filePath: "/Users/someone/Movies/MyNotch/Bản quay MyNotch 2026-10-18 14.30.00.mp4")
        #expect(writer.write(fileURL: url, markedAsOwn: false))
        let read = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        #expect(read == [url])
        #expect(board.string(forType: .fileURL) == url.absoluteString)
        #expect(!(board.types ?? []).contains(OwnPasteboardWrite.pasteboardType))
    }

    @Test func aMarkedFileCarriesMyNotchsOwnWriteTypeOnTheSameItem() throws {
        let url = URL(filePath: "/Users/someone/Movies/MyNotch/demo.mp4")
        #expect(writer.write(fileURL: url, markedAsOwn: true))
        #expect(board.pasteboardItems?.count == 1)
        let types = (board.pasteboardItems?.first?.types ?? []).map(\.rawValue)
        #expect(types.contains(OwnPasteboardWrite.typeIdentifier))
        #expect(types.contains("public.file-url"))
        #expect(board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] == [url])
    }

    @Test func aFileReplacesWhatWasThere() throws {
        board.clearContents()
        board.setString("old", forType: .string)
        #expect(writer.write(fileURL: URL(filePath: "/tmp/a.mp4"), markedAsOwn: true))
        #expect(board.string(forType: .string) == nil)
    }

    @Test func replacesWhatWasThere() async throws {
        board.clearContents()
        board.setString("old", forType: .string)
        #expect(await writer.write(try CaptureStoreTests.image(width: 4, height: 4), scale: 1))
        #expect(board.string(forType: .string) == nil)
        #expect(writer.write("Xin chào"))
        #expect(board.string(forType: .string) == "Xin chào")
        #expect(board.data(forType: .png) == nil)
    }
}
