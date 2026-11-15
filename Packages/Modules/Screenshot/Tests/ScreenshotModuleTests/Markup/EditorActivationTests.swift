import AppKit
import Testing
@testable import ScreenshotModule

@Suite struct EditorActivationTests {
    let closing = NSObject()
    let other = NSObject()

    func window(_ object: NSObject, visible: Bool = true, miniaturized: Bool = false, titled: Bool = true) -> EditorActivation.WindowState {
        .init(id: ObjectIdentifier(object), isVisible: visible, isMiniaturized: miniaturized, isTitled: titled)
    }

    func policy(_ windows: [EditorActivation.WindowState]) -> NSApplication.ActivationPolicy {
        EditorActivation.policyAfterClosing(ObjectIdentifier(closing), among: windows)
    }

    @Test func theLastEditorGoingAwayReturnsToAMenuBarApp() {
        #expect(policy([window(closing)]) == .accessory)
        #expect(policy([]) == .accessory)
    }

    @Test func anotherVisibleTitledWindowKeepsTheDockIcon() {
        #expect(policy([window(closing), window(other)]) == .regular)
    }

    @Test func aMinimizedWindowStillNeedsTheDockIcon() {
        #expect(policy([window(closing), window(other, visible: false, miniaturized: true)]) == .regular)
    }

    @Test func hiddenOrUntitledWindowsDoNotCount() {
        #expect(policy([window(closing), window(other, visible: false)]) == .accessory)
        #expect(policy([window(closing), window(other, titled: false)]) == .accessory)
    }
}
