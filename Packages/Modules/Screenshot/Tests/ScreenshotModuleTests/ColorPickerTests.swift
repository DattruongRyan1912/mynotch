import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct ColorPickerTests {
    // Helper to generate a 20x20 solid color CGImage
    static func makeSolidImage(red: UInt8, green: UInt8, blue: UInt8, width: Int = 20, height: Int = 20) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        var data = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            data[i * 4] = red
            data[i * 4 + 1] = green
            data[i * 4 + 2] = blue
            data[i * 4 + 3] = 255
        }
        let provider = CGDataProvider(data: Data(data) as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    @Test func colorFormatCyclesCorrectly() {
        var format = ColorFormat.hex
        format = format.next
        #expect(format == .rgb)
        format = format.next
        #expect(format == .hsl)
        format = format.next
        #expect(format == .hsb)
        format = format.next
        #expect(format == .hex)
    }

    @Test func colorSampleFormatsCorrectly() {
        // Pure Red (#FF0000)
        let red = ColorSample(red: 255, green: 0, blue: 0)
        #expect(red.formatted(as: .hex) == "#FF0000")
        #expect(red.formatted(as: .rgb) == "rgb(255, 0, 0)")
        #expect(red.formatted(as: .hsl) == "hsl(0, 100%, 50%)")
        #expect(red.formatted(as: .hsb) == "hsb(0, 100%, 100%)")
        #expect(red.prefersDarkCrosshair == false)

        // Pure White (#FFFFFF)
        let white = ColorSample(red: 255, green: 255, blue: 255)
        #expect(white.formatted(as: .hex) == "#FFFFFF")
        #expect(white.formatted(as: .rgb) == "rgb(255, 255, 255)")
        #expect(white.formatted(as: .hsl) == "hsl(0, 0%, 100%)")
        #expect(white.formatted(as: .hsb) == "hsb(0, 0%, 100%)")
        #expect(white.prefersDarkCrosshair == true)

        // Pure Black (#000000)
        let black = ColorSample(red: 0, green: 0, blue: 0)
        #expect(black.formatted(as: .hex) == "#000000")
        #expect(black.formatted(as: .rgb) == "rgb(0, 0, 0)")
        #expect(black.formatted(as: .hsl) == "hsl(0, 0%, 0%)")
        #expect(black.formatted(as: .hsb) == "hsb(0, 0%, 0%)")
        #expect(black.prefersDarkCrosshair == false)

        // Apple System Green (#34C759)
        let green = ColorSample(red: 52, green: 199, blue: 89)
        #expect(green.formatted(as: .hex) == "#34C759")
        #expect(green.formatted(as: .rgb) == "rgb(52, 199, 89)")
        let (h, s, l) = green.hslComponents()
        #expect(h == 135)
        #expect(s == 59)
        #expect(l == 49)
    }

    @Test func frozenDisplaySamplerReadsPixelsAndGrid() {
        let image = Self.makeSolidImage(red: 255, green: 128, blue: 0, width: 20, height: 20)
        let sampler = FrozenDisplaySampler(image: image)
        #expect(sampler != nil)

        // Sample center
        let sample = sampler?.sample(atX: 10, y: 10)
        #expect(sample?.red == 255)
        #expect(sample?.green == 128)
        #expect(sample?.blue == 0)

        // Sample clamped out of bounds
        let outOfBounds = sampler?.sample(atX: -5, y: 100)
        #expect(outOfBounds?.red == 255)
        #expect(outOfBounds?.green == 128)
        #expect(outOfBounds?.blue == 0)

        // Grid 11x11
        let grid = sampler?.grid(centerX: 0, centerY: 0, radius: 5)
        #expect(grid?.count == 11)
        #expect(grid?.first?.count == 11)
        #expect(grid?[5][5].red == 255)
    }

    @Test func interactionTabCyclesFormat() {
        let info = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 2)
        let image = Self.makeSolidImage(red: 10, green: 20, blue: 30)
        let frozen = [FrozenDisplay(info: info, image: image)]

        var interaction = ColorPickerInteraction(
            frozen: frozen,
            initialFormat: .hex,
            initialPointer: CGPoint(x: 50, y: 50)
        )

        #expect(interaction.format == .hex)
        let outcome1 = interaction.keyDown(.tab)
        #expect(outcome1 == .formatChanged(.rgb))
        #expect(interaction.format == .rgb)

        let outcome2 = interaction.keyDown(.tab)
        #expect(outcome2 == .formatChanged(.hsl))
        #expect(interaction.format == .hsl)
    }

    @Test func interactionShiftSlowDPI() {
        let info = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 200, height: 200), scale: 1)
        let image = Self.makeSolidImage(red: 10, green: 20, blue: 30, width: 200, height: 200)
        let frozen = [FrozenDisplay(info: info, image: image)]

        var interaction = ColorPickerInteraction(
            frozen: frozen,
            initialFormat: .hex,
            initialPointer: CGPoint(x: 50, y: 50)
        )

        // Move 20pt without shift -> moves 20pt
        interaction.pointerMoved(to: CGPoint(x: 70, y: 50), shiftDown: false)
        #expect(interaction.virtualPointer.x == 70)

        // Move 20pt with shift -> moves 20 * 0.15 = 3pt
        interaction.pointerMoved(to: CGPoint(x: 90, y: 50), shiftDown: true)
        #expect(abs(interaction.virtualPointer.x - 73.0) < 0.001)
    }

    @Test func interactionNudgeKeysShiftPixelByOne() {
        let info = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1)
        let image = Self.makeSolidImage(red: 10, green: 20, blue: 30, width: 100, height: 100)
        let frozen = [FrozenDisplay(info: info, image: image)]

        var interaction = ColorPickerInteraction(
            frozen: frozen,
            initialFormat: .hex,
            initialPointer: CGPoint(x: 50, y: 50)
        )

        let initialX = interaction.pixelX
        let initialY = interaction.pixelY

        // Right (D)
        _ = interaction.keyDown(.right)
        #expect(interaction.pixelX == initialX + 1)
        #expect(interaction.pixelY == initialY)

        // Down (S)
        _ = interaction.keyDown(.down)
        #expect(interaction.pixelX == initialX + 1)
        #expect(interaction.pixelY == initialY + 1)

        // Left (A)
        _ = interaction.keyDown(.left)
        #expect(interaction.pixelX == initialX)

        // Up (W)
        _ = interaction.keyDown(.up)
        #expect(interaction.pixelY == initialY)
    }

    @Test func interactionSingleClickFinishes() {
        let info = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1)
        let image = Self.makeSolidImage(red: 255, green: 0, blue: 128, width: 100, height: 100)
        let frozen = [FrozenDisplay(info: info, image: image)]

        var interaction = ColorPickerInteraction(
            frozen: frozen,
            initialFormat: .hex,
            initialPointer: CGPoint(x: 50, y: 50)
        )

        let outcome = interaction.mouseDown(at: CGPoint(x: 50, y: 50), shiftDown: false, commandDown: false)
        if case .finish(let result) = outcome {
            #expect(result.colors.count == 1)
            #expect(result.colors[0].red == 255)
            #expect(result.colors[0].green == 0)
            #expect(result.colors[0].blue == 128)
            #expect(result.clipboardText == "#FF0080")
        } else {
            Issue.record("Expected .finish outcome on single click")
        }
    }

    @Test func interactionCommandClickMultiPicksUpToFive() {
        let info = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1)
        let image = Self.makeSolidImage(red: 200, green: 100, blue: 50, width: 100, height: 100)
        let frozen = [FrozenDisplay(info: info, image: image)]

        var interaction = ColorPickerInteraction(
            frozen: frozen,
            initialFormat: .hex,
            initialPointer: CGPoint(x: 50, y: 50)
        )

        // Pick 1st color
        let out1 = interaction.mouseDown(at: CGPoint(x: 50, y: 50), shiftDown: false, commandDown: true)
        #expect(out1 == .pickedIntermediate(ColorSample(red: 200, green: 100, blue: 50)))
        #expect(interaction.pickedColors.count == 1)

        // Pick 2nd, 3rd, 4th, 5th
        for _ in 2...5 {
            _ = interaction.mouseDown(at: CGPoint(x: 50, y: 50), shiftDown: false, commandDown: true)
        }
        #expect(interaction.pickedColors.count == 5)

        // Pick 6th: drops oldest, keeps 5
        _ = interaction.mouseDown(at: CGPoint(x: 50, y: 50), shiftDown: false, commandDown: true)
        #expect(interaction.pickedColors.count == 5)

        // Press Return to finish and export all 5
        let finishOutcome = interaction.keyDown(.returnKey)
        if case .finish(let result) = finishOutcome {
            #expect(result.colors.count == 5)
            let lines = result.clipboardText.split(separator: "\n")
            #expect(lines.count == 5)
            #expect(lines.first == "#C86432")
        } else {
            Issue.record("Expected .finish outcome on return key")
        }
    }

    @Test func interactionEscapeCancels() {
        let info = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 1)
        let image = Self.makeSolidImage(red: 10, green: 20, blue: 30)
        let frozen = [FrozenDisplay(info: info, image: image)]

        var interaction = ColorPickerInteraction(
            frozen: frozen,
            initialFormat: .hex,
            initialPointer: CGPoint(x: 50, y: 50)
        )

        let outcome = interaction.keyDown(.escape)
        #expect(outcome == .cancel)
    }
}
