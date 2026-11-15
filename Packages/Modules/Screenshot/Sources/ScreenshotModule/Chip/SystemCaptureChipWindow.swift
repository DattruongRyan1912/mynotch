import AppKit
import SwiftUI

/// Borderless, floating over every Space, and never key or main: pressing a button must not take the keyboard from the
/// app in front, and no key press can reach the chip. It is left out of screen captures, so the next capture never shows it.
final class CaptureChipPanel: NSPanel {
    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 220, height: 64), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        // On every Space and next to full-screen apps, and left out of Mission Control's list.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        isReleasedWhenClosed = false
        // MyNotch is not the active app while the chip is up, and a panel that hid then would never show.
        hidesOnDeactivate = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        sharingType = .none
        title = "Ảnh vừa chụp"
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosts the chip's view: accepts the first click although MyNotch is not the active app, and reports the pointer coming
/// and going even then, with a tracking area that is `activeAlways`, which SwiftUI's own hover is not guaranteed to be.
final class CaptureChipHostingView: NSHostingView<AnyView> {
    var hover: @MainActor (Bool) -> Void = { _ in }
    private var pointerArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerArea { removeTrackingArea(pointerArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        pointerArea = area
    }

    override func mouseEntered(with event: NSEvent) { pointerEntered() }
    override func mouseExited(with event: NSEvent) { pointerExited() }

    func pointerEntered() { hover(true) }
    func pointerExited() { hover(false) }
}

/// The real chip window: one panel while a chip is up, made when it first shows and dropped when it goes, so a hidden
/// chip holds no views.
final class SystemCaptureChipWindow: CaptureChipPresenting {
    private let screens: () -> [ChipScreen]
    private let pointer: () -> CGPoint
    private(set) var panel: CaptureChipPanel?
    private var hosting: CaptureChipHostingView?

    /// `screens` and `pointer` are AppKit's by default; a test gives its own.
    init(
        screens: @escaping () -> [ChipScreen] = { NSScreen.screens.map { ChipScreen(frame: $0.frame, visibleFrame: $0.visibleFrame) } },
        pointer: @escaping () -> CGPoint = { NSEvent.mouseLocation }
    ) {
        self.screens = screens
        self.pointer = pointer
    }

    func show(_ content: CaptureChipContent) {
        place(content)
        // Without activating MyNotch: the app in front keeps the keyboard.
        panel?.orderFrontRegardless()
    }

    /// Everything `show` does except putting the panel on screen: its content, its size and its place. Returns the frame
    /// the panel has, which the system aligns to whole pixels.
    @discardableResult
    func place(_ content: CaptureChipContent) -> CGRect {
        let (panel, hosting) = panelAndHosting()
        hosting.hover = content.hover
        hosting.rootView = AnyView(CaptureChipView(thumbnail: content.thumbnail, edit: content.edit, copy: content.copy, pin: content.pin))
        panel.setFrame(CaptureChipGeometry.frame(size: hosting.fittingSize, pointer: pointer(), screens: screens()), display: true)
        return panel.frame
    }

    func hide() {
        guard let panel else { return }
        self.panel = nil
        hosting = nil
        panel.orderOut(nil)
        // Usually hidden from inside one of its own buttons, so its views are let go on the next turn.
        Task { panel.contentView = nil }
    }

    private func panelAndHosting() -> (CaptureChipPanel, CaptureChipHostingView) {
        if let panel, let hosting { return (panel, hosting) }
        let panel = CaptureChipPanel()
        let hosting = CaptureChipHostingView(rootView: AnyView(EmptyView()))
        panel.contentView = hosting
        self.panel = panel
        self.hosting = hosting
        return (panel, hosting)
    }
}
