import AppKit
import MyNotchCore
import SwiftUI
import Testing
@testable import AIAgentsModule

/// Counts the passes in which SwiftUI evaluates and lays out the views of a hosting view.
final class CountingHostingView<Content: View>: NSHostingView<Content> {
    private(set) var layouts = 0

    override func layout() {
        layouts += 1
        super.layout()
    }
}

/// The glyph beside the closed notch, in a hosting view in a window that is never shown, with the run loop ticking.
@Suite struct AgentActivityViewsTests {
    /// How often SwiftUI laid the hosting view out while `content` ran for `seconds`, after it had settled.
    func layoutPasses(of content: AgentActivityContent, for seconds: TimeInterval) -> Int {
        let hosting = CountingHostingView(rootView: AgentActivityLeading(content: content))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 60, height: 40), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let settled = hosting.layouts
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        let passes = hosting.layouts - settled
        window.contentView = nil
        return passes
    }

    /// The point of it: a repeating pulse symbol effect redraws the glyph at the display's refresh rate, so the notch's hosting
    /// view laid out and committed continuously for as long as an agent was working, which can be hours.
    @Test func aWorkingAgentsGlyphNeverKeepsTheHostingViewLayingOut() {
        let working = AgentActivityContent(kind: .working(since: Date()), source: .claude)
        #expect(layoutPasses(of: working, for: 0.5) == 0)
    }

    @Test(arguments: [AgentSource.claude, .codex])
    func eachAgentHasItsGlyph(source: AgentSource) {
        for kind in [AgentActivityContent.Kind.waitingForInput, .finished, .working(since: Date())] {
            let content = AgentActivityContent(kind: kind, source: source)
            #expect(layoutPasses(of: content, for: 0.05) == 0)
        }
    }
}
