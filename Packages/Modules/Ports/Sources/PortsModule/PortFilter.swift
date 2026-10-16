import Foundation

/// A short hint at what usually listens on a well-known development port.
nonisolated enum DevPortLabel {
    static let names: [UInt16: String] = [
        3000: "Node", 3001: "Node", 4200: "Angular", 5000: "Flask", 5173: "Vite", 5432: "Postgres",
        6379: "Redis", 8000: "Django", 8080: "HTTP", 8888: "Jupyter", 9000: "Dev", 27017: "MongoDB",
    ]

    static func label(for port: UInt16) -> String? { names[port] }
}

nonisolated enum PortFilter {
    /// The rows the tab shows: UDP only when asked for, then those that match what was typed.
    static func apply(_ entries: [PortEntry], query: String, showUDP: Bool) -> [PortEntry] {
        entries.filter { (showUDP || $0.proto == .tcp) && matches($0, query: query) }
    }

    /// A number matches the start of a port ("80" finds 8080 and 8000); anything else is looked for, ignoring case and accents,
    /// in the names, the command line and the hint of a well-known port.
    static func matches(_ entry: PortEntry, query: String) -> Bool {
        var text = query.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix(":") { text.removeFirst() }
        guard !text.isEmpty else { return true }
        if String(entry.port).hasPrefix(text) { return true }
        guard text.contains(where: { !$0.isNumber }) else { return false }
        let fields = [entry.process.name, entry.process.appName, entry.process.commandLine, DevPortLabel.label(for: entry.port)]
        return fields.contains { $0?.localizedStandardContains(text) ?? false }
    }
}
