import AppKit
import Foundation
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import ShelfModule

@Suite struct ShelfDragTests {
    // MARK: The decision

    @Test func onlyADragSomeDestinationAcceptedRemovesTheCard() {
        #expect(!ShelfDragOutcome.removesCard(operation: [], removeAfterDragOut: true))
        for operation: NSDragOperation in [.copy, .move, .link, .generic, .delete, .every, [.copy, .link]] {
            #expect(ShelfDragOutcome.removesCard(operation: operation, removeAfterDragOut: true))
            #expect(!ShelfDragOutcome.removesCard(operation: operation, removeAfterDragOut: false))
        }
        #expect(!ShelfDragOutcome.removesCard(operation: [], removeAfterDragOut: false))
    }

    @Test func aCancelledDragKeepsAPromisedItemAndItsCopy() async throws {
        let fixture = ShelfFixture()
        await fixture.start()
        fixture.settings.set(true, for: fixture.keys.removeAfterDragOut)
        let (adding, gate) = await fixture.startDropThatIsStillLoading()
        gate.release()
        #expect(await adding.value == 1)
        let item = try #require(fixture.items.first)
        let copy = try #require(fixture.module.state.store?.url(of: item))

        fixture.module.didDragEnd(item, operation: [])
        #expect(fixture.items == [item])
        #expect(exists(copy))
        #expect(ShelfStore(directory: fixture.storage.directory, limit: 50).items == [item])
        #expect(exists(copy))
    }

    @Test func aCancelledDragKeepsTextLinkAndFileItems() async throws {
        let fixture = ShelfFixture()
        await fixture.start()
        fixture.settings.set(true, for: fixture.keys.removeAfterDragOut)
        let file = try makeTempFile(in: try makeTempDirectory())
        _ = await fixture.module.add(providers: [
            NSItemProvider(object: file as NSURL),
            NSItemProvider(object: "t" as NSString),
            NSItemProvider(object: URL(string: "https://example.com")! as NSURL),
        ])
        let before = fixture.items
        #expect(before.count == 3)

        for item in before { fixture.module.didDragEnd(item, operation: []) }
        #expect(fixture.items == before)
    }

    @Test func anAcceptedDragRemovesThePromisedItemButLeavesItsCopyForTheNextLoadToSweep() async throws {
        let fixture = ShelfFixture()
        await fixture.start()
        fixture.settings.set(true, for: fixture.keys.removeAfterDragOut)
        let (adding, gate) = await fixture.startDropThatIsStillLoading()
        gate.release()
        _ = await adding.value
        let item = try #require(fixture.items.first)
        let copy = try #require(fixture.module.state.store?.url(of: item))

        fixture.module.didDragEnd(item, operation: .copy)
        #expect(fixture.items.isEmpty)
        #expect(exists(copy))
        #expect(ShelfStore(directory: fixture.storage.directory, limit: 50).items.isEmpty)
        #expect(fixture.promisedEntries.isEmpty)
    }

    @Test func aCompletedDragKeepsTheCardWhenTheSettingIsOff() async {
        let fixture = ShelfFixture()
        await fixture.start()
        _ = await fixture.module.add(providers: [NSItemProvider(object: "a" as NSString)])
        let item = fixture.items[0]

        fixture.module.didDragEnd(item, operation: .copy)
        #expect(fixture.items == [item])
    }

    // MARK: The drag session

    @Test func theSessionReportsItsEndOnceWithTheOperation() {
        var ended: [NSDragOperation] = []
        let session = ShelfDragSession { ended.append($0) }
        session.finish(operation: [])
        session.finish(operation: .copy)
        #expect(ended == [[]])
    }

    @Test func theSessionNeverOffersAMoveOrADelete() {
        #expect(ShelfDragSession.allowedOperations.contains(.copy))
        #expect(!ShelfDragSession.allowedOperations.contains(.move))
        #expect(!ShelfDragSession.allowedOperations.contains(.delete))
    }

    @Test func theDragViewTakesOnlyPlainLeftClicks() throws {
        func event(_ type: NSEvent.EventType, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(
                with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1
            ))
        }
        #expect(ShelfDragSourceView.takes(try event(.leftMouseDown)))
        #expect(!ShelfDragSourceView.takes(try event(.leftMouseDown, .control)))
        #expect(!ShelfDragSourceView.takes(try event(.rightMouseDown)))
        #expect(!ShelfDragSourceView.takes(try event(.leftMouseDragged)))
        #expect(!ShelfDragSourceView.takes(nil))
    }

    // MARK: What a card carries

    private func pasteboard(holding writer: (any NSPasteboardWriting)?) throws -> NSPasteboard {
        let pasteboard = NSPasteboard(name: .init("MyNotchTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([try #require(writer)]))
        return pasteboard
    }

    @Test func theDragWriterCarriesTheFileTheTextOrTheLink() async throws {
        let fixture = ShelfFixture()
        await fixture.start()
        let file = try makeTempFile(in: try makeTempDirectory())
        let link = try #require(URL(string: "https://example.com"))
        _ = await fixture.module.add(providers: [
            NSItemProvider(object: file as NSURL),
            NSItemProvider(object: "t" as NSString),
            NSItemProvider(object: link as NSURL),
        ])
        let writers = fixture.items.map { fixture.module.dragWriter(for: $0) }   // file, text, link
        #expect(writers.count == 3)

        let filePasteboard = try pasteboard(holding: writers[0])
        defer { filePasteboard.releaseGlobally() }
        let dragged = try #require(filePasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])?.first as? URL)
        #expect(dragged.lastPathComponent == "note.txt")
        #expect(dragged.isFileURL)

        let textPasteboard = try pasteboard(holding: writers[1])
        defer { textPasteboard.releaseGlobally() }
        #expect(textPasteboard.string(forType: .string) == "t")

        let linkPasteboard = try pasteboard(holding: writers[2])
        defer { linkPasteboard.releaseGlobally() }
        #expect(linkPasteboard.readObjects(forClasses: [NSURL.self])?.first as? URL == link)
    }

    @Test func aFileMovedWhileTheShelfWasOpenIsDraggedFromWhereItIsNow() async throws {
        let fixture = ShelfFixture()
        await fixture.start()
        let directory = try makeTempDirectory()
        let file = try makeTempFile(in: directory)
        _ = await fixture.module.add(providers: [NSItemProvider(object: file as NSURL)])
        let item = try #require(fixture.items.first)
        let moved = try makeTempDirectory().appending(path: "moved.txt")
        try FileManager.default.moveItem(at: file, to: moved)

        let pasteboard = try pasteboard(holding: fixture.module.dragWriter(for: item))
        defer { pasteboard.releaseGlobally() }
        let dragged = try #require(pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])?.first as? URL)
        #expect(dragged.lastPathComponent == "moved.txt")
    }

    @Test func aCardWhoseFileIsGoneHasNothingToDrag() async throws {
        let fixture = ShelfFixture()
        await fixture.start()
        let file = try makeTempFile(in: try makeTempDirectory())
        _ = await fixture.module.add(providers: [NSItemProvider(object: file as NSURL)])
        let item = try #require(fixture.items.first)
        try FileManager.default.removeItem(at: file)

        #expect(fixture.module.dragWriter(for: item) == nil)
    }

    // MARK: The card

    private func dragLayer(of card: ShelfCardView) throws -> (layer: ShelfDragSourceView, host: NSHostingView<ShelfCardView>) {
        let host = NSHostingView(rootView: card)
        host.frame = NSRect(x: 0, y: 0, width: 76, height: 78)
        host.layoutSubtreeIfNeeded()
        func find(in view: NSView) -> ShelfDragSourceView? {
            (view as? ShelfDragSourceView) ?? view.subviews.lazy.compactMap(find).first
        }
        return (try #require(find(in: host)), host)
    }

    @Test func theCardHasADragLayerOverItsWholeArea() async throws {
        let fixture = ShelfFixture()
        await fixture.start()
        let file = try makeTempFile(in: try makeTempDirectory())
        _ = await fixture.module.add(providers: [NSItemProvider(object: file as NSURL)])
        let item = try #require(fixture.items.first)

        let (layer, host) = try dragLayer(of: ShelfCardView(item: item, state: fixture.module.state, module: fixture.module))
        #expect(layer.convert(layer.bounds, to: host).size == CGSize(width: 76, height: 78))
        #expect(layer.writer() != nil)
        #expect(layer.image().size == CGSize(width: 40, height: 40))
    }

    @Test func theEndOfADragOnTheCardReachesTheShelfWithItsOperation() async throws {
        let fixture = ShelfFixture()
        await fixture.start()
        fixture.settings.set(true, for: fixture.keys.removeAfterDragOut)
        _ = await fixture.module.add(providers: [NSItemProvider(object: "a" as NSString), NSItemProvider(object: "b" as NSString)])
        let (first, second) = (fixture.items[0], fixture.items[1])

        let cancelled = try dragLayer(of: ShelfCardView(item: first, state: fixture.module.state, module: fixture.module)).layer
        cancelled.onEnd([])
        #expect(fixture.items == [first, second])

        let accepted = try dragLayer(of: ShelfCardView(item: second, state: fixture.module.state, module: fixture.module)).layer
        accepted.onEnd(.copy)
        #expect(fixture.items == [first])
    }

    // MARK: Rendering

    @Test func renderingACardNeverResolvesABookmark() throws {
        let directory = try makeTempDirectory()
        let file = try makeTempFile(in: directory)
        let bookmarks = FakeBookmarks()
        let module = ShelfModule()
        let store = bookmarks.store(in: directory)
        module.state.store = store
        let kinds: [ShelfItem.Kind] = [try .file(at: file), bookmarks.item("fake"), .text("t"), .link(URL(string: "https://example.com")!)]
        kinds.forEach { store.add($0, limit: 50) }
        let before = bookmarks.calls

        for item in store.items {
            _ = ShelfCardView(item: item, state: module.state, module: module).body
        }
        #expect(bookmarks.calls == before)
    }
}
