import Foundation
import Testing
@testable import ClipboardModule

/// What a page's title becomes before MyNotch keeps it: plain words, whatever the page put in it.
@Suite struct ClipboardLinkTextTests {
    @Test func entitiesAreDecodedOnce() {
        #expect(ClipboardLinkText.title(from: "Tom &amp; Jerry") == "Tom & Jerry")
        #expect(ClipboardLinkText.title(from: "&lt;b&gt;bold&lt;/b&gt; &quot;x&quot; &apos;y&apos;") == "<b>bold</b> \"x\" 'y'")
        // Once: the result of one decoding is not decoded again.
        #expect(ClipboardLinkText.title(from: "&amp;lt;") == "&lt;")
        #expect(ClipboardLinkText.title(from: "&amp;amp;") == "&amp;")
    }

    @Test func numericEntitiesAreDecoded() {
        #expect(ClipboardLinkText.title(from: "&#8364;5 &#x20AC;5 &#X20ac;5") == "€5 €5 €5")
        #expect(ClipboardLinkText.title(from: "&#128512;") == "😀")
        #expect(ClipboardLinkText.title(from: "caf&eacute; &copy; &hellip; &Uuml;ber &yuml;") == "café © … Über ÿ")
    }

    /// Decoded first and stripped after: a control character written as an entity does not get past the strip.
    @Test func aControlCharacterWrittenAsAnEntityIsStripped() {
        #expect(ClipboardLinkText.title(from: "a&#7;b") == "ab")
        #expect(ClipboardLinkText.title(from: "a&#0;b") == "ab")
        #expect(ClipboardLinkText.title(from: "a&#27;b&#127;c&#x9F;d") == "abcd")
        #expect(ClipboardLinkText.title(from: "a&#8238;b") == "ab")
    }

    @Test func impossibleEntitiesAreDropped() {
        // A surrogate, a number past the last character, one with too many digits.
        #expect(ClipboardLinkText.title(from: "a&#xD800;b&#1114112;c&#99999999;d") == "abcd")
        // A name that is not in the table is dropped, not shown as it was written.
        #expect(ClipboardLinkText.title(from: "x &bogus; y") == "x y")
    }

    @Test func aLoneAmpersandStays() {
        #expect(ClipboardLinkText.title(from: "AT&T rocks") == "AT&T rocks")
        #expect(ClipboardLinkText.title(from: "Q&A & more &") == "Q&A & more &")
        #expect(ClipboardLinkText.title(from: "&;") == "&;")
        #expect(ClipboardLinkText.title(from: "&#;") == "&#;")
    }

    @Test func lineBreaksAndRunsOfWhiteSpaceBecomeOneSpace() {
        #expect(ClipboardLinkText.title(from: "line1\n\n  line2\t\tend\r\n") == "line1 line2 end")
        #expect(ClipboardLinkText.title(from: "a&nbsp;&nbsp;b&#10;c") == "a b c")
        #expect(ClipboardLinkText.title(from: "a\u{2028}b\u{2029}c\u{3000}d") == "a b c d")
    }

    @Test func controlCharactersAreStripped() {
        #expect(ClipboardLinkText.title(from: "a\u{0}b\u{1B}c\u{7F}d") == "abcd")
        #expect(ClipboardLinkText.title(from: "a\u{80}b\u{9F}c") == "abc")
    }

    @Test func textThatReversesDirectionOrHidesItselfIsStripped() {
        #expect(ClipboardLinkText.title(from: "abc\u{202E}def") == "abcdef")
        #expect(ClipboardLinkText.title(from: "\u{2066}x\u{2069} \u{202A}y\u{202C}") == "x y")
        #expect(ClipboardLinkText.title(from: "a\u{200E}b\u{200F}c") == "abc")
        #expect(ClipboardLinkText.title(from: "a\u{200B}b\u{FEFF}c\u{2060}d") == "abcd")
    }

    @Test func joinersStayForEmojiAndAccentsAreKept() {
        #expect(ClipboardLinkText.title(from: "👨‍👩‍👧 gia đình") == "👨‍👩‍👧 gia đình")
        #expect(ClipboardLinkText.title(from: "Xin chào Việt Nam") == "Xin chào Việt Nam")
        #expect(ClipboardLinkText.title(from: "Vie\u{0302}\u{0323}t") == "Vie\u{0302}\u{0323}t")
    }

    @Test func aTitleIsCutAtTwoHundredCharacters() throws {
        let long = try #require(ClipboardLinkText.title(from: String(repeating: "a", count: 500)))
        #expect(long.count == 200)
        // Characters, not bytes or scalars: 300 emoji are cut at 200 emoji.
        let emoji = try #require(ClipboardLinkText.title(from: String(repeating: "😀", count: 300)))
        #expect(emoji.count == 200)
        #expect(try #require(ClipboardLinkText.title(from: String(repeating: "b", count: 200))).count == 200)
        #expect(try #require(ClipboardLinkText.title(from: String(repeating: "b", count: 199))).count == 199)
        #expect(ClipboardLinkText.titleLimit == 200)
    }

    /// A character (a grapheme cluster) can hold any number of combining marks, so 200 characters alone bound nothing: scalars are cut first.
    @Test func aStackOfCombiningMarksIsBounded() throws {
        let zalgo = String(repeating: "a" + String(repeating: "\u{0301}", count: 500), count: 300)
        let title = try #require(ClipboardLinkText.title(from: zalgo))
        #expect(title.unicodeScalars.count <= ClipboardLinkText.titleScalarLimit)
        #expect(title.utf8.count <= 4 * ClipboardLinkText.titleScalarLimit)
        #expect(title.count <= ClipboardLinkText.titleLimit)
        // Marks beyond four on a letter are dropped before the cut, so what stays is letters with a few marks, not one letter with 400.
        #expect(title.count > 50)
        let cluster = "a" + String(repeating: "\u{0301}", count: ClipboardLinkText.marksPerLetter)
        #expect(title.unicodeScalars.starts(with: (cluster + cluster).unicodeScalars))
        // Cut after a hundred thousand marks on one letter: nothing but the first few survive.
        let one = try #require(ClipboardLinkText.title(from: "e" + String(repeating: "\u{0323}", count: 100_000)))
        #expect(one.unicodeScalars.count == 1 + ClipboardLinkText.marksPerLetter)
        // A title of more than 400 scalars that are each a character is cut at 200 characters, as before.
        let wide = try #require(ClipboardLinkText.title(from: String(repeating: "😀", count: 500)))
        #expect(wide.count == 200)
        // Combining marks that are real text are kept: Vietnamese needs two, an emoji keycap one.
        #expect(try #require(ClipboardLinkText.title(from: "Vie\u{0302}\u{0323}t Nam")) == "Vie\u{0302}\u{0323}t Nam")
        #expect(try #require(ClipboardLinkText.title(from: "1\u{FE0F}\u{20E3}")) == "1\u{FE0F}\u{20E3}")
    }

    /// Hidden text is how smuggling works: every scalar that shows nothing is gone, whichever kind it is.
    @Test(arguments: [
        0xE0041, 0xE007F, 0xE0100, 0xE01EF, 0x206A, 0x206F, 0x2061, 0x2064, 0x115F, 0x1160, 0x3164, 0xFFA0, 0xFFFC, 0x180E, 0x034F, 0x00AD,
        0x2062, 0x2063, 0x0600, 0xFE00, 0xFE0D, 0x200B, 0x2060, 0xFEFF, 0x202E, 0x2067, 0x200E, 0x061C, 0x0085,
    ])
    func anInvisibleScalarIsStripped(_ value: Int) throws {
        let scalar = try #require(Unicode.Scalar(UInt32(value)))
        let title = try #require(ClipboardLinkText.title(from: "a\(Character(scalar))b"), "U+\(String(value, radix: 16))")
        // U+0085 is white space, which is a space; everything else is nothing.
        #expect(title == "ab" || title == "a b", "U+\(String(value, radix: 16))")
        #expect(!title.unicodeScalars.contains(scalar))
    }

    @Test func thePresentationSelectorsAndJoinersEmojiNeedStay() {
        #expect(ClipboardLinkText.title(from: "❤\u{FE0F} 👨\u{200D}👩\u{200D}👧 ✔\u{FE0E}") == "❤\u{FE0F} 👨\u{200D}👩\u{200D}👧 ✔\u{FE0E}")
        // The flags of England, Scotland and Wales are spelled with tag characters, which are stripped: they come out as a black flag.
        let england = "🏴\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"
        #expect(ClipboardLinkText.title(from: england) == "🏴")
    }

    @Test func nothingLeftIsNil() {
        #expect(ClipboardLinkText.title(from: "") == nil)
        #expect(ClipboardLinkText.title(from: "  \n\t ") == nil)
        #expect(ClipboardLinkText.title(from: "\u{0}\u{1}\u{200B}&#7;") == nil)
    }
}
