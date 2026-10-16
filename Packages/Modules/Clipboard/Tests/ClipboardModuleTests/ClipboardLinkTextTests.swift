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

    @Test func nothingLeftIsNil() {
        #expect(ClipboardLinkText.title(from: "") == nil)
        #expect(ClipboardLinkText.title(from: "  \n\t ") == nil)
        #expect(ClipboardLinkText.title(from: "\u{0}\u{1}\u{200B}&#7;") == nil)
    }
}
