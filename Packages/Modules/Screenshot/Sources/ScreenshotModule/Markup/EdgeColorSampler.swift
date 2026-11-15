import Foundation

/// Reads the colour of a ring of pixels: the dominant one, and how far the ring is from being a single colour.
/// Smart erase uses it on the pixels around a rectangle, and the canvas padding on the capture's outermost pixels.
nonisolated enum EdgeColorSampler {
    /// Pixels wide: enough to dodge a stray anti-aliased pixel, narrow enough to stay at the edge.
    static let ringWidth = 2
    /// The ring counts as one colour while the variance of its pixels, averaged over the four channels in 0…255
    /// units, stays at or below this: a standard deviation of 8 levels, which allows a little compression noise or a
    /// faint gradient but not text, a seam or a different background.
    static let uniformVarianceLimit = 64.0

    struct Sample: Equatable {
        /// The average of the pixels in the most common colour bucket.
        var dominant: RawPixel
        var variance: Double

        var isUniform: Bool { variance <= EdgeColorSampler.uniformVarianceLimit }
    }

    /// The pixels of `outer` that are not in `inner`, both clipped to `buffer`, or nil when there are none.
    static func sample(_ buffer: PixelBuffer, ring outer: PixelRegion, around inner: PixelRegion) -> Sample? {
        let outer = outer.clipped(to: buffer.region)
        guard !outer.isEmpty else { return nil }
        let inner = inner.clipped(to: outer)
        var accumulator = Accumulator()
        for y in outer.rows {
            if !inner.isEmpty, inner.rows.contains(y) {
                accumulator.add(buffer, columns: outer.columns.lowerBound..<inner.columns.lowerBound, y: y)
                accumulator.add(buffer, columns: inner.columns.upperBound..<outer.columns.upperBound, y: y)
            } else {
                accumulator.add(buffer, columns: outer.columns, y: y)
            }
        }
        return accumulator.sample
    }

    /// Per-channel integer sums.
    private struct Channels {
        var red = 0, green = 0, blue = 0, alpha = 0

        init() {}

        init(_ pixel: RawPixel) {
            red = Int(pixel.red)
            green = Int(pixel.green)
            blue = Int(pixel.blue)
            alpha = Int(pixel.alpha)
        }

        static func += (lhs: inout Channels, rhs: Channels) {
            lhs.red += rhs.red
            lhs.green += rhs.green
            lhs.blue += rhs.blue
            lhs.alpha += rhs.alpha
        }

        var squared: Channels {
            var result = Channels()
            result.red = red * red
            result.green = green * green
            result.blue = blue * blue
            result.alpha = alpha * alpha
            return result
        }

        var all: [Int] { [red, green, blue, alpha] }
    }

    /// Pixels land in buckets of 16 levels per channel; the fullest bucket's average is the dominant colour.
    private struct Accumulator {
        struct Bucket {
            var count = 0
            var sums = Channels()
        }

        var buckets: [UInt16: Bucket] = [:]
        var count = 0
        var sums = Channels()
        var squares = Channels()

        mutating func add(_ buffer: PixelBuffer, columns: Range<Int>, y: Int) {
            for x in columns {
                let pixel = buffer.pixel(x, y)
                let channels = Channels(pixel)
                let key = UInt16(pixel.red >> 4) << 12 | UInt16(pixel.green >> 4) << 8 | UInt16(pixel.blue >> 4) << 4 | UInt16(pixel.alpha >> 4)
                buckets[key, default: Bucket()].count += 1
                buckets[key, default: Bucket()].sums += channels
                sums += channels
                squares += channels.squared
                count += 1
            }
        }

        var sample: Sample? {
            // Ties go to the lower key, so the result does not depend on dictionary order.
            guard count > 0, let fullest = buckets.min(by: { ($0.value.count, $1.key) > ($1.value.count, $0.key) })?.value else { return nil }
            func average(_ sum: Int) -> UInt8 { UInt8((sum + fullest.count / 2) / fullest.count) }
            let dominant = RawPixel(
                red: average(fullest.sums.red), green: average(fullest.sums.green),
                blue: average(fullest.sums.blue), alpha: average(fullest.sums.alpha)
            )
            let total = Double(count)
            let variance = zip(sums.all, squares.all).map { Double($1) / total - pow(Double($0) / total, 2) }.reduce(0, +) / 4
            return Sample(dominant: dominant, variance: max(variance, 0))
        }
    }
}
