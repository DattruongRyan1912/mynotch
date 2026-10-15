import ClipboardMCPKit
import Foundation
import Testing
@testable import ClipboardModule

/// The lines the user pastes into their agent's own configuration, which MyNotch never writes itself.
@Suite struct ClipboardMCPSnippetsTests {
    let plain = ClipboardMCPSnippets(helperPath: "/Users/a/Library/Application Support/io.lucasvu.mynotch/Modules/clipboard/bin/mynotch-clipboard-mcp")

    @Test func claudeCodeGetsOneCommandWithThePathQuoted() {
        #expect(plain.claudeCode == "claude mcp add --scope user --transport stdio mynotch-clipboard -- '/Users/a/Library/Application Support/io.lucasvu.mynotch/Modules/clipboard/bin/mynotch-clipboard-mcp'")
    }

    @Test func aQuoteInThePathCannotEndTheShellQuoting() {
        let tricky = ClipboardMCPSnippets(helperPath: "/Users/o'neil/$HOME/`x`/mynotch-clipboard-mcp")
        #expect(tricky.claudeCode.hasSuffix("-- '/Users/o'\\''neil/$HOME/`x`/mynotch-clipboard-mcp'"))
    }

    @Test func cursorGetsTheJSONForItsMcpJSON() throws {
        let parsed = try JSON(decoding: Data(plain.cursor.utf8))
        #expect(parsed == .object(["mcpServers": .object(["mynotch-clipboard": .object([
            "type": .string("stdio"), "command": .string(plain.helperPath),
        ])])]))
        #expect(plain.cursor.contains("\n"))
    }

    @Test func theJSONEscapesWhatNeedsIt() throws {
        let tricky = ClipboardMCPSnippets(helperPath: "/a\"b\\c/x")
        let parsed = try JSON(decoding: Data(tricky.cursor.utf8))
        #expect(parsed["mcpServers"]?["mynotch-clipboard"]?["command"] == .string("/a\"b\\c/x"))
    }

    @Test func codexGetsATableForItsConfigToml() {
        #expect(plain.codex == """
            [mcp_servers.mynotch-clipboard]
            command = "\(plain.helperPath)"
            """)
        let tricky = ClipboardMCPSnippets(helperPath: "/a\"b\\c/x")
        #expect(tricky.codex.hasSuffix(#"command = "/a\"b\\c/x""#))
    }

    @Test func theNameIsOneEveryAgentAccepts() {
        #expect(ClipboardMCPSnippets.serverName.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
    }

    @Test func theSnippetsNameTheFilesTheyBelongIn() {
        #expect(ClipboardMCPSnippets.cursorFile == "~/.cursor/mcp.json")
        #expect(ClipboardMCPSnippets.codexFile == "~/.codex/config.toml")
    }
}
