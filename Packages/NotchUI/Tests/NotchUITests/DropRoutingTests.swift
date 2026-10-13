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
}
