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
}
