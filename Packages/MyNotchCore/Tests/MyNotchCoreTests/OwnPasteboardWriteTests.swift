import AppKit
import Testing
import MyNotchCore

@Suite struct OwnPasteboardWriteTests {
    /// Clipboard's history skips what carries this type, in the history already on disk and in other clipboard managers: a
    /// change to the string would make MyNotch record its own writes again.
    @Test func theMarkerIsByteForByteTheOneEveryReleaseHasWritten() {
        #expect(OwnPasteboardWrite.typeIdentifier == "io.lucasvu.mynotch.clipboard")
        #expect(Array(OwnPasteboardWrite.typeIdentifier.utf8) == Array("io.lucasvu.mynotch.clipboard".utf8))
        #expect(OwnPasteboardWrite.pasteboardType.rawValue == "io.lucasvu.mynotch.clipboard")
    }

    @Test func theMarkerIsATypeAPasteboardItemKeeps() {
        let item = NSPasteboardItem()
        #expect(item.setData(Data(), forType: OwnPasteboardWrite.pasteboardType))
        #expect(item.types.contains(OwnPasteboardWrite.pasteboardType))
    }
}
