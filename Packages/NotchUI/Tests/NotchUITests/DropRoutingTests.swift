import AppKit
import MyNotchCore
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import NotchUI

@Suite struct DropRoutingTests {
    func tab(_ id: ModuleID, drops: [UTType]) -> NotchTab {
        NotchTab(id: id, title: id.rawValue, systemImage: "circle", dropTypes: drops, content: AnyView(EmptyView()))
    }

    @Test func picksTheFirstTabWhoseTypesMatch() {
        let tabs = [tab("battery", drops: []), tab("shelf", drops: [.fileURL]), tab("other", drops: [.fileURL, .image])]
        #expect(DropRouting.tab(for: [UTType.fileURL.identifier], tabs: tabs) == "shelf")
    }

    @Test func matchesTypesThatConformToAnAcceptedType() {
        let tabs = [tab("shelf", drops: [.image])]
        #expect(DropRouting.tab(for: [UTType.png.identifier], tabs: tabs) == "shelf")
    }

    @Test func noMatchWhenNothingAccepts() {
        let tabs = [tab("battery", drops: []), tab("shelf", drops: [.image])]
        #expect(DropRouting.tab(for: [UTType.fileURL.identifier], tabs: tabs) == nil)
        #expect(DropRouting.tab(for: [], tabs: tabs) == nil)
    }

    @Test func keepsThePreferredTabWhenItAccepts() {
        let tabs = [tab("shelf", drops: [.fileURL]), tab("other", drops: [.fileURL])]
        #expect(DropRouting.tab(for: [UTType.fileURL.identifier], tabs: tabs, preferring: "other") == "other")
    }

    @Test func fallsBackToTheFirstTabWhenThePreferredOneDoesNotAccept() {
        let tabs = [tab("shelf", drops: [.fileURL]), tab("battery", drops: [])]
        #expect(DropRouting.tab(for: [UTType.fileURL.identifier], tabs: tabs, preferring: "battery") == "shelf")
        #expect(DropRouting.tab(for: [UTType.fileURL.identifier], tabs: tabs, preferring: "missing") == "shelf")
    }

    func action(
        tab: ModuleID? = "shelf", inside: Bool = true, dragging: Bool = false, startedInside: Bool = false, refresh: Bool = false
    ) -> DropRouting.DragAction {
        DropRouting.dragAction(dropTab: tab, inside: inside, isDragging: dragging, startedInside: startedInside, isRefresh: refresh)
    }

    @Test func aPointerMoveInsideWithAcceptedTypesEntersDragMode() {
        #expect(action() == .enter("shelf"))
    }

    @Test func leavingOrCarryingNothingAcceptedExitsDragMode() {
        #expect(action(inside: false) == .exit)
        #expect(action(tab: nil) == .exit)
    }

    @Test func aRefreshNeverReEntersDragModeButKeepsIt() {
        #expect(action(refresh: true) == .none)
        #expect(action(dragging: true, refresh: true) == .none)
    }

    @Test func aDragStartedInsideTheNotchDoesNotEnter() {
        #expect(action(startedInside: true) == .none)
    }

    @Test func specificTypeTakesPrecedenceOverGenericContainer() {
        let tabs = [tab("shelf", drops: [.fileURL]), tab("cleaner", drops: [.applicationBundle, .application])]
        let types = [UTType.fileURL.identifier, UTType.applicationBundle.identifier]
        #expect(DropRouting.tab(for: types, tabs: tabs) == "cleaner")
    }

    @Test func specificTypeOverridesPreferredGenericTab() {
        let tabs = [tab("shelf", drops: [.fileURL]), tab("cleaner", drops: [.applicationBundle])]
        let types = [UTType.fileURL.identifier, UTType.applicationBundle.identifier]
        #expect(DropRouting.tab(for: types, tabs: tabs, preferring: "shelf") == "cleaner")
    }

    @Test func genericFileStillRoutesToGenericTab() {
        let tabs = [tab("shelf", drops: [.fileURL]), tab("cleaner", drops: [.applicationBundle])]
        let types = [UTType.fileURL.identifier]
        #expect(DropRouting.tab(for: types, tabs: tabs) == "shelf")
    }

    @Test func prefersCurrentTabWhenBothSpecificallyMatch() {
        let tabs = [tab("photos", drops: [.image]), tab("shelf", drops: [.image])]
        let types = [UTType.png.identifier]
        #expect(DropRouting.tab(for: types, tabs: tabs, preferring: "shelf") == "shelf")
        #expect(DropRouting.tab(for: types, tabs: tabs, preferring: "photos") == "photos")
    }

    @Test func isApplicationURLDetection() {
        #expect(DropRouting.isApplicationURL(URL(fileURLWithPath: "/Applications/Slack.app")))
        #expect(DropRouting.isApplicationURL(URL(fileURLWithPath: "/Applications/TEST.APP")))
        #expect(!DropRouting.isApplicationURL(URL(fileURLWithPath: "/Users/test/document.pdf")))
        #expect(!DropRouting.isApplicationURL(URL(fileURLWithPath: "/Users/test/photo.png")))
    }

    @Test func pasteboardEnrichmentRoutesAppToCleanerAndGenericToShelf() {
        let boardName = NSPasteboard.Name("MyNotchTests.\(UUID().uuidString)")
        let board = NSPasteboard(name: boardName)
        defer { board.releaseGlobally() }

        let tabs = [tab("shelf", drops: [.fileURL]), tab("cleaner", drops: [.applicationBundle, .application])]

        // 1. When pasteboard contains an application bundle URL
        board.clearContents()
        board.writeObjects([NSURL(fileURLWithPath: "/Applications/Safari.app")])
        let appTypes = DropRouting.enrichedTypes(from: [UTType.fileURL.identifier], pasteboard: board)
        #expect(appTypes.contains(UTType.applicationBundle.identifier))
        #expect(DropRouting.tab(for: appTypes, tabs: tabs) == "cleaner")

        // 2. When pasteboard contains a regular file URL
        board.clearContents()
        board.writeObjects([NSURL(fileURLWithPath: "/tmp/report.pdf")])
        let fileTypes = DropRouting.enrichedTypes(from: [UTType.fileURL.identifier], pasteboard: board)
        #expect(!fileTypes.contains(UTType.applicationBundle.identifier))
        #expect(DropRouting.tab(for: fileTypes, tabs: tabs) == "shelf")
    }
}
