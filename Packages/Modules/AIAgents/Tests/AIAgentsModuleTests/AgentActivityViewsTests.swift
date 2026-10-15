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
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
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
        #expect(layoutPasses(of: working, for: 0.15) == 0)
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

/// The small count on the glyph while subagents run, drawn offscreen.
@Suite struct AgentSubagentBadgeTests {
    /// The side of a bubble's circle, which clips the glyph where the other activities sit beside the notch.
    let side: CGFloat = 32
    let scale: CGFloat = 4

    struct Picture {
        var width: Int
        var height: Int
        var bytes: [UInt8]

        /// More than anti-aliasing: a loaded machine draws the same text with edges a few levels apart.
        func differs(from other: Picture, at x: Int, _ y: Int) -> Bool {
            let index = 4 * (y * width + x)
            return (0..<4).contains { abs(Int(bytes[index + $0]) - Int(other.bytes[index + $0])) > 80 }
        }
    }

    func picture(subagents: Int) -> Picture? {
        let content = AgentActivityContent(kind: .working(since: Date(timeIntervalSince1970: 0)), source: .claude, subagents: subagents)
        let renderer = ImageRenderer(content: AgentActivityLeading(content: content).frame(width: side, height: side))
        renderer.scale = scale
        guard let image = renderer.cgImage else { return nil }
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return drawn ? Picture(width: image.width, height: image.height, bytes: bytes) : nil
    }

    /// Where the two pictures differ, in points from the centre of the frame.
    func changes(_ a: Picture, _ b: Picture) -> [CGPoint] {
        var points: [CGPoint] = []
        for y in 0..<a.height {
            for x in 0..<a.width where a.differs(from: b, at: x, y) {
                points.append(CGPoint(x: (CGFloat(x) + 0.5) / scale - side / 2, y: (CGFloat(y) + 0.5) / scale - side / 2))
            }
        }
        return points
    }

    @Test func aCountDrawsABadgeThatNoCountDoesNot() throws {
        let plain = try #require(picture(subagents: 0))
        let badged = try #require(picture(subagents: 3))
        #expect(changes(plain, badged).count > 20)
    }

    @Test func theBadgeStaysInsideTheCircleABubbleClipsTheGlyphTo() throws {
        let plain = try #require(picture(subagents: 0))
        for count in [1, 3, 9, 10, 99] {
            let badged = try #require(picture(subagents: count))
            let points = changes(plain, badged)
            let farthest = points.map { ($0.x * $0.x + $0.y * $0.y).squareRoot() }.max() ?? 0
            #expect(farthest < side / 2 - 0.5, "\(count): \(farthest) pt from the centre")
        }
    }

    @Test func aBadgeIsInTheCornerBesideTheGlyphNotOverItsMiddle() throws {
        let plain = try #require(picture(subagents: 0))
        let points = changes(plain, try #require(picture(subagents: 2)))
        let nearest = points.map { ($0.x * $0.x + $0.y * $0.y).squareRoot() }.min() ?? 0
        #expect(nearest > 1)
        #expect(points.allSatisfy { $0.x > 0 && $0.y > 0 })
    }

    @Test func aCountOverNineReadsNineAndMoreAndEveryCountIsItsOwnPicture() throws {
        let ten = try #require(picture(subagents: 10))
        let ninetyNine = try #require(picture(subagents: 99))
        #expect(changes(ten, ninetyNine).isEmpty)
        let five = try #require(picture(subagents: 5))
        let six = try #require(picture(subagents: 6))
        #expect(!changes(five, six).isEmpty)
    }
}
