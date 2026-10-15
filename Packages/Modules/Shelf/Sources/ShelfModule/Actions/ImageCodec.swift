import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reading and writing images with ImageIO. Pictures are always handled upright: a camera's sideways pixels and
/// their orientation tag become turned pixels and no tag, so no program turns them a second time.
nonisolated enum ImageCodec {
    /// An image decoded upright, with the properties of the file it came from.
    struct Loaded {
        let image: CGImage
        let properties: [CFString: Any]
        /// The format the file has; nil for one the shelf cannot write (GIF, WebP, BMP…).
        let format: ImageFormat?
    }

    /// Decodes the first picture of the file, at most `limit` pixels on the longest side (never enlarged).
    static func load(_ url: URL, longestSide limit: Int?) throws -> Loaded {
        let source = try openSource(url)
        let properties = try fileProperties(of: source)
        let size = uprightSize(from: properties)
        let side = min(limit ?? Int(max(size.width, size.height)), Int(max(size.width, size.height)))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, side),
        ]
        // A file that stops short still decodes to a partly grey picture, so the decoder's verdict is checked.
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { throw FileActionError.notAnImage }
        let format = (CGImageSourceGetType(source) as String?).flatMap(UTType.init).flatMap(ImageFormat.init)
        return Loaded(image: image, properties: properties, format: format)
    }

    /// The size the picture has when shown, from the file's properties alone.
    static func uprightSize(of url: URL) throws -> CGSize {
        uprightSize(from: try fileProperties(of: try openSource(url)))
    }

    /// The image written as `format`. `properties` are the ones the file had; they go along (camera, dates, colour
    /// profile) except the location, when `stripLocation` is on, and what describes the pixels or their turn.
    static func encode(_ image: CGImage, as format: ImageFormat, quality: Double, properties: [CFString: Any], stripLocation: Bool) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.utType.identifier as CFString, 1, nil) else {
            throw FileActionError.encoderUnavailable(format)
        }
        var options = metadata(from: properties, for: image, stripLocation: stripLocation)
        if format.isLossy { options[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(destination, format.hasAlpha ? image : flattenedOnWhite(image), options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FileActionError.encoderUnavailable(format) }
        return data as Data
    }

    private static func openSource(_ url: URL) throws -> CGImageSource {
        guard FileManager.default.fileExists(atPath: url.path) else { throw FileActionError.missing }
        guard FileManager.default.isReadableFile(atPath: url.path) else { throw FileActionError.unreadable }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { throw FileActionError.notAnImage }
        return source
    }

    private static func fileProperties(of source: CGImageSource) throws -> [CFString: Any] {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { throw FileActionError.notAnImage }
        return properties
    }

    private static func uprightSize(from properties: [CFString: Any]) -> CGSize {
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0, height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        // Orientations 5 to 8 show the picture on its side.
        let isSideways = (5...8).contains(properties[kCGImagePropertyOrientation] as? Int ?? 1)
        return isSideways ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    private static func metadata(from properties: [CFString: Any], for image: CGImage, stripLocation: Bool) -> [CFString: Any] {
        var result = properties
        for key in [
            kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight, kCGImagePropertyDepth, kCGImagePropertyColorModel,
            kCGImagePropertyProfileName, kCGImagePropertyHasAlpha,
        ] { result[key] = nil }
        if stripLocation {
            result[kCGImagePropertyGPSDictionary] = nil
            // Place names written as text are location too.
            if var iptc = result[kCGImagePropertyIPTCDictionary] as? [CFString: Any] {
                for key in [
                    kCGImagePropertyIPTCSubLocation, kCGImagePropertyIPTCCity, kCGImagePropertyIPTCProvinceState,
                    kCGImagePropertyIPTCCountryPrimaryLocationName, kCGImagePropertyIPTCCountryPrimaryLocationCode,
                    kCGImagePropertyIPTCContentLocationName, kCGImagePropertyIPTCContentLocationCode,
                ] { iptc[key] = nil }
                result[kCGImagePropertyIPTCDictionary] = iptc
            }
        }
        result[kCGImagePropertyOrientation] = 1
        if var tiff = result[kCGImagePropertyTIFFDictionary] as? [CFString: Any], tiff[kCGImagePropertyTIFFOrientation] != nil {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            result[kCGImagePropertyTIFFDictionary] = tiff
        }
        if var exif = result[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = image.width
            exif[kCGImagePropertyExifPixelYDimension] = image.height
            result[kCGImagePropertyExifDictionary] = exif
        }
        return result
    }

    /// JPEG has no alpha, and ImageIO would turn transparent areas black.
    private static func flattenedOnWhite(_ image: CGImage) -> CGImage {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return image
        default: break
        }
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let own = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
        for space in [own, sRGB].compactMap({ $0 }) {
            guard let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { continue }
            let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(rect)
            context.draw(image, in: rect)
            if let flat = context.makeImage() { return flat }
        }
        return image
    }
}
