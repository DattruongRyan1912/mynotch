import AppKit
import SwiftUI
import Testing
@testable import ClipboardModule

@Suite struct ClipboardSearchFieldTests {
    final class TextBox {
        var text = ""
        var writes: [String] = []

        var binding: Binding<String> {
            Binding(get: { self.text }, set: { self.text = $0; self.writes.append($0) })
        }
    }

    /// Both the text-change notification and the field's delayed search action report the text; only a change is written.
    @Test func onlyChangedTextIsWritten() {
        let box = TextBox()
        box.text = "abc"
        let field = NSSearchField()
        let coordinator = ClipboardSearchField(text: box.binding, takesFocus: true, focusRequest: 0) { _ in true }.makeCoordinator()
        coordinator.field = field
        let changed = Notification(name: NSControl.textDidChangeNotification, object: field)

        field.stringValue = "abc"
        coordinator.searchChanged(field)
        coordinator.controlTextDidChange(changed)
        #expect(box.writes.isEmpty)

        field.stringValue = "abcd"
        coordinator.controlTextDidChange(changed)
        coordinator.searchChanged(field)
        #expect(box.writes == ["abcd"])
    }
}
