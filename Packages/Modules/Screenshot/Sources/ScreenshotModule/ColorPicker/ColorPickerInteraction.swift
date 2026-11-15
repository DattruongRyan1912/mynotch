import CoreGraphics
import Foundation

/// Result of a color picker session.
nonisolated struct ColorPickerResult: Equatable, Sendable {
    var colors: [ColorSample]
    var format: ColorFormat

    init(colors: [ColorSample], format: ColorFormat) {
        self.colors = colors
        self.format = format
    }

    var clipboardText: String {
        colors.map { $0.formatted(as: format) }.joined(separator: "\n")
    }
}

/// Pure state machine driving keyboard, mouse, and magnification mechanics.
nonisolated struct ColorPickerInteraction: Sendable {
    static let gridRadius = 5 // 11x11 grid
    static let maxPickedColors = 5
    static let slowDPIScale: CGFloat = 0.15

    enum Key: Equatable, Sendable {
        case escape
        case tab
        case space
        case returnKey
        case up
        case down
        case left
        case right

        static func key(forKeyCode keyCode: UInt16) -> Key? {
            switch keyCode {
            case 53: return .escape
            case 48: return .tab
            case 49: return .space
            case 36, 76: return .returnKey
            case 126, 13: return .up    // Arrow up or W
            case 125, 1: return .down   // Arrow down or S
            case 123, 0: return .left   // Arrow left or A
            case 124, 2: return .right  // Arrow right or D
            default: return nil
            }
        }
    }

    enum Outcome: Equatable, Sendable {
        case none
        case formatChanged(ColorFormat)
        case pickedIntermediate(ColorSample)
        case cancel
        case finish(ColorPickerResult)
    }

    private(set) var format: ColorFormat
    private(set) var pickedColors: [ColorSample] = []
    private(set) var activeDisplay: DisplayInfo
    private(set) var pixelX: Int = 0
    private(set) var pixelY: Int = 0
    private(set) var virtualPointer: CGPoint
    private var lastRawPointer: CGPoint?

    let displays: [DisplayInfo]
    let samplers: [CGDirectDisplayID: FrozenDisplaySampler]

    init(frozen: [FrozenDisplay], initialFormat: ColorFormat, initialPointer: CGPoint) {
        self.format = initialFormat
        self.displays = frozen.map(\.info)

        var map: [CGDirectDisplayID: FrozenDisplaySampler] = [:]
        for f in frozen {
            if let sampler = FrozenDisplaySampler(image: f.image) {
                map[f.info.id] = sampler
            }
        }
        self.samplers = map

        let matchingDisplay = GeometryMapper.display(containing: initialPointer, in: displays) ?? displays.first ?? DisplayInfo(
            id: 0,
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2.0
        )
        self.activeDisplay = matchingDisplay
        self.virtualPointer = initialPointer
        self.lastRawPointer = initialPointer

        updatePixelCoordinates()
    }

    mutating func pointerMoved(to rawPoint: CGPoint, shiftDown: Bool) {
        let next: CGPoint
        if let last = lastRawPointer, shiftDown {
            let dx = (rawPoint.x - last.x) * Self.slowDPIScale
            let dy = (rawPoint.y - last.y) * Self.slowDPIScale
            next = CGPoint(x: virtualPointer.x + dx, y: virtualPointer.y + dy)
        } else {
            next = rawPoint
        }
        lastRawPointer = rawPoint

        if let display = GeometryMapper.display(containing: next, in: displays) {
            activeDisplay = display
            virtualPointer = next
        } else {
            // Keep on current display, clamp inside frame
            let clampedX = min(max(next.x, activeDisplay.frame.minX), activeDisplay.frame.maxX)
            let clampedY = min(max(next.y, activeDisplay.frame.minY), activeDisplay.frame.maxY)
            virtualPointer = CGPoint(x: clampedX, y: clampedY)
        }

        updatePixelCoordinates()
    }

    mutating func nudge(dx: Int, dy: Int) {
        let sampler = currentSampler
        let width = sampler?.width ?? max(Int((activeDisplay.frame.width * activeDisplay.scale).rounded()), 1)
        let height = sampler?.height ?? max(Int((activeDisplay.frame.height * activeDisplay.scale).rounded()), 1)

        pixelX = min(max(pixelX + dx, 0), width - 1)
        pixelY = min(max(pixelY + dy, 0), height - 1)

        // Center virtual pointer in the newly nudged pixel
        let ptX = activeDisplay.frame.minX + (CGFloat(pixelX) + 0.5) / activeDisplay.scale
        let ptY = activeDisplay.frame.maxY - (CGFloat(pixelY) + 0.5) / activeDisplay.scale
        virtualPointer = CGPoint(x: ptX, y: ptY)
    }

    mutating func mouseDown(at rawPoint: CGPoint, shiftDown: Bool, commandDown: Bool) -> Outcome {
        pointerMoved(to: rawPoint, shiftDown: shiftDown)
        let sample = currentColor

        if commandDown {
            if pickedColors.count >= Self.maxPickedColors {
                pickedColors.removeFirst()
            }
            pickedColors.append(sample)
            return .pickedIntermediate(sample)
        } else {
            if pickedColors.isEmpty {
                return .finish(ColorPickerResult(colors: [sample], format: format))
            } else {
                var finalColors = pickedColors
                if finalColors.count < Self.maxPickedColors {
                    finalColors.append(sample)
                }
                return .finish(ColorPickerResult(colors: finalColors, format: format))
            }
        }
    }

    mutating func keyDown(_ key: Key) -> Outcome {
        switch key {
        case .escape:
            return .cancel

        case .tab:
            format = format.next
            return .formatChanged(format)

        case .space, .returnKey:
            let colors = pickedColors.isEmpty ? [currentColor] : pickedColors
            return .finish(ColorPickerResult(colors: colors, format: format))

        case .left:
            nudge(dx: -1, dy: 0)
            return .none

        case .right:
            nudge(dx: 1, dy: 0)
            return .none

        case .up:
            nudge(dx: 0, dy: -1)
            return .none

        case .down:
            nudge(dx: 0, dy: 1)
            return .none
        }
    }

    var currentSampler: FrozenDisplaySampler? {
        samplers[activeDisplay.id]
    }

    var currentColor: ColorSample {
        currentSampler?.sample(atX: pixelX, y: pixelY) ?? ColorSample(red: 0, green: 0, blue: 0)
    }

    var currentGrid: [[ColorSample]] {
        currentSampler?.grid(centerX: pixelX, centerY: pixelY, radius: Self.gridRadius) ??
            Array(repeating: Array(repeating: ColorSample(red: 0, green: 0, blue: 0), count: 11), count: 11)
    }

    var hint: String {
        if pickedColors.isEmpty {
            return "Click: Chép màu · ⌘-Click: Thêm màu · Tab: Đổi dạng · ⇧: Rê chuột chậm · WASD/Mũi tên: 1px · Esc: Thoát"
        } else {
            return "Đã chọn \(pickedColors.count)/\(Self.maxPickedColors) màu · ⌘-Click: Thêm tiếp · Enter/Space: Chép toàn bộ · Esc: Thoát"
        }
    }

    private mutating func updatePixelCoordinates() {
        let sampler = currentSampler
        let width = sampler?.width ?? max(Int((activeDisplay.frame.width * activeDisplay.scale).rounded()), 1)
        let height = sampler?.height ?? max(Int((activeDisplay.frame.height * activeDisplay.scale).rounded()), 1)

        let relX = (virtualPointer.x - activeDisplay.frame.minX) * activeDisplay.scale
        let relY = (activeDisplay.frame.maxY - virtualPointer.y) * activeDisplay.scale

        let rawX = Int(floor(relX))
        let rawY = Int(floor(relY))

        pixelX = min(max(rawX, 0), width - 1)
        pixelY = min(max(rawY, 0), height - 1)
    }
}
