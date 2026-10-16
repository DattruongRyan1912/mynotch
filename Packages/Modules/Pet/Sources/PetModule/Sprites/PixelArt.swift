import CoreGraphics
import Foundation

/// The colours a sprite is drawn with: one character per colour, so a frame is a few lines of text. `.` is always clear.
nonisolated struct PixelPalette: Equatable, Sendable {
    /// Colour of each character as 0xRRGGBB. A character that is not here is an error in the art, not a clear pixel.
    let colors: [Character: UInt32]

    static let clear: Character = "."

    func isKnown(_ character: Character) -> Bool { character == Self.clear || colors[character] != nil }
}

nonisolated enum PixelArtError: Error, Equatable {
    case empty
    case ragged(row: Int, width: Int, expected: Int)
    case unknownCharacter(Character, row: Int, column: Int)
}

/// One picture of pixels: a grid of palette characters, rows from the top.
nonisolated struct PixelFrame: Equatable, Sendable {
    let width: Int
    let height: Int
    /// Row-major, `width * height` characters.
    let cells: [Character]

    /// Parses `rows` (all the same length) against `palette`.
    init(rows: [String], palette: PixelPalette) throws {
        guard let first = rows.first, !first.isEmpty else { throw PixelArtError.empty }
        let width = first.count
        var cells: [Character] = []
        for (row, line) in rows.enumerated() {
            guard line.count == width else { throw PixelArtError.ragged(row: row, width: line.count, expected: width) }
            for (column, character) in line.enumerated() {
                guard palette.isKnown(character) else { throw PixelArtError.unknownCharacter(character, row: row, column: column) }
                cells.append(character)
            }
        }
        self.width = width
        self.height = rows.count
        self.cells = cells
    }

    /// A clear picture.
    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        cells = Array(repeating: PixelPalette.clear, count: width * height)
    }

    private init(width: Int, height: Int, cells: [Character]) {
        self.width = width
        self.height = height
        self.cells = cells
    }

    subscript(column: Int, row: Int) -> Character { cells[row * width + column] }

    /// The picture as lines of text again.
    var rows: [String] {
        (0..<height).map { row in String(cells[(row * width)..<((row + 1) * width)]) }
    }

    /// Left and right swapped: the cat that walks right, walking left.
    var mirrored: PixelFrame {
        var flipped = cells
        for row in 0..<height {
            for column in 0..<width { flipped[row * width + column] = cells[row * width + (width - 1 - column)] }
        }
        return PixelFrame(width: width, height: height, cells: flipped)
    }

    /// `piece` drawn over this picture with its top left at (`x`, `y`); its clear pixels leave what is under them, and whatever falls
    /// outside the picture is cut off, which is how a cat that jumps off the top of its frame is drawn.
    func drawing(_ piece: PixelFrame, atX x: Int, y: Int) -> PixelFrame {
        var cells = self.cells
        for row in 0..<piece.height {
            for column in 0..<piece.width {
                let (targetColumn, targetRow) = (column + x, row + y)
                guard (0..<width).contains(targetColumn), (0..<height).contains(targetRow) else { continue }
                let pixel = piece[column, row]
                if pixel != PixelPalette.clear { cells[targetRow * width + targetColumn] = pixel }
            }
        }
        return PixelFrame(width: width, height: height, cells: cells)
    }

    /// How many pixels are not clear.
    var inkCount: Int { cells.reduce(0) { $0 + ($1 == PixelPalette.clear ? 0 : 1) } }
}

/// A looping run of frames, played at `fps`.
nonisolated struct PixelAnimation: Equatable, Sendable {
    let frames: [PixelFrame]
    let fps: Double

    /// Time one pass takes, in seconds.
    var duration: TimeInterval { Double(frames.count) / fps }
}

/// A strip of frames side by side in one image, which a layer plays by moving its `contentsRect` along it.
///
/// Every frame has a clear pixel of its own all round it: a layer that draws with nearest-neighbour filtering still samples at the
/// edge of what it is shown, and without the margin the edge of a neighbouring frame can show through.
nonisolated struct PixelStrip {
    /// Clear pixels on each side of every frame.
    static let margin = 1

    let frameWidth: Int
    let frameHeight: Int
    let frameCount: Int
    let image: CGImage

    /// nil only when the system cannot make an image of this size.
    init?(frames: [PixelFrame], palette: PixelPalette) {
        guard let first = frames.first, frames.allSatisfy({ $0.width == first.width && $0.height == first.height }) else { return nil }
        frameWidth = first.width
        frameHeight = first.height
        frameCount = frames.count
        let cellWidth = first.width + 2 * Self.margin
        let width = cellWidth * frames.count
        let height = first.height + 2 * Self.margin
        // Opaque or clear, so premultiplying changes nothing.
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for (index, frame) in frames.enumerated() {
            for row in 0..<frame.height {
                for column in 0..<frame.width {
                    guard let rgb = palette.colors[frame[column, row]] else { continue }
                    let x = index * cellWidth + Self.margin + column
                    let y = Self.margin + row
                    let offset = (y * width + x) * 4
                    bytes[offset] = UInt8((rgb >> 16) & 0xFF)
                    bytes[offset + 1] = UInt8((rgb >> 8) & 0xFF)
                    bytes[offset + 2] = UInt8(rgb & 0xFF)
                    bytes[offset + 3] = 255
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent
              ) else { return nil }
        self.image = image
    }

    /// The part of the image that is frame `index`, in the unit square a layer's `contentsRect` is measured in.
    func contentsRect(of index: Int) -> CGRect {
        let cellWidth = frameWidth + 2 * Self.margin
        let width = Double(cellWidth * frameCount)
        let height = Double(frameHeight + 2 * Self.margin)
        return CGRect(
            x: Double(index * cellWidth + Self.margin) / width, y: Double(Self.margin) / height,
            width: Double(frameWidth) / width, height: Double(frameHeight) / height
        )
    }
}
