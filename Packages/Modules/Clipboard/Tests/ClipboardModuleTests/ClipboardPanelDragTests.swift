import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import ClipboardModule

/// Dragging a row out of the floating panel to another app: the provider is the one the notch and the library use, a drag never pastes
/// and never closes a pinned panel, and an unpinned panel closes once the drag ends outside it.
extension ClipboardPanelModelTests {
    /// The panel's frame in screen coordinates, as the window reports it.
    static let panelFrame = CGRect(x: 100, y: 100, width: 660, height: 420)
    static let outside = CGPoint(x: 1_500, y: 600)
    static let inside = CGPoint(x: 300, y: 300)

    func dragModel(pinned: Bool, frame: CGRect? = ClipboardPanelModelTests.panelFrame) -> ClipboardPanelModel {
        let model = makeModel(pinned: pinned)
        model.panelFrame = { frame }
        return model
    }

    // MARK: What a drag does

    @Test func aDragTakesTheProviderForTheRowAndSelectsIt() {
        let model = dragModel(pinned: true)

        let provider = model.beginDrag(of: image)

        #expect(actions.dragged == [image])
        #expect(provider.registeredTypeIdentifiers == ["public.utf8-plain-text"], "what the module's provider made")
        #expect(model.selectedID == image)
        #expect(model.draggingID == image)
    }

    @Test func aDragNeverPastesNorClosesNorHandsTheKeyboardAwayWhileItLasts() {
        for pinned in [true, false] {
            let model = dragModel(pinned: pinned)
            _ = model.beginDrag(of: text)

            #expect(actions.activated.isEmpty, "a drag is not a click")
            #expect(!actions.events.contains("write") && !actions.events.contains("paste"))
            #expect(closeCount == 0)
            #expect(keyboardReturns == 0)
        }
    }

    @Test func aDragOfARowThatIsGoneCarriesNothing() {
        let model = dragModel(pinned: true)

        let provider = model.beginDrag(of: UUID())

        #expect(provider.registeredTypeIdentifiers.isEmpty)
        #expect(actions.dragged.isEmpty)
        #expect(model.draggingID == nil)
    }

    @Test func aDragFromAClosedPanelCarriesNothing() {
        let model = dragModel(pinned: true)
        model.requestClose()

        #expect(model.beginDrag(of: text).registeredTypeIdentifiers.isEmpty)
        #expect(actions.dragged.isEmpty)
    }

    @Test func aDragClosesTheLargePreview() {
        let model = dragModel(pinned: true)
        model.togglePreview()
        #expect(model.isPreviewOpen)

        _ = model.beginDrag(of: text)

        #expect(!model.isPreviewOpen)
    }

    // MARK: A pinned panel

    @Test func aPinnedPanelStaysOpenWhereverTheDragEnds() {
        for point in [Self.outside, Self.inside] {
            let model = dragModel(pinned: true)
            _ = model.beginDrag(of: text)

            model.endDrag(releasedAt: point)

            #expect(closeCount == 0)
            #expect(model.draggingID == nil)
        }
    }

    @Test func aPinnedPanelHandsTheKeyboardToTheAppDroppedOnWhenTheDragEndsOutsideIt() {
        let model = dragModel(pinned: true)
        _ = model.beginDrag(of: text)

        model.endDrag(releasedAt: Self.outside)

        // The user types where the item went, not into the panel's search field.
        #expect(keyboardReturns == 1)
    }

    @Test func aDragLetGoOverThePanelItselfChangesNothing() {
        let model = dragModel(pinned: true)
        _ = model.beginDrag(of: text)

        model.endDrag(releasedAt: Self.inside)

        #expect(keyboardReturns == 0)
        #expect(closeCount == 0)
        #expect(model.selectedID == text)
    }

    // MARK: An unpinned panel

    @Test func anUnpinnedPanelDoesNotCloseWhenTheKeyboardLeavesDuringTheDrag() {
        let model = dragModel(pinned: false)
        _ = model.beginDrag(of: text)

        // The app that is dropped on takes the keyboard.
        model.focusLost()

        #expect(closeCount == 0)
    }

    @Test func anUnpinnedPanelClosesWhenTheDragEndsOutsideIt() {
        let model = dragModel(pinned: false)
        _ = model.beginDrag(of: text)
        model.focusLost()

        model.endDrag(releasedAt: Self.outside)

        #expect(closeCount == 1)
        #expect(keyboardReturns == 0, "it is gone, which gives the keyboard back by itself")
    }

    @Test func anUnpinnedPanelStaysWhenTheDragEndsOverItself() {
        let model = dragModel(pinned: false)
        _ = model.beginDrag(of: text)

        model.endDrag(releasedAt: Self.inside)

        #expect(closeCount == 0)
        // And it closes again when the keyboard leaves, as it always did.
        model.focusLost()
        #expect(closeCount == 1)
    }

    @Test func withoutADragAnUnpinnedPanelStillClosesWhenTheKeyboardLeaves() {
        let model = dragModel(pinned: false)
        model.focusLost()
        #expect(closeCount == 1)
    }

    @Test func whereTheDragEndedIsNotKnownWithoutAFrameAndThePanelStays() {
        let model = dragModel(pinned: false, frame: nil)
        _ = model.beginDrag(of: text)

        model.endDrag(releasedAt: Self.outside)

        #expect(closeCount == 0)
    }

    // MARK: The end of a drag

    @Test func theEndOfADragAlwaysLetsTheModuleClearWhatItMadeForIt() {
        let model = dragModel(pinned: true)
        _ = model.beginDrag(of: image)
        model.endDrag(releasedAt: Self.inside)
        #expect(actions.dragEnds == 1)

        // Even when the panel closed during the drag.
        let closed = dragModel(pinned: false)
        _ = closed.beginDrag(of: image)
        closed.requestClose()
        closed.endDrag(releasedAt: Self.outside)
        #expect(actions.dragEnds == 2)
    }

    @Test func aSecondDragStartsAfterTheFirstWasDropped() {
        let model = dragModel(pinned: true)
        _ = model.beginDrag(of: text)
        model.endDrag(releasedAt: Self.outside)
        _ = model.beginDrag(of: link)

        #expect(model.draggingID == link)
        #expect(actions.dragged == [text, link])
    }
}

/// The module's side of a drag out of the panel: a picture of an open locked board is a file only if the drop target asks, with the
/// owner's permissions only, and gone two seconds after the drag; nothing of a board that has locked is carried.
extension ClipboardBoardLockModuleTests {
    @Test func aDragOutOfThePanelMakesAPicturesFileOnlyWhenAskedAndTheDragsEndRemovesItAfterTwoSeconds() async throws {
        await start()
        let (board, picture) = try await openBoardWithPicture()
        module.togglePanel()
        let panel = try #require(panelWindow.model)
        let item = try #require(history.items(of: board).first { $0.imageName == picture.name })
        #expect(panel.items.contains { $0.id == item.id })

        let provider = panel.beginDrag(of: item.id)
        #expect(dragFiles().isEmpty, "a file exists before anyone asked for it")
        let received = await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.png.identifier) { url, _ in
                continuation.resume(returning: url.flatMap { try? Data(contentsOf: $0) })
            }
        }
        #expect(received == picture.bytes)
        let file = try #require(dragFiles().first)
        let mode = try FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))[.posixPermissions] as? Int
        #expect(mode == 0o600)

        // The mouse is up, outside the panel: the picture's file goes once the target had time to read it.
        panel.endDrag(releasedAt: CGPoint(x: 5_000, y: 5_000))
        harness.scheduler.advance(by: .seconds(1))
        #expect(dragFiles().count == 1)
        harness.scheduler.advance(by: .seconds(2))
        #expect(dragFiles().isEmpty)
        #expect(filesAnywhereHolding(picture.bytes).isEmpty, "the picture never was a file of its own")
    }

    @Test func aPictureOfAnOpenBoardAlsoGivesItsDataToATargetThatAsksForData() async throws {
        await start()
        let (board, picture) = try await openBoardWithPicture()
        module.togglePanel()
        let panel = try #require(panelWindow.model)
        let item = try #require(history.items(of: board).first { $0.imageName == picture.name })

        let provider = panel.beginDrag(of: item.id)
        let data = await ClipboardDragProviderTests.data(of: provider, as: UTType.png.identifier)

        #expect(data == picture.bytes)
        panel.endDrag(releasedAt: CGPoint(x: 5_000, y: 5_000))
    }

    @Test func nothingOfABoardThatHasLockedCanBeDraggedOutOfThePanel() async throws {
        await start()
        let (board, picture) = try await openBoardWithPicture()
        module.togglePanel()
        let panel = try #require(panelWindow.model)
        let item = try #require(history.items(of: board).first { $0.imageName == picture.name })
        let text = try #require(history.items(of: board).first { $0.content.plainText == "văn bản trong két" })
        // Open, a text of the board is carried like any other.
        let open = await ClipboardDragProviderTests.string(of: panel.beginDrag(of: text.id))
        #expect(open == "văn bản trong két")
        // Dropped back on the panel, which stays.
        panel.endDrag(releasedAt: CGPoint(x: 300, y: 400))

        #expect(module.relockBoard(board))

        // The panel's rows are gone, and a row a view still holds of an item that left memory carries nothing either.
        #expect(!panel.items.contains { $0.id == item.id || $0.id == text.id })
        #expect(panel.beginDrag(of: text.id).registeredTypeIdentifiers.isEmpty)
        #expect(module.dragProvider(for: text).registeredTypeIdentifiers.isEmpty)
        #expect(module.dragProvider(for: item).registeredTypeIdentifiers.isEmpty)
        #expect(dragFiles().isEmpty)
    }

    @Test func anItemThatWasDeletedCarriesNothingOutOfTheModule() async throws {
        await start()
        copy("Xin chào")
        let item = try #require(history.items.first)
        #expect(!module.dragProvider(for: item).registeredTypeIdentifiers.isEmpty)

        module.update { history in
            _ = history.remove(ids: [item.id])
            return []
        }

        #expect(module.dragProvider(for: item).registeredTypeIdentifiers.isEmpty)
    }

    @Test func theModuleGivesThePanelItsWindowsFrameToDecideWhereADragEnded() async throws {
        await start()
        module.togglePanel()
        let panel = try #require(panelWindow.model)
        copy("Xin chào")
        let item = try #require(history.items.first)
        // The fake window's frame is (120, 340), 660 x 420, and the panel starts unpinned.
        #expect(panelWindow.frame == CGRect(x: 120, y: 340, width: 660, height: 420))

        _ = panel.beginDrag(of: item.id)
        panel.endDrag(releasedAt: CGPoint(x: 300, y: 400))
        #expect(panelWindow.isOpen, "let go over the panel: dropped back")

        _ = panel.beginDrag(of: item.id)
        panel.endDrag(releasedAt: CGPoint(x: 2_000, y: 400))
        #expect(!panelWindow.isOpen, "let go outside: an unpinned panel closes")
    }
}
