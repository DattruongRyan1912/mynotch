import Foundation
import Testing
@testable import ClipboardModule

/// What a copy sends to the paired phone: the relay keeps the last clip for every new connection, so a secret must never leave.
extension ClipboardModuleTests {
    final class Sent {
        var texts: [String] = []
    }

    func recordSends() -> Sent {
        let sent = Sent()
        module.sendToCloud = { text, _ in sent.texts.append(text) }
        return sent
    }

    @Test func plainTextFromAnotherAppIsSentToTheCloud() async {
        let sent = recordSends()
        await start()
        copy("Xin chào")

        #expect(sent.texts == ["Xin chào"])
    }

    @Test func copyingImageDoesNotAutoSendToCloud() async {
        let sent = recordSends()
        await start()
        let tiffData = Data([0x49, 0x49, 0x2A, 0x00]) // Minimal TIFF header
        copy(PasteboardSnapshot(types: ["public.tiff"], tiff: tiffData))

        #expect(sent.texts.isEmpty, "Image copy MUST NOT auto-send to cloud")
    }

    @Test func copyingFileDoesNotAutoSendToCloud() async {
        let sent = recordSends()
        await start()
        let fileURL = URL(fileURLWithPath: "/tmp/sample.pdf")
        copy(PasteboardSnapshot(types: ["public.file-url"], fileURLs: [fileURL]))

        #expect(sent.texts.isEmpty, "File copy MUST NOT auto-send to cloud")
    }

    @Test(arguments: [true, false])
    func aCopyFromPasswordsIsNeverSentToTheCloud(ignoreSensitive: Bool) async throws {
        let (settings, keys) = try settings()
        settings.set(ignoreSensitive, for: keys.ignoreSensitive)
        let sent = recordSends()
        system.frontmost = ("com.apple.Passwords", "Passwords")
        await start()
        copy("hunter2")

        #expect(sent.texts.isEmpty)
        #expect(items.map(\.content) == (ignoreSensitive ? [] : [.text("hunter2")]))
        #expect(items.allSatisfy { $0.isSensitive })
    }

    @Test func aCopyMarkedConcealedIsNeverSentToTheCloudEvenWhenKept() async throws {
        let (settings, keys) = try settings()
        settings.set(false, for: keys.ignoreSensitive)
        let sent = recordSends()
        await start()
        copy(PasteboardSnapshot(types: ["org.nspasteboard.ConcealedType", "public.utf8-plain-text"], string: "hunter2"))

        #expect(sent.texts.isEmpty)
        #expect(items.map(\.isSensitive) == [true])
    }
}
