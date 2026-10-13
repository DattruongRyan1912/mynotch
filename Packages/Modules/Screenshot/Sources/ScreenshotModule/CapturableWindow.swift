import CoreGraphics
import Foundation

/// One on-screen window that window mode can capture. Named so it does not clash with NotchUI's `WindowInfo`.
nonisolated struct CapturableWindow: Equatable, Sendable {
    var id: CGWindowID
    var ownerPID: pid_t
    var layer: Int
    /// CG global points: origin at the top-left of the primary display, y grows downwards.
    var bounds: CGRect
    /// May be missing; window titles in particular need Screen Recording access.
    var ownerName: String?
    var title: String?

    /// Reads `CGWindowListCopyWindowInfo` entries, keeping their front-to-back order and skipping malformed ones
    /// and fully transparent ones, which cannot be seen and so must not be highlighted or captured.
    static func parse(_ list: [[String: Any]]) -> [CapturableWindow] {
        list.compactMap { info in
            guard let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return nil }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha == 0 { return nil }
            return CapturableWindow(
                id: id, ownerPID: pid, layer: layer, bounds: bounds,
                ownerName: info[kCGWindowOwnerName as String] as? String,
                title: info[kCGWindowName as String] as? String
            )
        }
    }
}
