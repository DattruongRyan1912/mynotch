import AppKit
import SwiftUI
import Testing
@testable import TranslationModule

/// The tab hosted in a window that is never shown, which SwiftUI still lays out and runs the lifecycle of.
@Suite struct TranslationTabViewTests {
    let fixture = ModuleFixture()

    func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() { try await Task.sleep(for: .milliseconds(20)) }
    }

    @Test func aVoiceStopsWhenTheTabLeavesTheScreen() async throws {
        await fixture.start()
        let tab = try #require(fixture.module.makeTab())
        let hosting = NSHostingView(rootView: AnyView(tab.content.frame(width: 452, height: 176)))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 452, height: 176), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        // Appearing is what lists the system's voices, in the background.
        try await waitFor { fixture.module.speech.canSpeak(.en) }
        #expect(fixture.synthesizer.voiceLoads == 1)

        fixture.module.speech.toggle(.original, text: "Hello", language: .en)
        #expect(fixture.synthesizer.active != nil)
        hosting.rootView = AnyView(EmptyView())
        try await waitFor { fixture.synthesizer.active == nil }
        #expect(fixture.synthesizer.active == nil)
        #expect(fixture.module.speech.speaking == nil)
        window.contentView = nil
    }

    /// What the tab has for its content: the height it declares less the notch's bottom padding and, with two or more
    /// tabs, the tab bar.
    @Test func theReplaceRowFitsTheTabAtTheNarrowestNotch() async throws {
        await fixture.start()
        fixture.accessibility.selections = ["Hello, how are you today?"]
        await fixture.pressShortcutAndRead()
        await fixture.translated()
        let tab = try #require(fixture.module.makeTab())
        // The row at its fullest: the hint, and the reason the last replacement failed.
        fixture.state.needsAccessibility = true
        fixture.state.replaceFailure = "Vùng chọn đã đổi, nên chưa thay được"
        #expect(fixture.state.showsReplace)
        // The narrowest open notch is 480 pt wide, 28 of them padding.
        let height = NSHostingView(rootView: tab.content.frame(width: 452)).fittingSize.height
        let declared = try #require(tab.preferredHeight)
        #expect(height <= declared - 14 - 30)
    }

    /// The box is about 205 pt wide and a good 160 pt tall. A time, with its three lines and the note on how it was read,
    /// is the longest thing a conversion shows, and it must not need scrolling.
    @Test func aTimeFitsTheOutputBoxWithoutScrolling() throws {
        let lines = [
            ConversionLine(label: "Giờ máy · UTC+7", text: "06:00 (hôm sau)"),
            ConversionLine(label: "London · UTC+0", text: "23:00"),
            ConversionLine(label: "Tokyo · UTC+9", text: "08:00 (hôm sau)"),
        ]
        let conversion = Conversion(source: "3pm PST", outcome: .lines(lines), note: "Hiểu là 15:00, Los Angeles · UTC-8")
        let list = ConversionListView(conversions: [conversion], isCompact: false, copy: { _ in })
        let height = NSHostingView(rootView: list.frame(width: 205)).fittingSize.height
        #expect(height <= 176 - 16)
        // With the heading, still room for a second quantity's single line.
        let withHeading = ConversionListView(conversions: [conversion], isCompact: true, copy: { _ in })
        #expect(NSHostingView(rootView: withHeading.frame(width: 205)).fittingSize.height <= 176 - 16)
    }

    @Test func aRateConversionFitsToo() throws {
        var conversion = Conversion(source: "12 USD", outcome: .lines([ConversionLine(text: "300.000 ₫")]), creditsRates: true)
        conversion.note = "Tỷ giá ngày 15/01/2026, chưa lấy được tỷ giá mới"
        let list = ConversionListView(conversions: [conversion], isCompact: true, copy: { _ in })
        #expect(NSHostingView(rootView: list.frame(width: 205)).fittingSize.height <= 176 - 16)
    }

    @Test func theTabShowsAConversionInPlaceOfATranslation() async throws {
        await fixture.start()
        let tab = try #require(fixture.module.makeTab())
        let translator = try #require(fixture.module.translator)
        translator.submit("72 °F")
        await fixture.translated()
        let hosting = NSHostingView(rootView: AnyView(tab.content.frame(width: 452, height: 176)))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 452, height: 176), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        #expect(fixture.state.showsConversionsOnly)
        #expect(hosting.fittingSize.height <= 176)
        window.contentView = nil
    }

    @Test func theFootnoteCarriesTheRatesCreditAsALink() throws {
        var rates = Conversion(source: "$12", outcome: .fetching, creditsRates: true)
        #expect(String(ConversionListView.footnoteText(rates).characters) == "Rates By Exchange Rate API")
        rates.note = "Tỷ giá ngày 15/01/2026"
        let text = ConversionListView.footnoteText(rates)
        #expect(String(text.characters) == "Tỷ giá ngày 15/01/2026 · Rates By Exchange Rate API")
        let links = text.runs.compactMap(\.link)
        #expect(links == [URL(string: "https://www.exchangerate-api.com")!])
        let time = Conversion(source: "3pm PST", outcome: .lines([]), note: "Hiểu là 15:00, Los Angeles · UTC-8")
        #expect(String(ConversionListView.footnoteText(time).characters) == "Hiểu là 15:00, Los Angeles · UTC-8")
        #expect(ConversionListView.footnoteText(time).runs.compactMap(\.link).isEmpty)
    }

    @Test func aCompactResultReadsQuantityThenAnswer() {
        let text = ConversionListView.inlineText(source: "12 USD", result: "300.000 ₫")
        #expect(String(text.characters) == "12 USD  →  300.000 ₫")
        #expect(text.runs.count == 2)
    }

    @Test func amountsOnTheSameRatesShareOneFootnote() {
        func money(_ note: String?, fetching: Bool = false) -> Conversion {
            Conversion(source: "$1", outcome: fetching ? .fetching : .lines([ConversionLine(text: "25.000 ₫")]), note: note, creditsRates: true)
        }
        let same = [money("Tỷ giá ngày 15/01/2026"), Conversion(source: "5 kg", outcome: .lines([ConversionLine(text: "11 lb")])), money("Tỷ giá ngày 15/01/2026")]
        #expect((0..<3).map { ConversionListView.showsFootnote(of: same, at: $0) } == [true, false, false])
        // Still waiting for the rates, or other rates: its own.
        let different = [money("Tỷ giá ngày 15/01/2026"), money(nil, fetching: true)]
        #expect((0..<2).map { ConversionListView.showsFootnote(of: different, at: $0) } == [true, true])
        let times = [
            Conversion(source: "3pm PST", outcome: .lines([]), note: "Hiểu là 15:00, Los Angeles · UTC-8"),
            Conversion(source: "4pm PST", outcome: .lines([]), note: "Hiểu là 16:00, Los Angeles · UTC-8"),
        ]
        #expect((0..<2).map { ConversionListView.showsFootnote(of: times, at: $0) } == [true, true])
    }
}
