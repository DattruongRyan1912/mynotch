import CoreGraphics
import Foundation
import os
@testable import ShelfModule

/// Recognition that answers from a closure and remembers what it was asked, so no test needs Vision.
nonisolated final class FakeRecognizer: TextRecognizing {
    typealias Handler = @Sendable (CGImage) async throws -> String

    private let handler: Handler
    private let calls = OSAllocatedUnfairLock(initialState: [(width: Int, languages: [String])]())

    init(_ handler: @escaping Handler = { _ in "chữ" }) { self.handler = handler }

    var requests: [(width: Int, languages: [String])] { calls.withLock { $0 } }

    func recognize(_ image: CGImage, languages: [String]) async throws -> String {
        calls.withLock { $0.append((image.width, languages)) }
        return try await handler(image)
    }
}

/// A cutter that answers from a closure; the default makes the left half of the picture transparent.
nonisolated final class FakeCutter: ForegroundCutting {
    typealias Handler = @Sendable (CGImage) async throws -> CGImage

    private let handler: Handler
    private let count = OSAllocatedUnfairLock(initialState: 0)

    init(_ handler: @escaping Handler = { image in FakeCutter.leftHalfCleared(image) }) { self.handler = handler }

    var calls: Int { count.withLock { $0 } }

    func cutOut(_ image: CGImage) async throws -> CGImage {
        count.withLock { $0 += 1 }
        return try await handler(image)
    }

    static func leftHalfCleared(_ image: CGImage) -> CGImage {
        let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.clear(CGRect(x: 0, y: 0, width: image.width / 2, height: image.height))
        return context.makeImage()!
    }
}

/// Makes decoded images whose memory is counted, to see how many are alive at once. Each image is backed by a
/// buffer that tells the counter when it is freed.
nonisolated final class ImageCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0
    private var highest = 0
    private var total = 0

    var live: Int { lock.withLock { current } }
    var peak: Int { lock.withLock { highest } }
    var made: Int { lock.withLock { total } }

    func makeImage(width: Int, height: Int) -> CGImage {
        lock.withLock {
            current += 1
            total += 1
            highest = max(highest, current)
        }
        let size = width * height * 4
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
        buffer.initializeMemory(as: UInt8.self, repeating: 200, count: size)
        let provider = CGDataProvider(dataInfo: Unmanaged.passRetained(self).toOpaque(), data: buffer, size: size) { info, data, _ in
            data.deallocate()
            let counter = Unmanaged<ImageCounter>.fromOpaque(info!).takeRetainedValue()
            counter.lock.withLock { counter.current -= 1 }
        }!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }
}
