import AppKit
import NotchUI
import SwiftUI
import Testing
@testable import ClipboardModule

/// A plain object a view holds, so a weak reference to it says whether the view tree is still alive.
final class ReleaseToken {}

struct ReleaseProbe: View {
    let token: ReleaseToken

    var body: some View {
        Color.clear
    }
}

/// A weak reference that does not keep what it points at, to hold across a closure that made the object.
struct WeakBox<Object: AnyObject> {
    weak var object: Object?

    init(_ object: Object) {
        self.object = object
    }
}

/// Closing a window of the clipboard lets go of what it showed: its views, its model and the pictures only it needed. Each test makes
/// the real window controller's window without putting it on a screen, closes it and waits for the objects to be freed.
extension ClipboardModuleTests {
    func eventuallyFreed(_ freed: () -> Bool) async -> Bool {
        // By the clock, not by the count: the cooperative pool is shared with the heavy tests of this package, which can keep a decode
        // from starting for many seconds.
        let deadline = ContinuousClock.now + .seconds(240)
        while ContinuousClock.now < deadline {
            if freed() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return freed()
    }

    // MARK: Library

    @Test func closingTheLibraryWindowFreesItsViewsAndItsModel() async {
        let recorder = ClipboardEditorWindowTests.Recorder()
        let controller = ClipboardLibraryWindowController(interface: NotchInterface(), activation: .recorded(recorder))
        let (token, model) = makeLibraryWindow(in: controller)

        controller.close()

        #expect(recorder.closedWindows == 1)
        #expect(await eventuallyFreed { token.object == nil })
        #expect(await eventuallyFreed { model.object == nil })
    }

    private func makeLibraryWindow(in controller: ClipboardLibraryWindowController) -> (WeakBox<ReleaseToken>, WeakBox<ClipboardLibraryModel>) {
        let token = ReleaseToken()
        let model = ClipboardLibraryModel(state: module.state, actions: module)
        // The inspector is part of the library's views, so it is part of what is let go.
        model.isInspectorVisible = true
        let content = AnyView(ZStack {
            ClipboardLibraryView(module: module, model: model)
            ReleaseProbe(token: token)
        })
        let window = controller.makeWindow(content)
        // As the module's is: the close handler holds the model, and must not outlive the window.
        controller.register(window, model: model, onClose: { _ = model })
        // Builds the views the way a window on a screen would, so what a hosted toolbar bridges is part of what is checked.
        window.contentViewController?.view.layoutSubtreeIfNeeded()
        return (WeakBox(token), WeakBox(model))
    }

    @Test func theLibraryWindowControllerKeepsNothingOfAClosedWindow() async {
        let controller = ClipboardLibraryWindowController(interface: NotchInterface(), activation: .recorded(ClipboardEditorWindowTests.Recorder()))
        let (_, model) = makeLibraryWindow(in: controller)
        #expect(controller.isOpen)

        controller.close()

        #expect(!controller.isOpen)
        #expect(controller.frame == nil)
        #expect(controller.windowIdentity == nil)
        #expect(await eventuallyFreed { model.object == nil })
    }

    @Test func theModuleKeepsNothingOfAClosedLibrary() async throws {
        await start()
        module.openLibrary()
        let model = try WeakBox(#require(module.library))
        #expect(module.library != nil)

        libraryWindow.close()

        #expect(module.library == nil)
        #expect(await eventuallyFreed { model.object == nil })
    }

    @Test func stoppingTheModuleFreesTheLibrary() async throws {
        await start()
        module.openLibrary()
        let library = try WeakBox(#require(module.library))

        await harness.registry.setEnabled(false, for: "clipboard")

        #expect(module.library == nil)
        #expect(await eventuallyFreed { library.object == nil })
    }

    // MARK: Floating panel

    /// Holds the panel the controller shows without keeping it.
    final class PanelCatcher {
        weak var panel: ClipboardFloatingPanel?
    }

    @Test func closingTheFloatingPanelFreesItsViewsAndItsModel() async {
        let catcher = PanelCatcher()
        let controller = ClipboardPanelController(
            interface: NotchInterface(), clickMonitor: ClipboardPanelClickMonitor(start: { _ in "token" }, stop: { _ in }),
            orderFront: { catcher.panel = $0 }
        )
        let (token, model) = showPanel(in: controller)
        #expect(controller.isOpen)
        #expect(catcher.panel != nil)

        controller.close()

        #expect(!controller.isOpen)
        #expect(await eventuallyFreed { token.object == nil })
        #expect(await eventuallyFreed { model.object == nil })
        // The panel itself goes too, and with it what its content view held.
        #expect(await eventuallyFreed { catcher.panel == nil })
    }

    private func showPanel(in controller: ClipboardPanelController) -> (WeakBox<ReleaseToken>, WeakBox<ClipboardPanelModel>) {
        let token = ReleaseToken()
        let model = ClipboardPanelModel(state: module.state, actions: module, isPinned: false)
        let content = AnyView(ZStack {
            ClipboardPanelView(module: module, model: model)
            ReleaseProbe(token: token)
        })
        controller.show(content, model: model, restoringOrigin: nil, onClose: { _ = model })
        return (WeakBox(token), WeakBox(model))
    }

    // MARK: Large preview

    @Test func closingTheLargePreviewFreesItsViews() async {
        let laptop = ClipboardPanelPlacement.Screen(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 806)
        )
        var panels: [ClipboardPreviewPanel] = []
        let controller = ClipboardPreviewController(
            interface: NotchInterface(), screens: { [laptop] }, clickMonitor: ClipboardPreviewClickMonitor(start: { _ in "token" }, stop: { _ in }),
            center: NotificationCenter(), orderFront: { panels.append($0) }
        )
        let token = showPreview(in: controller)
        #expect(controller.isOpen)

        controller.close()
        panels = []

        #expect(!controller.isOpen)
        #expect(await eventuallyFreed { token.object == nil })
    }

    private func showPreview(in controller: ClipboardPreviewController) -> WeakBox<ReleaseToken> {
        let token = ReleaseToken()
        controller.show(
            AnyView(ReleaseProbe(token: token)), hostFrame: CGRect(x: 100, y: 300, width: 660, height: 420), hostWindow: nil,
            onOutsideClick: { _ = token }
        )
        return WeakBox(token)
    }

    // MARK: Editor

    @Test func closingTheEditorWindowFreesItsViewsAndItsModel() async throws {
        let recorder = ClipboardEditorWindowTests.Recorder()
        let controller = ClipboardEditorWindowController(interface: NotchInterface(), activation: .recorded(recorder))
        module.editors.windowing = controller
        await start()
        copy("Xin chào")
        let item = try #require(items.first)

        #expect(module.edit(item))
        let model = try WeakBox(#require(module.editors.open[item.id]))
        #expect(controller.openCount == 1)

        controller.close(itemID: item.id)

        #expect(controller.openCount == 0)
        #expect(module.editors.open.isEmpty)
        #expect(recorder.closedWindows == 1)
        #expect(await eventuallyFreed { model.object == nil })
    }

    // MARK: Thumbnails

    /// A real picture, written for the thumbnails to read.
    private func writePicture(named name: String) throws -> URL {
        let folder = temporaryRoot.appending(path: "pictures")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        let context = try #require(CGContext(
            data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    @Test func theLibraryAndThePanelShareTheModulesBudgetAndTheirPicturesGoWhenTheyClose() async throws {
        await start()
        let url = try writePicture(named: "one.png")
        module.openLibrary()
        module.togglePanel()
        let library = try #require(module.library)
        let panel = try #require(module.panel)
        let size = ClipboardThumbnailCache.libraryPixelSize

        _ = await module.thumbnails.thumbnail(for: url)
        _ = await library.thumbnails.thumbnail(for: url)
        let glyph = ClipboardThumbnailCache.glyphPixelSize
        _ = await panel.thumbnails.thumbnail(for: url, maxPixelSize: glyph)
        // One budget: the module's handle sees what the library decoded.
        #expect(module.thumbnails.cachedThumbnail(for: url, maxPixelSize: size) != nil)

        // The library closes while the panel is open: the panel still uses the library's size, so nothing it needs goes.
        libraryWindow.close()
        #expect(module.thumbnails.cachedThumbnail(for: url, maxPixelSize: size) != nil)
        #expect(module.thumbnails.cachedThumbnail(for: url, maxPixelSize: glyph) != nil)

        // The panel closes too: the library's size and the rows' size go, the notch's own stays for its next opening.
        panelWindow.close()
        #expect(module.thumbnails.cachedThumbnail(for: url, maxPixelSize: size) == nil)
        #expect(module.thumbnails.cachedThumbnail(for: url, maxPixelSize: glyph) == nil)
        #expect(module.thumbnails.cachedThumbnail(for: url) != nil)
    }

    @Test func aLibraryThatIsOpenedAgainStartsFromWhatTheNotchHolds() async throws {
        await start()
        let url = try writePicture(named: "two.png")
        module.openLibrary()
        _ = await module.library?.thumbnails.thumbnail(for: url)
        libraryWindow.close()
        #expect(module.thumbnails.cachedThumbnail(for: url, maxPixelSize: ClipboardThumbnailCache.libraryPixelSize) == nil)

        module.openLibrary()
        let again = try #require(module.library)
        #expect(await again.thumbnails.thumbnail(for: url) != nil)
        #expect(module.thumbnails.cachedThumbnail(for: url, maxPixelSize: ClipboardThumbnailCache.libraryPixelSize) != nil)
    }

    @Test func stoppingTheModuleForgetsEveryThumbnail() async throws {
        await start()
        let url = try writePicture(named: "three.png")
        _ = await module.thumbnails.thumbnail(for: url)
        #expect(module.thumbnails.cachedThumbnail(for: url) != nil)

        await harness.registry.setEnabled(false, for: "clipboard")

        #expect(module.thumbnails.cachedThumbnail(for: url) == nil)
        #expect(module.thumbnails.stats.cachedCount == 0)
    }

    @Test func lockingABoardForgetsThePicturesOfTheLibraryAndThePanelToo() async throws {
        await start()
        let url = try writePicture(named: "four.png")
        module.openLibrary()
        let library = try #require(module.library)
        _ = await library.thumbnails.thumbnail(for: url)
        #expect(library.thumbnails.cachedThumbnail(for: url) != nil)

        // What `released(_:)` does for the items that leave memory when a board locks.
        module.thumbnails.removeAll()

        #expect(library.thumbnails.cachedThumbnail(for: url) == nil)
    }
}
