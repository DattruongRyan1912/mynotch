import AppKit
import ScreenCaptureKit

/// Captures with ScreenCaptureKit's screenshot API (macOS 26). Needs Screen Recording; without it the first call
/// throws `permissionDenied`, and nothing here prompts.
final class ScreenCaptureKitService: CaptureService {
    func freezeDisplays() async throws -> [FrozenDisplay] {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            // MyNotch's windows (the notch) stay out of the frozen frames; the overlay is not up yet.
            let ownApplications = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            var frozen: [FrozenDisplay] = []
            for display in content.displays {
                guard let frame = Self.screenFrame(of: display) else { continue }
                let filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])
                let image = try await Self.screenshot(of: filter, includeShadow: true)
                // The scale comes from the image itself, so the crop maths can never disagree with its pixels.
                let scale = CGFloat(image.width) / frame.width
                frozen.append(FrozenDisplay(info: DisplayInfo(id: display.displayID, frame: frame, scale: scale), image: image))
            }
            guard !frozen.isEmpty else { throw CaptureError.noDisplays }
            return frozen
        } catch {
            throw Self.mapped(error)
        }
    }

    func captureWindow(id: CGWindowID, includeShadow: Bool) async throws -> CGImage {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let window = content.windows.first(where: { $0.windowID == id }) else {
                throw CaptureError.failed("Cửa sổ không còn trên màn hình")
            }
            return try await Self.screenshot(of: SCContentFilter(desktopIndependentWindow: window), includeShadow: includeShadow)
        } catch {
            throw Self.mapped(error)
        }
    }

    /// One image of what `filter` selects, at one pixel per point times the filter's scale, in SDR, without the cursor.
    private static func screenshot(of filter: SCContentFilter, includeShadow: Bool) async throws -> CGImage {
        let scale = CGFloat(filter.pointPixelScale)
        let configuration = SCScreenshotConfiguration()
        configuration.width = Int((filter.contentRect.width * scale).rounded())
        configuration.height = Int((filter.contentRect.height * scale).rounded())
        configuration.showsCursor = false
        configuration.ignoreShadows = !includeShadow
        configuration.dynamicRange = .sdr
        let output = try await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: configuration)
        guard let image = output.sdrImage else { throw CaptureError.failed("ScreenCaptureKit không trả về ảnh") }
        return image
    }

    /// The AppKit frame of the screen showing `display`, matched by its CoreGraphics display ID.
    private static func screenFrame(of display: SCDisplay) -> CGRect? {
        NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display.displayID
        }?.frame
    }

    /// A cancelled capture stays a cancellation; everything else becomes a `CaptureError`.
    private static func mapped(_ error: any Error) -> any Error {
        error is CancellationError ? error : CaptureError(error)
    }
}
