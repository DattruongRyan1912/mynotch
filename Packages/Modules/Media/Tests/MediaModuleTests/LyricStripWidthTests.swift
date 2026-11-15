import AppKit
import MyNotchCore
import NotchUI
import SwiftUI
import Testing
@testable import MediaModule

/// The width the lyrics strip asks the collapsed notch to be (`View.notchStripWidth`): as wide as the wider of its two rows, so the whole
/// sung line shows, however narrow the notch's own width is.
@Suite struct LyricStripWidthTests {
    /// A width that does not depend on the machine's fonts: half the point size per character, so 12 pt text is 6 pt a character.
    let measure: (String, NSFont) -> CGFloat = { text, font in CGFloat(text.count) * font.pointSize / 2 }
    let margin = LyricStrip.measuringMargin

    // MARK: the pure width

    @Test func theWidthIsTheWiderOfTheTwoRowsAtTheirOwnSizes() {
        // Current row at 12 pt (6 pt a character), next row at 11 pt (5.5).
        let longCurrent = LyricStrip(current: String(repeating: "a", count: 40), next: String(repeating: "b", count: 10))
        #expect(longCurrent.preferredWidth(measure: measure) == 40 * 6 + margin)
        let longNext = LyricStrip(current: String(repeating: "a", count: 10), next: String(repeating: "b", count: 50))
        #expect(longNext.preferredWidth(measure: measure) == 50 * 5.5 + margin)
        let equalish = LyricStrip(current: String(repeating: "a", count: 20), next: String(repeating: "b", count: 20))
        #expect(equalish.preferredWidth(measure: measure) == 20 * 6 + margin, "the current row is the bigger one at the same length")
    }

    @Test func aLongPairAsksForMoreThanAShortOne() {
        let short = LyricStrip(current: "Hello", next: "World")
        let long = LyricStrip(current: "Muốn giữ em lại nhưng không thể nào", next: "Vì anh biết rằng em đã đi xa")
        #expect(long.preferredWidth(measure: measure) > short.preferredWidth(measure: measure) + 100)
        #expect(short.preferredWidth(measure: measure) == 5 * 6 + margin)
    }

    @Test func theNoteAndAnEmptyRowAskForALittle() {
        // Nothing sung and nothing coming (a new track's lyrics are being looked up): the note alone.
        let waiting = LyricStrip.waiting.preferredWidth(measure: measure)
        #expect(waiting == 6 + margin, "one character wide, the note")
        #expect(waiting < 20)
        // A pause between lines: the note on top, and the line coming next below it.
        let pause = LyricStrip(current: nil, next: "the next line")
        #expect(pause.preferredWidth(measure: measure) == 13 * 5.5 + margin)
        // After the last line: the line alone, an empty row under it.
        let last = LyricStrip(current: "the last line", next: nil)
        #expect(last.preferredWidth(measure: measure) == 13 * 6 + margin)
    }

    @Test func theRealFontsMeasureAWiderLineWiderAndTheCurrentRowBiggerThanTheNextAtTheSameText() {
        let text = "Muốn giữ em lại nhưng không thể nào"
        let current = LyricStrip.textWidth(text, font: NowPlayingLyricStrip.currentFont)
        let next = LyricStrip.textWidth(text, font: NowPlayingLyricStrip.nextFont)
        #expect(current > next && next > 100)
        #expect(LyricStrip.textWidth(text + text, font: NowPlayingLyricStrip.currentFont) > 1.9 * current)
        #expect(LyricStrip.textWidth("", font: NowPlayingLyricStrip.currentFont) == 0)
        #expect(LyricStrip(current: text, next: nil).preferredWidth() == current + margin)
    }

    @Test func theStripsFontsAreTheOnesItDrawsWith() {
        #expect(NowPlayingLyricStrip.currentFont.pointSize == 12 && NowPlayingLyricStrip.nextFont.pointSize == 11)
        #expect(NowPlayingLyricStrip.minimumScale == 0.8)
    }

    // MARK: the strip says it

    func makeStore(elapsed: Double, lines: [LyricLine]) -> NowPlayingStore {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        store.apply(line: AdapterLines.track(elapsed: elapsed), receivedAt: Date())
        store.setLyricsOn(true)
        store.showLyrics(lines)
        store.setKaraokeEnabled(false)
        return store
    }

    final class Heard {
        var widths: [CGFloat] = []
    }

    /// What the strip tells whoever hosts it, with the lyrics at `elapsed`.
    func reported(_ store: NowPlayingStore) async throws -> CGFloat {
        let heard = Heard()
        let view = NowPlayingLyricStrip(store: store).onNotchStripWidth { heard.widths.append($0) }.frame(width: 700)
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 700, height: 80), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        defer { window.contentView = nil }
        for _ in 0..<200 {
            hosting.layoutSubtreeIfNeeded()
            if heard.widths.contains(where: { $0 > 0 }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        return try #require(heard.widths.last(where: { $0 > 0 }), "the strip said how wide it wants to be")
    }

    @Test func theViewAsksForTheWidthOfTheLinesItShows() async throws {
        let short = [LyricLine(time: 10, text: "Hello"), LyricLine(time: 20, text: "World")]
        let long = [
            LyricLine(time: 10, text: "Muốn giữ em lại nhưng không thể nào"), LyricLine(time: 20, text: "Vì anh biết rằng em đã đi xa mãi mãi"),
        ]
        let shortWidth = try await reported(makeStore(elapsed: 12, lines: short))
        let longWidth = try await reported(makeStore(elapsed: 12, lines: long))
        #expect(shortWidth == LyricStrip(current: "Hello", next: "World").preferredWidth())
        #expect(longWidth == LyricStrip(current: long[0].text, next: long[1].text).preferredWidth())
        #expect(longWidth > shortWidth + 100)
    }

    @Test func theNoteAloneAsksForALittleAndTheLineBeforeTheFirstIsTheOneComingNext() async throws {
        let lines = [LyricLine(time: 10, text: "the first line"), LyricLine(time: 20, text: "the second line")]
        // Before the first line: the note, and the first line as the one coming next.
        let before = try await reported(makeStore(elapsed: 2, lines: lines))
        #expect(before == LyricStrip(current: nil, next: "the first line").preferredWidth())
        #expect(before > LyricStrip.waiting.preferredWidth())
    }
}
