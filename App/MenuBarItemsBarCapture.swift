import AppKit
import MyNotchCore
import ScreenCaptureKit

/// What the status items really look like, captured with ScreenCaptureKit like the Screenshot module does: the window of the item
/// (layer 25, the status-bar level), so the bar shows the item as the menu bar does. Best effort: with no Screen Recording
/// permission, a window that cannot be found, or a capture that fails, the item is missing from the result and the bar shows the
/// app's icon instead. Nothing here prompts, and the images only live in the bar while it is open.
final class ScreenCaptureMenuBarItemImages: MenuBarItemImageSource {
    /// `kCGStatusWindowLevel`: the layer status items are drawn in.
    private static let statusLayer = 25
    /// How far an item's frame and its window's may differ and still be the same thing, in points.
    private static let tolerance: CGFloat = 2

    func images(for items: [MenuBarItem]) async -> [String: CGImage] {
        // `SCShareableContent` would ask for the permission if it were missing; this only looks.
        guard !items.isEmpty, CGPreflightScreenCaptureAccess() else { return [:] }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else { return [:] }
        let windows = content.windows.filter { $0.windowLayer == Self.statusLayer }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var images: [String: CGImage] = [:]
        for item in items {
            // The window server's frames, like Accessibility's, have their origin at the top left of the primary display.
            let frame = MenuBarCoordinates.accessibilityFrame(fromAppKit: item.frame, primaryHeight: primaryHeight)
            guard let window = Self.window(for: item, frame: frame, among: windows),
                  let image = try? await Self.screenshot(of: window) else { continue }
            images[item.id] = image
        }
        return images
    }

    /// The window at the item's frame, preferring one of the item's own app: where a system process draws other apps' items, the
    /// frame is all there is to go by. No frame, no match.
    private static func window(for item: MenuBarItem, frame: CGRect, among windows: [SCWindow]) -> SCWindow? {
        guard frame.width > 0, frame.height > 0 else { return nil }
        let matching = windows.filter { window in
            abs(window.frame.minX - frame.minX) <= tolerance && abs(window.frame.minY - frame.minY) <= tolerance
                && abs(window.frame.width - frame.width) <= tolerance && abs(window.frame.height - frame.height) <= tolerance
        }
        return matching.first { $0.owningApplication?.processID == item.pid } ?? matching.first
    }

    /// One image of the window at one pixel per point times its scale, in SDR, without shadow or cursor.
    private static func screenshot(of window: SCWindow) async throws -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let configuration = SCScreenshotConfiguration()
        configuration.width = Int((filter.contentRect.width * scale).rounded())
        configuration.height = Int((filter.contentRect.height * scale).rounded())
        guard configuration.width > 0, configuration.height > 0 else { return nil }
        configuration.showsCursor = false
        configuration.ignoreShadows = true
        configuration.dynamicRange = .sdr
        let output = try await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: configuration)
        return output.sdrImage
    }
}
