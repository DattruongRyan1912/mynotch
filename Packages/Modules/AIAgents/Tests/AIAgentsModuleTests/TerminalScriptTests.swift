import Foundation
import Testing
@testable import AIAgentsModule

/// The AppleScript that selects a tab. It is never run here: the text is checked, and a fake runner stands in for the real one.
@Suite struct TerminalScriptTests {
    let forbidden = ["keystroke", "key code", "do script", "write text", "System Events", "quit", "close", "delete", "do shell script", "run script"]

    @Test func terminalScriptSelectsTheTabWithThatTtyByTheAppsBundleIdentifier() throws {
        let script = try #require(TerminalScript.selectTab(of: .terminal, tty: "/dev/ttys003"))
        #expect(script.contains(#"tell application id "com.apple.Terminal""#))
        #expect(script.contains(#"tty of t is "/dev/ttys003""#))
        #expect(script.contains("set selected tab of w to t"))
        #expect(script.contains(#"return "found""#))
        #expect(script.contains(#"return "none""#))
    }

    @Test func iTermScriptSelectsTheSessionWithThatTty() throws {
        let script = try #require(TerminalScript.selectTab(of: .iTerm, tty: "/dev/ttys011"))
        #expect(script.contains(#"tell application id "com.googlecode.iterm2""#))
        #expect(script.contains(#"tty of s is "/dev/ttys011""#))
        #expect(script.contains("select s"))
        #expect(script.contains(#"return "found""#))
        #expect(script.contains(#"return "none""#))
    }

    @Test func neitherScriptEverTypesRunsOrClosesAnything() throws {
        for kind in [TerminalTarget.Kind.terminal, .iTerm] {
            let script = try #require(TerminalScript.selectTab(of: kind, tty: "/dev/ttys003"))
            for word in forbidden { #expect(!script.localizedCaseInsensitiveContains(word), "\(kind): \(word)") }
        }
    }

    @Test func onlyTheTwoTerminalsHaveAScript() {
        #expect(TerminalScript.selectTab(of: .editor, tty: "/dev/ttys003") == nil)
        #expect(TerminalScript.selectTab(of: .other, tty: "/dev/ttys003") == nil)
    }

    @Test func aTtyThatIsNotADeviceNeverReachesTheScript() {
        let bad = [
            #"/dev/ttys003" & (do shell script "x") & ""#, "ttys003", "/dev/ttys003\n", "/dev/../etc/passwd", "", "/dev/tty s1", "/dev/ttys003\"",
            "/dev/ttys0\u{202E}3",
        ]
        for tty in bad {
            #expect(TerminalScript.selectTab(of: .terminal, tty: tty) == nil, "\(tty)")
            #expect(TerminalScript.selectTab(of: .iTerm, tty: tty) == nil, "\(tty)")
        }
    }

    @Test func theRunnerTellsAMissingPermissionFromOtherFailures() {
        #expect(SystemAppleScriptRunner.result(errorNumber: -1743, value: nil) == .notPermitted)
        #expect(SystemAppleScriptRunner.result(errorNumber: -1744, value: nil) == .notPermitted)
        #expect(SystemAppleScriptRunner.result(errorNumber: -600, value: nil) == .failed)
        #expect(SystemAppleScriptRunner.result(errorNumber: -1728, value: "found") == .failed)
        #expect(SystemAppleScriptRunner.result(errorNumber: nil, value: "found") == .value("found"))
        #expect(SystemAppleScriptRunner.result(errorNumber: nil, value: nil) == .value(nil))
    }
}
