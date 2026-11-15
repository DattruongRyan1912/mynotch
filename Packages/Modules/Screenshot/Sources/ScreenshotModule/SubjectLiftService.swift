import CoreGraphics
import CoreImage
import Foundation
import Vision

/// Service that lifts foreground subjects from images using Apple Vision framework or pure CoreGraphics operations.
public nonisolated struct SubjectLiftService: Sendable {
    public init() {}

    /// Uses `VNGenerateForegroundInstanceMaskRequest` on Neural Engine / GPU to isolate subjects with transparent alpha.
    @concurrent
    public func liftSubject(from image: CGImage, cropToSubject: Bool = true) async throws -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first else { return nil }
        guard !observation.allInstances.isEmpty else { return nil }

        let pixelBuffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: cropToSubject
        )

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return cgImage
    }

    /// Crops an image to the smallest bounding box containing non-transparent pixels.
    public static func cropToNonTransparentBounds(_ image: CGImage, alphaThreshold: UInt8 = 10) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var rawData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        // Flip coordinates so row 0 in rawData corresponds to top-most row of image
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1.0, y: -1.0)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var maxX = -1
        var minY = height
        var maxY = -1

        for y in 0..<height {
            let rowOffset = y * bytesPerRow
            for x in 0..<width {
                let alpha = rawData[rowOffset + x * bytesPerPixel + 3]
                if alpha > alphaThreshold {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }

        let cropRect = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
        return image.cropping(to: cropRect)
    }

    /// Applies an alpha mask to source and optionally crops to non-transparent bounds.
    public static func applyAlphaMask(_ mask: CGImage, to source: CGImage, cropToBounds: Bool = false) -> CGImage? {
        let width = source.width
        let height = source.height
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.clip(to: bounds, mask: mask)
        context.draw(source, in: bounds)

        guard let masked = context.makeImage() else { return nil }
        if cropToBounds {
            return cropToNonTransparentBounds(masked) ?? masked
        }
        return masked
    }
}
