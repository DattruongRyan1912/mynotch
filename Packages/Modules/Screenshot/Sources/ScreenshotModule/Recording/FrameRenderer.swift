import CoreGraphics
import CoreImage
import CoreVideo
import Metal

/// Draws one frame of the edited video: the part of the picture the camera sees, scaled to fill the output, with the click
/// rings over it. Used by the compositor for the preview and the export alike.
///
/// Colour is not managed: the pixels go in and come out as the numbers they are, so a frame that is not cropped or scaled
/// leaves exactly as it came. A fractional crop is a transform of the whole picture, sampled in between pixels, so a camera
/// that moves a fraction of a pixel per frame moves smoothly instead of in pixel steps.
nonisolated final class FrameRenderer: @unchecked Sendable {
    /// One context for the whole app, drawing on the GPU. AVFoundation makes a new compositor, and so a new renderer, for every
    /// player item and every export, and a context takes much longer to make than a frame takes to draw; sharing it also lets
    /// the preview and an export queue their work on the same device. A context is safe to use from any thread.
    private static let sharedContext: CIContext = {
        let options: [CIContextOption: Any] = [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(), .cacheIntermediates: false]
        guard let device = MTLCreateSystemDefaultDevice() else { return CIContext(options: options) }
        return CIContext(mtlDevice: device, options: options)
    }()

    private var context: CIContext { Self.sharedContext }

    /// `crop` is in pixels of `source`, origin at its top-left. The picture is scaled to the size of `destination`; a
    /// `source` of nil (a gap in the video) leaves black.
    func render(source: CVPixelBuffer?, crop: CGRect, rings: [ClickEffect.Ring], into destination: CVPixelBuffer) {
        let width = CGFloat(CVPixelBufferGetWidth(destination)), height = CGFloat(CVPixelBufferGetHeight(destination))
        let output = CGRect(x: 0, y: 0, width: width, height: height)
        var image: CIImage
        var scaleX = 1.0, scaleY = 1.0
        if let source, crop.width > 0, crop.height > 0 {
            let sourceHeight = CGFloat(CVPixelBufferGetHeight(source))
            scaleX = width / crop.width
            scaleY = height / crop.height
            // Core Image has its origin at the bottom-left; the crop is measured from the top-left.
            let transform = CGAffineTransform(translationX: -crop.minX, y: -(sourceHeight - crop.maxY))
                .concatenating(CGAffineTransform(scaleX: scaleX, y: scaleY))
            image = CIImage(cvPixelBuffer: source).clampedToExtent()
                .transformed(by: transform, highQualityDownsample: scaleX < 1 || scaleY < 1)
                .cropped(to: output)
        } else {
            image = CIImage(color: .black).cropped(to: output)
        }
        for ring in rings {
            let centerX = (ring.x - crop.minX) * scaleX
            let centerY = height - (ring.y - crop.minY) * scaleY
            let radius = ring.radius * (scaleX + scaleY) / 2
            if let sprite = Self.sprite(radius: radius, opacity: ring.opacity, centerX: centerX, centerY: centerY, in: output) {
                image = sprite.composited(over: image)
            }
        }
        context.render(image, to: destination, bounds: output, colorSpace: nil)
    }

    /// A ring as a small picture placed where it belongs, or nil when it is wholly outside the output or invisible.
    private static func sprite(radius: Double, opacity: Double, centerX: Double, centerY: Double, in output: CGRect) -> CIImage? {
        let stroke = max(2, radius * 0.12)
        let reach = radius + stroke + 2
        guard opacity > 0.001, radius > 0.5,
              CGRect(x: centerX - reach, y: centerY - reach, width: reach * 2, height: reach * 2).intersects(output) else { return nil }
        let side = min(Int(ceil(reach * 2)), 4_096)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let bitmap = CGContext(
                  data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              ) else { return nil }
        let middle = CGPoint(x: CGFloat(side) / 2, y: CGFloat(side) / 2)
        let circle = CGRect(x: middle.x - radius, y: middle.y - radius, width: radius * 2, height: radius * 2)
        // A tinted disc, a dark thin edge for light backgrounds, and a bright ring on top.
        bitmap.setFillColor(CGColor(srgbRed: 0.2, green: 0.55, blue: 1, alpha: 0.3 * opacity))
        bitmap.fillEllipse(in: circle)
        bitmap.setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.3 * opacity))
        bitmap.setLineWidth(stroke + 2)
        bitmap.strokeEllipse(in: circle)
        bitmap.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95 * opacity))
        bitmap.setLineWidth(stroke)
        bitmap.strokeEllipse(in: circle)
        guard let picture = bitmap.makeImage() else { return nil }
        return CIImage(cgImage: picture)
            .transformed(by: CGAffineTransform(translationX: centerX - CGFloat(side) / 2, y: centerY - CGFloat(side) / 2))
    }
}
