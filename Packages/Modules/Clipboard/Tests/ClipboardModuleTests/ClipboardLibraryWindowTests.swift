import AppKit
import MyNotchCore
import MyNotchTestSupport
import NotchUI
import SwiftUI
import Testing
@testable import ClipboardModule

/// The library window follows the screen-recording setting like the notch's windows. The window is made but never put
/// on a screen, so nothing appears and nothing can be captured.
@Suite struct ClipboardLibraryWindowTests {
    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @Test func aNewLibraryWindowIsHiddenFromCaptureWhenTheSettingSaysSo() {
        for (hiding, expected) in [
            (CaptureHiding.never, NSWindow.SharingType.readOnly), (.always, .none),
            // Opened by the user like an open notch, so "only while collapsed" shows it.
            (.whenCollapsed, .readOnly),
        ] {
            let controller = ClipboardLibraryWindowController(interface: NotchInterface(captureHiding: hiding))
            #expect(controller.makeWindow(AnyView(EmptyView())).sharingType == expected, "\(hiding)")
        }
    }

    @Test func theLibraryWindowFollowsTheSettingWhileItIsOpen() async {
        let interface = NotchInterface()
        let controller = ClipboardLibraryWindowController(interface: interface)
        let window = controller.makeWindow(AnyView(EmptyView()))
        #expect(window.sharingType == .readOnly)

        interface.captureHiding = .always
        #expect(await eventually { window.sharingType == .none })
        interface.captureHiding = .never
        #expect(await eventually { window.sharingType == .readOnly })
    }

    @Test func theLibraryWindowIsHostedWithTheAccentOfTheNotch() {
        let controller = ClipboardLibraryWindowController(interface: NotchInterface())
        let window = controller.makeWindow(AnyView(EmptyView()))
        #expect(window.contentViewController is NSHostingController<ClipboardAccentHost<AnyView>>)
    }

    @Test func aClosedLibraryWindowStopsFollowing() async {
        let interface = NotchInterface()
        let controller = ClipboardLibraryWindowController(interface: interface)
        let window = controller.makeWindow(AnyView(EmptyView()))
        controller.stopFollowingSetting()

        interface.captureHiding = .always
        try? await Task.sleep(for: .milliseconds(50))
        #expect(window.sharingType == .readOnly)
    }

    @Test func sidebarKindsHaveDistinctColoursAndValidSymbols() {
        let kinds = ClipboardKind.libraryOrder
        #expect(kinds.count == ClipboardKind.allCases.count)

        let colors = Set(kinds.map(\.sidebarColor))
        #expect(colors.count == kinds.count)

        for kind in kinds {
            #expect(
                NSImage(systemSymbolName: kind.sidebarSystemImage, accessibilityDescription: nil) != nil,
                "\(kind.sidebarSystemImage) should exist as an SF Symbol"
            )
        }
        #expect(NSImage(systemSymbolName: "clock.fill", accessibilityDescription: nil) != nil)
        #expect(ClipboardKind.color.usesMulticolorSidebarSymbol)
        #expect(kinds.filter(\.usesMulticolorSidebarSymbol) == [.color])
    }

    @Test func textKindGridFillsAvailableWidthAlongsideInspector() async throws {
        let pasteboard = FakePasteboard()
        let keystrokes = FakeKeystrokeSender()
        let system = FakeSystem()
        let module = ClipboardModule(
            pasteboard: pasteboard, keystrokes: keystrokes,
            frontmostApp: { system.frontmost }, isTrusted: { system.trusted },
            pasteboardAccessBehavior: { system.accessBehavior }, modifiers: FakeModifierState(), now: { system.now },
            libraryWindow: FakeLibraryWindow(), panelWindow: FakePanelWindow()
        )
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()
        defer { try? FileManager.default.removeItem(at: harness.storageRoot.applicationSupport.deletingLastPathComponent()) }

        var history = ClipboardHistory()
        for i in 0..<20 {
            let content = ClipboardContent.text("Mục văn bản mẫu số \(i) với nội dung khá dài")
            _ = history.add(content, hash: ClipboardContent.hash(of: content), source: ("com.apple.Notes", "Ghi chú"), at: .now.addingTimeInterval(Double(-i * 60)))
        }
        module.state.history = history
        let model = ClipboardLibraryModel(state: module.state, actions: module, now: { .now })
        model.cardSize = .small
        model.selection = .kind(.text)
        model.isInspectorVisible = true

        let controller = ClipboardLibraryWindowController(interface: NotchInterface(), activation: .recorded(ClipboardEditorWindowTests.Recorder()))
        let window = controller.makeWindow(AnyView(ClipboardLibraryView(module: module, model: model)))
        window.setContentSize(NSSize(width: 1080, height: 800))
        controller.register(window, model: model, onClose: {})

        let rootView = try #require(window.contentViewController?.view)
        for _ in 0..<4 { rootView.layoutSubtreeIfNeeded() }
        CATransaction.flush()
        for _ in 0..<4 { rootView.layoutSubtreeIfNeeded() }
        CATransaction.flush()

        let scrollViews = ClipboardModuleTests.views(in: rootView).compactMap { $0 as? NSScrollView }
        let contentScroll = try #require(scrollViews.max(by: { $0.frame.width < $1.frame.width }))
        let docWidth = try #require(contentScroll.documentView?.frame.width)

        // With 1080pt window, ~220pt sidebar, and 290pt inspector, content must expand to fill available width (not shrink to 1-2 centered/offset columns).
        #expect(contentScroll.frame.width >= 500)
        #expect(abs(docWidth - contentScroll.frame.width) < 1)
        #expect(model.columns >= 3)
        controller.close()
    }
}
