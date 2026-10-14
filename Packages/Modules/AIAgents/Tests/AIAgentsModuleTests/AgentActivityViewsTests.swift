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

@Suite struct AgentGlyphPulseTests {
    func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendants)
    }

    /// The glyph's own hosting view, where the pulse runs on its layer, inside the view of `notchPulse`.
    func glyphHost(for content: AgentActivityContent) -> (host: NSView, window: NSWindow)? {
        let hosting = NSHostingView(rootView: AgentActivityLeading(content: content).frame(width: 16, height: 16))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 60, height: 40), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        guard let pulse = descendants(of: hosting).first(where: { String(describing: type(of: $0)).hasPrefix("NotchPulseView") }),
              let host = pulse.subviews.first else { return nil }
        return (host, window)
    }

    @Test func aWorkingGlyphIsDrawnAndPulsesOnItsLayer() throws {
        let (host, window) = try #require(glyphHost(for: AgentActivityContent(kind: .working(since: Date()), source: .claude)))
        #expect(host.frame.width > 8 && host.frame.height > 8)
        #expect(host.layer?.animationKeys()?.isEmpty == false)
        window.contentView = nil
    }

    @Test(arguments: [AgentActivityContent.Kind.waitingForInput, .finished])
    func aGlyphThatIsNotWorkingDoesNotPulse(kind: AgentActivityContent.Kind) throws {
        let (host, window) = try #require(glyphHost(for: AgentActivityContent(kind: kind, source: .codex)))
        #expect(host.frame.width > 8)
        #expect(host.layer?.animationKeys() == nil)
        window.contentView = nil
    }
}
