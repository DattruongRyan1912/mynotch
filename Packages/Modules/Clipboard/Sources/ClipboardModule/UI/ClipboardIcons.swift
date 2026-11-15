import AppKit

/// App and file icons for the cards. Each lookup asks LaunchServices, so it happens once per app or file.
enum ClipboardIcons {
    /// nil values remember apps that are not installed.
    private static var appIcons: [String: NSImage?] = [:]
    private static let fileIcons = NSCache<NSString, NSImage>()
    /// Fast URL-keyed L1 cache so scroll redraws avoid `URL.path` + `NSString` bridging on every frame.
    private static var fileURLCache: [URL: NSImage] = [:]
    private static let fileURLCacheLimit = 256

    /// Draws `source` into an explicit bitmap `CGImage` once so SwiftUI never re-invokes `IconServices` on scroll.
    private static func rasterized(_ source: NSImage, pointSize: CGFloat) -> NSImage {
        let pixelSide = Int(pointSize * 2)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: pixelSide, height: pixelSide, bitsPerComponent: 8, bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { return source }
        let previous = NSGraphicsContext.current
        defer { NSGraphicsContext.current = previous }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        source.draw(in: NSRect(x: 0, y: 0, width: pixelSide, height: pixelSide), from: .zero, operation: .copy, fraction: 1)
        guard let cgImage = context.makeImage() else { return source }
        return NSImage(cgImage: cgImage, size: NSSize(width: pointSize, height: pointSize))
    }

    /// nil when no app with this bundle ID is installed.
    static func app(bundleID: String) -> NSImage? {
        if let cached = appIcons[bundleID] { return cached }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { rasterized(NSWorkspace.shared.icon(forFile: $0.path(percentEncoded: false)), pointSize: 32) }
        appIcons[bundleID] = icon
        return icon
    }

    /// The Finder icon of a copied file; a generic one once the file is gone.
    static func file(_ url: URL) -> NSImage {
        if let cached = fileURLCache[url] { return cached }
        let path = url.path(percentEncoded: false)
        let pathKey = path as NSString
        let icon: NSImage
        if let cached = fileIcons.object(forKey: pathKey) {
            icon = cached
        } else if !FileManager.default.fileExists(atPath: path) {
            let extKey = "ext:\(url.pathExtension.lowercased())" as NSString
            if let cached = fileIcons.object(forKey: extKey) {
                fileIcons.setObject(cached, forKey: pathKey)
                icon = cached
            } else {
                let rendered = rasterized(NSWorkspace.shared.icon(forFile: path), pointSize: 48)
                fileIcons.setObject(rendered, forKey: extKey)
                fileIcons.setObject(rendered, forKey: pathKey)
                icon = rendered
            }
        } else {
            let rendered = rasterized(NSWorkspace.shared.icon(forFile: path), pointSize: 48)
            fileIcons.setObject(rendered, forKey: pathKey)
            icon = rendered
        }
        if fileURLCache.count >= fileURLCacheLimit { fileURLCache.removeAll(keepingCapacity: true) }
        fileURLCache[url] = icon
        return icon
    }
}
