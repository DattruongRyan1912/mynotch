import AppKit
import NotchUI
import SwiftUI
import Testing
@testable import ClipboardModule

/// The board pills and the picker, drawn into an image in memory (no window, no screen): the colours that reach the notch are
/// the ones the board chose, and the default colour is the accent the notch has.
@Suite struct ClipboardBoardViewTests {
    static let accent = Color(.sRGB, red: 26 / 255, green: 204 / 255, blue: 230 / 255)

    func pixels(of view: some View, width: CGFloat = 300, height: CGFloat = 40) throws -> [(Int, Int, Int)] {
        let renderer = ImageRenderer(content: view.background(Color.black).frame(width: width, height: height))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        return (0..<bitmap.pixelsHigh).flatMap { y in
            (0..<bitmap.pixelsWide).compactMap { x in
                bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB).map {
                    (Int($0.redComponent * 255), Int($0.greenComponent * 255), Int($0.blueComponent * 255))
                }
            }
        }
    }

    func contains(_ pixels: [(Int, Int, Int)], near color: (Int, Int, Int), tolerance: Int = 30) -> Bool {
        pixels.contains { abs($0.0 - color.0) <= tolerance && abs($0.1 - color.1) <= tolerance && abs($0.2 - color.2) <= tolerance }
    }

    /// Whether the view has pixels near `color`, as a plain answer so a failure does not print the image.
    func draws(_ view: some View, near color: (Int, Int, Int), tolerance: Int = 30, width: CGFloat = 300, height: CGFloat = 40) throws -> Bool {
        contains(try pixels(of: view, width: width, height: height), near: color, tolerance: tolerance)
    }

    func board(_ color: ClipboardBoardColor, icon: String = "star.fill") -> ClipboardBoard {
        ClipboardBoard(id: UUID(), name: "Việc", systemImage: icon, color: color, itemIDs: [])
    }

    @Test func theDefaultColourIsTheAccentOfTheNotch() throws {
        let pill = ClipboardBoardPill(board: board(.accent), isSelected: false).environment(\.notchAccent, Self.accent)
        #expect(try draws(pill, near: (26, 204, 230)))
    }

    @Test func aNewAccentOfTheNotchReachesAPillThatUsesTheDefault() throws {
        let other = Color(.sRGB, red: 230 / 255, green: 40 / 255, blue: 200 / 255)
        let pill = ClipboardBoardPill(board: board(.accent), isSelected: false).environment(\.notchAccent, other)
        #expect(try draws(pill, near: (230, 40, 200)))
        #expect(try !draws(pill, near: (26, 204, 230)))
    }

    @Test func aChosenColourIsKeptWhateverTheAccentIs() throws {
        let pill = ClipboardBoardPill(board: board(.red), isSelected: false).environment(\.notchAccent, Self.accent)
        #expect(try draws(pill, near: (255, 60, 50), tolerance: 45))
        #expect(try !draws(pill, near: (26, 204, 230)))
    }

    @Test func aSelectedPillHasAHighlightAndAnUnselectedOneDoesNot() throws {
        let selected = try pixels(of: ClipboardBoardPill(board: board(.gray), isSelected: true))
        let plain = try pixels(of: ClipboardBoardPill(board: board(.gray), isSelected: false))
        let highlight = { (pixels: [(Int, Int, Int)]) in pixels.filter { $0.0 > 30 && $0.0 < 50 && abs($0.0 - $0.1) < 4 && abs($0.1 - $0.2) < 4 }.count }
        let selectedCount = highlight(selected), plainCount = highlight(plain)
        #expect(selectedCount > 300)
        #expect(plainCount < 50)
    }

    /// The strip's icons and dots sit in a scroll view, which an in-memory drawing leaves out, so what is checked here is what is
    /// outside it: the board's pill and the button that finishes, which takes the accent of the notch.
    @Test func theStyleStripDrawsTheBoardAndAFinishButtonInTheAccentOfTheNotch() throws {
        let strip = ClipboardBoardStyleStrip(board: board(.red), onIcon: { _ in }, onColor: { _ in }, onDone: {})
            .environment(\.notchAccent, Self.accent)
        let drawn = try pixels(of: strip, width: 600, height: 30)
        // The accent at 0.7 over black, and the red of the board's icon.
        let finish = contains(drawn, near: (18, 143, 161)), icon = contains(drawn, near: (255, 60, 50), tolerance: 45)
        #expect(finish)
        #expect(icon)
    }

    @Test func theLibraryPickerOffersTheAccentAndTheFixedColours() throws {
        let picker = ClipboardBoardStylePicker(board: board(.accent), onIcon: { _ in }, onColor: { _ in })
            .environment(\.notchAccent, Self.accent)
        let drawn = try pixels(of: picker, width: 340, height: 220)
        let accent = contains(drawn, near: (26, 204, 230)), orange = contains(drawn, near: (255, 149, 0), tolerance: 45)
        #expect(accent)
        #expect(orange)
    }
}
