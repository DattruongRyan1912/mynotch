import Testing
@testable import YouTubeBridgeKit

@Suite struct DisplayTextTests {
    @Test func runsOfWhitespaceAreOneSpaceAndTheEndsAreTrimmed() {
        #expect(DisplayText.clean("  A\n\n  B\t C \r\n", limit: 50) == "A B C")
        #expect(DisplayText.clean("", limit: 50) == "")
        #expect(DisplayText.clean(" \n\t ", limit: 50) == "")
    }

    @Test func controlCharactersAreDropped() {
        #expect(DisplayText.clean("a\u{0000}b\u{0007}c\u{001B}[31md\u{007F}e\u{0085}f\u{009F}g", limit: 50) == "abc[31mdefg")
    }

    @Test func theMarksThatSetTheDirectionOfTextAreDropped() {
        // Embeddings and overrides, the left-to-right and right-to-left marks, the Arabic letter mark and the isolates.
        let marks = "\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{200E}\u{200F}\u{061C}\u{2066}\u{2067}\u{2068}\u{2069}"
        #expect(DisplayText.clean("moc.elpmaxe\(marks)/lanigiro", limit: 50) == "moc.elpmaxe/lanigiro")
    }

    @Test func textInAnyLanguageAndEmojiAreKept() {
        #expect(DisplayText.clean("Bài hát — 日本語 🎵 שלום", limit: 50) == "Bài hát — 日本語 🎵 שלום")
    }

    @Test func theTextIsCutAtTheLimitAfterTheCleaning() {
        #expect(DisplayText.clean(String(repeating: "x", count: 500), limit: 200).count == 200)
        // What cleaning removes does not count towards the limit, and a cut does not leave a space at the end.
        #expect(DisplayText.clean("\u{202E}ab cd", limit: 3) == "ab")
        #expect(DisplayText.clean("ab\n\n\ncd", limit: 4) == "ab c")
    }
}
