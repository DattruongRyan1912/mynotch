import Foundation

/// The short text shown next to a running tool. Kept to a command's first line or a file name so it says what
/// the agent is doing without carrying file contents or prompt text.
nonisolated enum ToolSummary {
    static let maxLength = 120

    /// The first non-blank line of a shell command.
    static func command(_ command: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstLine = trimmed.split(whereSeparator: \.isNewline).first else { return nil }
        return clipped(firstLine.trimmingCharacters(in: .whitespaces))
    }

    /// The last path component: enough to recognise the file in one line.
    static func fileName(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return clipped((trimmed as NSString).lastPathComponent)
    }

    private static func clipped(_ text: String) -> String? {
        text.isEmpty ? nil : String(text.prefix(maxLength))
    }
}
