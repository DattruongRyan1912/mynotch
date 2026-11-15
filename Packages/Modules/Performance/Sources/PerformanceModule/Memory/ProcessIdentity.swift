import AppKit

/// A process as the tab lists it: what to call it, how much it holds and its icon.
struct ProcessRow: Identifiable {
    let id: Int32
    let name: String
    let size: String
    /// Nil for a process that is not part of an app; the row then draws a plain glyph.
    let icon: NSImage?
}

/// Names and icons for the processes in the list. A process that is an app takes the app's name and icon, a helper inside an
/// app's bundle keeps its own name with the app's icon, anything else has its executable's name and no icon.
final class ProcessIdentity {
    /// Icons by app path; the list changes only a little from one read to the next, so this stays small, and it is emptied
    /// before it could grow without limit.
    private var icons: [String: NSImage] = [:]
    static let iconLimit = 32

    func rows(for processes: [ProcessMemory]) -> [ProcessRow] {
        processes.map { process in
            let app = NSRunningApplication(processIdentifier: process.pid)
            let bundlePath = app?.bundleURL?.path ?? process.path.flatMap(ProcessRanking.appBundlePath(of:))
            return ProcessRow(
                id: process.pid, name: app?.localizedName ?? process.name, size: MemoryFormat.bytes(process.footprint),
                icon: bundlePath.map { icon(ofAppAt: $0) }
            )
        }
    }

    func rows(for processes: [ProcessCPU]) -> [ProcessRow] {
        processes.map { process in
            let app = NSRunningApplication(processIdentifier: process.pid)
            let bundlePath = app?.bundleURL?.path ?? process.path.flatMap(ProcessRanking.appBundlePath(of:))
            let percentText = String(format: "%.1f%%", process.percent)
            return ProcessRow(
                id: process.pid, name: app?.localizedName ?? process.name, size: percentText,
                icon: bundlePath.map { icon(ofAppAt: $0) }
            )
        }
    }

    private func icon(ofAppAt path: String) -> NSImage {
        if let cached = icons[path] { return cached }
        if icons.count >= Self.iconLimit { icons.removeAll() }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons[path] = icon
        return icon
    }

    /// How many icons are kept (for tests).
    var cachedIcons: Int { icons.count }
}
