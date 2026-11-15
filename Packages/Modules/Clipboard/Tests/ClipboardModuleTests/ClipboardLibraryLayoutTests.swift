import AppKit
import Testing
@testable import ClipboardModule

@Suite struct ClipboardLibraryLayoutTests {
    /// Held for the whole test: the identifier of a freed object can be reused by the next one.
    let objects = (0..<3).map { _ in NSObject() }

    // MARK: Card sizes

    @Test func cardSizesGrowInThreeSteps() {
        let sizes = ClipboardLibraryCardSize.allCases
        #expect(sizes == [.small, .medium, .large])
        #expect(sizes.map(\.minWidth) == sizes.map(\.minWidth).sorted())
        #expect(sizes.map(\.height) == sizes.map(\.height).sorted())
        #expect(sizes.map(\.textLines) == sizes.map(\.textLines).sorted())
        #expect(Set(sizes.map(\.minWidth)).count == 3)
    }

    @Test func theSliderMapsToTheSizes() {
        #expect(ClipboardLibraryCardSize(sliderValue: 0) == .small)
        #expect(ClipboardLibraryCardSize(sliderValue: 1) == .medium)
        #expect(ClipboardLibraryCardSize(sliderValue: 2) == .large)
        #expect(ClipboardLibraryCardSize(sliderValue: -3) == .small)
        #expect(ClipboardLibraryCardSize(sliderValue: 9) == .large)
        #expect(ClipboardLibraryCardSize.large.sliderValue == 2)
    }

    @Test func theColumnCountFillsTheWidthWithoutShrinkingCardsBelowTheirMinimum() {
        for size in ClipboardLibraryCardSize.allCases {
            for width in stride(from: 300.0, through: 1600.0, by: 37.0) {
                let columns = size.columnCount(forWidth: width, spacing: 12)
                let used = Double(columns) * size.minWidth + Double(columns - 1) * 12
                #expect(columns >= 1)
                #expect(used <= width)
                #expect(used + size.minWidth + 12 > width)
            }
        }
    }

    @Test func aNarrowOrUnknownWidthStillHasOneColumn() {
        #expect(ClipboardLibraryCardSize.large.columnCount(forWidth: 50, spacing: 12) == 1)
        #expect(ClipboardLibraryCardSize.small.columnCount(forWidth: 0, spacing: 12) == 1)
        #expect(ClipboardLibraryCardSize.small.columnCount(forWidth: -10, spacing: 12) == 1)
    }

    // MARK: Keys

    @Test func arrowsMoveAndShiftExtends() {
        #expect(ClipboardLibraryKeyCommand(keyCode: 123, modifiers: []) == .move(.left, extend: false))
        #expect(ClipboardLibraryKeyCommand(keyCode: 124, modifiers: []) == .move(.right, extend: false))
        #expect(ClipboardLibraryKeyCommand(keyCode: 125, modifiers: []) == .move(.down, extend: false))
        #expect(ClipboardLibraryKeyCommand(keyCode: 126, modifiers: []) == .move(.up, extend: false))
        #expect(ClipboardLibraryKeyCommand(keyCode: 125, modifiers: .shift) == .move(.down, extend: true))
        #expect(ClipboardLibraryKeyCommand(keyCode: 125, modifiers: .option) == nil)
        #expect(ClipboardLibraryKeyCommand(keyCode: 125, modifiers: .command) == nil)
    }

    @Test func returnActivatesAndDeleteRemoves() {
        #expect(ClipboardLibraryKeyCommand(keyCode: 36, modifiers: []) == .activate)
        #expect(ClipboardLibraryKeyCommand(keyCode: 76, modifiers: []) == .activate)
        #expect(ClipboardLibraryKeyCommand(keyCode: 51, modifiers: []) == .delete)
        #expect(ClipboardLibraryKeyCommand(keyCode: 117, modifiers: []) == .delete)
        #expect(ClipboardLibraryKeyCommand(keyCode: 51, modifiers: .command) == .delete)
        #expect(ClipboardLibraryKeyCommand(keyCode: 36, modifiers: .command) == nil)
        #expect(ClipboardLibraryKeyCommand(keyCode: 53, modifiers: []) == .clearSelection)
    }

    @Test func otherKeysAreLeftToTheSystem() {
        #expect(ClipboardLibraryKeyCommand(keyCode: 0, modifiers: []) == nil)
        #expect(ClipboardLibraryKeyCommand(keyCode: 49, modifiers: []) == nil)
    }

    // MARK: Activation policy

    @Test func theLibraryClosingReturnsToAMenuBarAppWhenNothingElseIsOpen() {
        let library = ObjectIdentifier(objects[0])
        let settings = ObjectIdentifier(objects[1])
        func state(_ id: ObjectIdentifier, visible: Bool = true, minimized: Bool = false, titled: Bool = true) -> ClipboardLibraryActivation.WindowState {
            .init(id: id, isVisible: visible, isMiniaturized: minimized, isTitled: titled)
        }
        #expect(ClipboardLibraryActivation.policyAfterClosing(library, among: [state(library)]) == .accessory)
        // The notch's panel and other untitled windows do not need a Dock icon.
        #expect(ClipboardLibraryActivation.policyAfterClosing(
            library, among: [state(library), state(ObjectIdentifier(objects[2]), titled: false)]
        ) == .accessory)
        #expect(ClipboardLibraryActivation.policyAfterClosing(library, among: [state(library), state(settings)]) == .regular)
        // A minimized window is still reached through the Dock.
        #expect(ClipboardLibraryActivation.policyAfterClosing(
            library, among: [state(library), state(settings, visible: false, minimized: true)]
        ) == .regular)
        #expect(ClipboardLibraryActivation.policyAfterClosing(
            library, among: [state(library), state(settings, visible: false)]
        ) == .accessory)
    }
}
