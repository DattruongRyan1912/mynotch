import AppKit
import Foundation
import Testing
@testable import ShelfModule

/// Records what would be copied. Nothing here touches a pasteboard.
final class FakePasteboard: PasteboardWriting {
    private(set) var written: [String] = []
    var accepts = true

    func write(_ text: String) -> Bool {
        guard accepts else { return false }
        written.append(text)
        return true
    }
}

/// Only a private named pasteboard is ever written, never the general one.
@Suite final class SystemPasteboardTests {
    let board = NSPasteboard(name: NSPasteboard.Name("MyNotchTests.\(UUID().uuidString)"))
    var writer: SystemPasteboard { SystemPasteboard(pasteboard: board) }

    isolated deinit { board.releaseGlobally() }

    @Test func replacesWhatWasThereWithTheText() {
        board.clearContents()
        board.setString("cũ", forType: .string)
        #expect(writer.write("Xin chào"))
        #expect(board.string(forType: .string) == "Xin chào")
        #expect(board.pasteboardItems?.count == 1)
    }

    /// As Screenshot's recognised text: the Clipboard module records it in its history like any other copy.
    @Test func addsNoMarkerSoTheClipboardHistoryKeepsTheText() {
        #expect(writer.write("chữ"))
        let types = (board.types ?? []).map(\.rawValue)
        #expect(!types.isEmpty)
        #expect(!types.contains { $0.contains("mynotch") || $0.hasPrefix("org.nspasteboard") })
    }
}
