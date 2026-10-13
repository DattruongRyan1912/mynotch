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
}
