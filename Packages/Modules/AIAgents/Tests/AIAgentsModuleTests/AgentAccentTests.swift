import AppKit
import NotchUI
import SwiftUI
import Testing
@testable import AIAgentsModule

/// A colour no part of the tab draws with, so a pass can only mean that a view took the accent its environment gave it.
private let probeGreen = Color(.sRGB, red: 0, green: 1, blue: 0)

/// The accent the user picked, in the marks of the agents tab and activity. The environment is what the notch gives its
/// content; a view that asked for the notch's own purple instead would show it under any other accent.
@Suite struct AgentAccentTests {
    let actions = AgentTabActions(jump: { _ in false }, openFolder: { _ in }, copyPath: { _ in }, decide: { _, _ in })

    func row(_ state: AgentState) -> AgentTabState.Row {
        var session = AgentSession(key: AgentSessionKey(source: .claude, sessionID: "s1"), lastEventAt: Date(timeIntervalSince1970: 100))
        session.cwd = "/Users/example/Projects/MyNotch"
        session.branch = "main"
        session.state = state
        return AgentTabState.Row(session)
    }

    /// The view as the notch shows it: over black, in the dark scheme.
    func bitmap<Content: View>(of view: Content) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark).background(Color.black))
        renderer.scale = 2
        return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    }

    func count(in bitmap: NSBitmapImageRep, where isMatch: (NSColor) -> Bool) -> Int {
        var matches = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                if let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), isMatch(pixel) { matches += 1 }
            }
        }
        return matches
    }

    /// Pixels whose colour is mostly green, as the probe accent draws them, however far text smoothing took them to black.
    func isGreenish(_ pixel: NSColor) -> Bool {
        pixel.greenComponent > 0.4 && pixel.greenComponent > 2 * pixel.redComponent && pixel.greenComponent > 2 * pixel.blueComponent
    }

    /// Pixels whose colour is mostly blue with some red: the notch's own purple, which nothing may draw under another accent.
    func isNotchPurple(_ pixel: NSColor) -> Bool {
        pixel.blueComponent > 0.4 && pixel.blueComponent > 1.5 * pixel.redComponent && pixel.blueComponent > 2 * pixel.greenComponent
    }

    // MARK: the session's state

    @Test func aWorkingSessionsChipIsDrawnInTheEnvironmentsAccent() throws {
        let view = AgentSessionRow(row: row(.working(tool: nil, summary: nil)), actions: actions).frame(width: 420).environment(\.notchAccent, probeGreen)
        let bitmap = try bitmap(of: view)
        #expect(count(in: bitmap, where: isGreenish) > 20)
        #expect(count(in: bitmap, where: isNotchPurple) == 0, "nothing is left in the notch's own purple")
    }

    @Test func aSessionThatIsNotWorkingKeepsItsOwnColourWhateverTheAccentIs() throws {
        for state in [AgentState.waitingForInput, .idle, .error] {
            let view = AgentSessionRow(row: row(state), actions: actions).frame(width: 420).environment(\.notchAccent, probeGreen)
            #expect(try count(in: bitmap(of: view), where: isGreenish) == 0, "\(state)")
        }
    }

    // MARK: Codex's limits

    @Test func aLimitBarThatIsNotNearlyFullIsDrawnInTheEnvironmentsAccent() throws {
        let bar = AgentTabState.LimitBar(id: "5h", label: "5h", percent: 40, resets: nil)
        let bitmap = try bitmap(of: AgentUsageFooter(usage: [], limits: [bar]).frame(width: 300).environment(\.notchAccent, probeGreen))
        #expect(count(in: bitmap, where: isGreenish) > 20)
        #expect(count(in: bitmap, where: isNotchPurple) == 0, "nothing is left in the notch's own purple")
    }

    @Test func aLimitBarNearlyFullKeepsItsWarningColourWhateverTheAccentIs() throws {
        for percent in [75, 95] {
            let bar = AgentTabState.LimitBar(id: "5h", label: "5h", percent: percent, resets: nil)
            let view = AgentUsageFooter(usage: [], limits: [bar]).frame(width: 300).environment(\.notchAccent, probeGreen)
            #expect(try count(in: bitmap(of: view), where: isGreenish) == 0, "\(percent) %")
        }
    }

    // MARK: the glyph's count

    @Test func theSubagentCountOnTheGlyphIsDrawnInTheEnvironmentsAccent() throws {
        let content = AgentActivityContent(kind: .working(since: Date(timeIntervalSince1970: 0)), source: .claude, subagents: 3)
        let view = AgentActivityLeading(content: content).frame(width: 32, height: 32).environment(\.notchAccent, probeGreen)
        let bitmap = try bitmap(of: view)
        #expect(count(in: bitmap, where: isGreenish) > 10)
        #expect(count(in: bitmap, where: isNotchPurple) == 0, "nothing is left in the notch's own purple")
    }

    @Test func theCountStaysReadableOnALightAccent() {
        let white = Color.white
        // The palette colours as macOS shows them on a dark surface (blue, purple, pink, red) keep the white they always had.
        for accent in [NotchAccent.Palette.blue, .purple, .pink, .red].map(\.rgb.color) {
            #expect(AccentLabel.colour(on: accent) == white)
        }
        // Yellow, orange and green are too light for white to be read on them.
        for accent in [NotchAccent.Palette.yellow, .orange, .green].map(\.rgb.color) {
            #expect(AccentLabel.colour(on: accent) != white)
        }
    }
}
