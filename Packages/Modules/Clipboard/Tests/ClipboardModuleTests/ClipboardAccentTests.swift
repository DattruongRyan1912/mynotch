import AppKit
import Foundation
import NotchUI
import SwiftUI
import Testing
@testable import ClipboardModule

/// What the Clipboard module draws with the accent: in the notch, the one the notch gives its content through the
/// environment, and in the library and the floating panel (windows of their own) the one `ClipboardAccentHost` puts in from the
/// notch's interface. Drawn into images in memory (no window, no screen) and read pixel by pixel; nothing here uses a
/// colour that the notch's own purple could be mistaken for.
@Suite struct ClipboardAccentTests {
    /// A colour that is neither the notch's purple (125, 92, 255) nor macOS's blue.
    static let accent = Color(.sRGB, red: 20 / 255, green: 220 / 255, blue: 60 / 255)
    static let accentRGB = (20, 220, 60)
    static let purple = (125, 92, 255)

    func pixels(of view: some View, width: CGFloat = 320, height: CGFloat = 140) throws -> [(Int, Int, Int)] {
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

    func count(_ pixels: [(Int, Int, Int)], near color: (Int, Int, Int), tolerance: Int = 30) -> Int {
        pixels.count { abs($0.0 - color.0) <= tolerance && abs($0.1 - color.1) <= tolerance && abs($0.2 - color.2) <= tolerance }
    }

    /// How many pixels of `view` are in the accent, and how many in the notch's static purple, with `accent` in the environment.
    func drawn(_ view: some View, accent: Color = ClipboardAccentTests.accent, width: CGFloat = 320, height: CGFloat = 140) throws -> (accent: Int, purple: Int) {
        let pixels = try pixels(of: view.environment(\.notchAccent, accent), width: width, height: height)
        return (count(pixels, near: Self.accentRGB), count(pixels, near: Self.purple))
    }

    static let item = ClipboardItem(
        id: UUID(), content: .text("Xin chào"), contentHash: "h", copiedAt: Date(timeIntervalSince1970: 1_800_000_000),
        sourceBundleID: nil, sourceAppName: nil, codeDetection: .notCode
    )

    // MARK: In the notch

    @Test func aSelectedCardIsOutlinedInTheAccentOfTheNotch() throws {
        let card = ClipboardCardView(
            item: Self.item, isSelected: true, isPinned: false, now: Self.item.copiedAt, imageURL: nil, thumbnails: ClipboardThumbnailCache()
        )
        let selected = try drawn(card, width: 140, height: 150)
        #expect(selected.accent > 150)
        #expect(selected.purple == 0)

        let plain = ClipboardCardView(
            item: Self.item, isSelected: false, isPinned: false, now: Self.item.copiedAt, imageURL: nil, thumbnails: ClipboardThumbnailCache()
        )
        let unselected = try drawn(plain, width: 140, height: 150)
        #expect(unselected.accent == 0)
    }

    @Test func aPinnedCardShowsItsPinInTheAccent() throws {
        let pinned = ClipboardCardView(
            item: Self.item, isSelected: false, isPinned: true, now: Self.item.copiedAt, imageURL: nil, thumbnails: ClipboardThumbnailCache()
        )
        let result = try drawn(pinned, width: 140, height: 150)
        #expect(result.accent > 5)
        #expect(result.purple == 0)
    }

    @Test func theNextEntryOfTheStackIsMarkedInTheAccent() throws {
        let entry = CopyStackEntry(id: UUID(), item: Self.item)
        func row(isNext: Bool) -> some View {
            ClipboardStackRow(entry: entry, isNext: isNext, canMoveUp: false, canMoveDown: false, remove: {}, move: { _ in })
        }
        let next = try drawn(row(isNext: true), width: 300, height: 40)
        let other = try drawn(row(isNext: false), width: 300, height: 40)

        #expect(next.accent > 100)
        #expect(next.purple == 0)
        #expect(other.accent == 0)
    }

    @Test func theAccessibilityHintsButtonInTheNotchTakesTheAccent() throws {
        let hint = ClipboardAccessibilityHint(look: .notch, onGrant: {})
        let pixels = try pixels(of: hint.environment(\.notchAccent, Self.accent), width: 400, height: 30)
        // The accent at 0.7 over black.
        #expect(count(pixels, near: (14, 154, 42)) > 200)
        #expect(count(pixels, near: (88, 64, 178)) == 0)
    }

    @Test func theChipsOfTheSearchTakeTheAccent() throws {
        let token = ClipboardSearchTerms(parsing: "@code ", apps: []).chips
        #expect(!token.isEmpty)
        let notch = try pixels(of: ClipboardSearchChips(look: .notch, tokens: token, onRemove: { _ in }).environment(\.notchAccent, Self.accent), width: 200, height: 30)
        // The accent at 0.45 over black.
        #expect(count(notch, near: (9, 99, 27)) > 100)
        #expect(count(notch, near: (56, 41, 115)) == 0)
        let library = try pixels(of: ClipboardSearchChips(look: .library, tokens: token, onRemove: { _ in }).environment(\.notchAccent, Self.accent), width: 200, height: 30)
        // At 0.2.
        #expect(count(library, near: (4, 44, 12), tolerance: 12) > 100)
    }

    @Test func aHighlightedSuggestionTakesTheAccent() throws {
        let suggestion = try #require(ClipboardSearchSuggestions.suggestions(for: "@", apps: []).first)
        let notch = try pixels(
            of: ClipboardSuggestionRow(look: .notch, suggestion: suggestion, isHighlighted: true).environment(\.notchAccent, Self.accent), width: 220, height: 30
        )
        // At 0.7.
        #expect(count(notch, near: (14, 154, 42)) > 200)
        let other = try pixels(
            of: ClipboardSuggestionRow(look: .notch, suggestion: suggestion, isHighlighted: false).environment(\.notchAccent, Self.accent), width: 220, height: 30
        )
        #expect(count(other, near: (14, 154, 42)) == 0)
        let library = try pixels(
            of: ClipboardSuggestionRow(look: .library, suggestion: suggestion, isHighlighted: true).environment(\.notchAccent, Self.accent), width: 260, height: 30
        )
        #expect(count(library, near: Self.accentRGB) > 200)
    }

    // MARK: In the library and the panel

    @Test func theLibraryCardsAndRowsAreSelectedInTheAccent() throws {
        let card = ClipboardLibraryCard(
            item: Self.item, size: .medium, isSelected: true, isPinned: true, timeLabel: "1 phút trước", accessibilityLabel: "",
            imageURL: nil, thumbnails: ClipboardThumbnailCache()
        )
        let cardResult = try drawn(card, width: 220, height: 200)
        #expect(cardResult.accent > 300)
        #expect(cardResult.purple == 0)
        // The accent at 0.16 over black fills the selected card.
        let fill = count(try pixels(of: card.environment(\.notchAccent, Self.accent), width: 220, height: 200), near: (3, 35, 10), tolerance: 10)
        #expect(fill > 2_000)

        let row = ClipboardLibraryRow(
            item: Self.item, isSelected: true, isPinned: true, timeLabel: "1 phút", accessibilityLabel: "", imageURL: nil,
            thumbnails: ClipboardThumbnailCache()
        )
        let rowResult = try drawn(row, width: 700, height: 60)
        #expect(rowResult.accent > 300)
        #expect(rowResult.purple == 0)

        let loose = ClipboardLibraryRow(
            item: Self.item, isSelected: false, isPinned: false, timeLabel: "1 phút", accessibilityLabel: "", imageURL: nil,
            thumbnails: ClipboardThumbnailCache()
        )
        #expect(try drawn(loose, width: 700, height: 60).accent == 0)
    }

    @Test func theLibrarysBoardTileAndTheTargetOfADropTakeTheAccent() throws {
        let board = ClipboardBoard(id: UUID(), name: "Việc", systemImage: "star.fill", itemIDs: [])
        let tile = try drawn(ClipboardLibraryBoardTile(board: board, count: 3, isTargeted: false), width: 200, height: 70)
        #expect(tile.accent > 10)
        let targeted = try drawn(ClipboardLibraryBoardTile(board: board, count: 3, isTargeted: true), width: 200, height: 70)
        #expect(targeted.accent > tile.accent + 100)
    }

    @Test func aSelectedRowOfThePanelIsOutlinedInTheAccent() throws {
        let row = ClipboardPanelRow(
            item: Self.item, isSelected: true, shortcut: 1, timeLabel: "1 phút", accessibilityLabel: "", imageURL: nil,
            thumbnails: ClipboardThumbnailCache()
        )
        let result = try drawn(row, width: 420, height: 60)
        #expect(result.accent > 200)
        #expect(result.purple == 0)
    }

    @Test func theStylePickerOfTheLibraryUsesTheAccentOfTheWindow() throws {
        let picker = ClipboardBoardStylePicker(
            board: ClipboardBoard(id: UUID(), name: "A", systemImage: "star", itemIDs: []), onIcon: { _ in }, onColor: { _ in }
        )
        // The fixed colours of the row include purples and blues of their own, so only the accent is looked for.
        let result = try drawn(picker, width: 340, height: 240)
        #expect(result.accent > 100)
    }

    // MARK: The host of a window of its own

    @Test func theHostPutsTheAccentOfTheInterfaceIntoTheEnvironmentOfWhatItHolds() throws {
        let board = ClipboardBoard(id: UUID(), name: "Việc", systemImage: "star.fill", itemIDs: [])
        // An interface with no theme has the notch's purple, whatever the surroundings say.
        let host = ClipboardAccentHost(interface: NotchInterface()) { ClipboardBoardPill(board: board, isSelected: false) }
            .environment(\.notchAccent, Self.accent)
        let pixels = try pixels(of: host, width: 200, height: 40)
        #expect(count(pixels, near: Self.purple) > 10)
        #expect(count(pixels, near: Self.accentRGB) == 0)
    }

    // MARK: Nothing left on the static colour

    @Test func noSourceDrawsWithTheStaticAccentAnyMore() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/ClipboardModule", directoryHint: .isDirectory)
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.split(separator: "//", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
                if code.contains("NotchTokens.accent") || code.contains("Color.accentColor") || code.contains(".accentColor") {
                    offenders.append("\(url.lastPathComponent):\(number + 1)")
                }
            }
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }
}
