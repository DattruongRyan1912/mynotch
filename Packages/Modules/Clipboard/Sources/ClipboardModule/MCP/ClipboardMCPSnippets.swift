import ClipboardMCPKit
import Foundation

/// The lines the user adds to their agent's configuration to use the helper. MyNotch only shows them: it never reads or writes
/// the agents' own files.
nonisolated struct ClipboardMCPSnippets: Equatable, Sendable {
    /// Letters, digits and hyphens: a name Claude Code, Cursor and Codex all take.
    static let serverName = "mynotch-clipboard"
    static let cursorFile = "~/.cursor/mcp.json"
    static let codexFile = "~/.codex/config.toml"

    let helperPath: String

    /// One command, run in a terminal. `--scope user` because the history is not about one project.
    var claudeCode: String {
        "claude mcp add --scope user --transport stdio \(Self.serverName) -- \(Self.shellQuoted(helperPath))"
    }

    /// The whole file, for a user who has none; with others, the entry goes inside `mcpServers`.
    var cursor: String {
        """
        {
          "mcpServers": {
            "\(Self.serverName)": {
              "type": "stdio",
              "command": \(Self.quoted(helperPath))
            }
          }
        }
        """
    }

    var codex: String {
        """
        [mcp_servers.\(Self.serverName)]
        command = \(Self.quoted(helperPath))
        """
    }

    /// Single quotes hold everything but a single quote, which is closed, escaped and opened again.
    private static func shellQuoted(_ text: String) -> String {
        "'" + text.replacing("'", with: "'\\''") + "'"
    }

    /// A JSON string, which is also a valid TOML basic string: both escape the quote, the backslash and control characters the
    /// same way.
    private static func quoted(_ text: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return (try? encoder.encode(text)).map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
    }
}
