import AppKit
import SwiftUI
import Testing
@testable import ClipboardModule

/// Records what the module asks of a preview window, so no test creates a real one.
final class FakePreviewWindow: ClipboardPreviewWindowing {
    private(set) var isOpen = false
    private(set) var showCount = 0
    private(set) var closeCount = 0
    private(set) var hostFrame: CGRect?
    private(set) var hostWindow: ObjectIdentifier?
    /// Runs when the preview closes, so a test can look at what had happened by then.
    var onClose: (() -> Void)?
    private var outsideClick: (() -> Void)?

    func show(_ content: AnyView, hostFrame: CGRect?, hostWindow: ObjectIdentifier?, onOutsideClick: @escaping () -> Void) {
        showCount += 1
        isOpen = true
        self.hostFrame = hostFrame
        self.hostWindow = hostWindow
        outsideClick = onOutsideClick
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        closeCount += 1
        outsideClick = nil
        onClose?()
    }

    /// The user clicking anywhere but the preview.
    func clickOutside() {
        outsideClick?()
    }
}

/// The large preview as the module wires it to the library window and the floating panel.
extension ClipboardModuleTests {
    func openPanelPreview() throws -> ClipboardPanelModel {
        module.togglePanel()
        let panel = try #require(module.panel)
        panel.togglePreview()
        return panel
    }

    // MARK: Showing

    @Test func thePanelsPreviewIsShownOverThePanelsDisplay() async throws {
        await start()
        copy("Xin chào")
        panelWindow.frame = CGRect(x: 100, y: 200, width: 660, height: 420)

        let panel = try openPanelPreview()

        #expect(panel.isPreviewOpen)
        #expect(panelPreview.isOpen)
        #expect(panelPreview.showCount == 1)
        #expect(panelPreview.hostFrame == CGRect(x: 100, y: 200, width: 660, height: 420))
        // Told which window its clicks are swallowed for.
        #expect(panelPreview.hostWindow == ObjectIdentifier(panelWindow))
        #expect(!libraryPreview.isOpen)
    }

    @Test func theLibrarysPreviewIsShownOverTheLibraryWindow() async throws {
        await start()
        copy("Xin chào")
        libraryWindow.frame = CGRect(x: 50, y: 60, width: 980, height: 640)
        module.openLibrary()
        let library = try #require(module.library)
        library.select(try #require(items.first).id, mode: .replace)

        library.togglePreview()

        #expect(libraryPreview.isOpen)
        #expect(libraryPreview.hostFrame == CGRect(x: 50, y: 60, width: 980, height: 640))
        #expect(libraryPreview.hostWindow == ObjectIdentifier(libraryWindow))
        #expect(!panelPreview.isOpen)
    }

    @Test func closingThePreviewTakesTheWindowAway() async throws {
        await start()
        copy("Xin chào")
        let panel = try openPanelPreview()

        panel.closePreview()

        #expect(!panelPreview.isOpen)
        #expect(panelPreview.closeCount == 1)
    }

    @Test func aClickOutsideThePreviewClosesItAndNotThePinnedPanel() async throws {
        let (settings, keys) = try settings()
        settings.set(true, for: keys.panelPinned)
        await start()
        copy("Xin chào")
        let panel = try openPanelPreview()

        panelPreview.clickOutside()

        #expect(!panel.isPreviewOpen)
        #expect(!panelPreview.isOpen)
        #expect(panelWindow.isOpen)
    }

    // MARK: Going away with the window

    @Test func closingThePanelClosesItsPreview() async throws {
        await start()
        copy("Xin chào")
        _ = try openPanelPreview()

        module.togglePanel()

        #expect(!panelWindow.isOpen)
        #expect(!panelPreview.isOpen)
    }

    @Test func closingTheLibraryClosesItsPreview() async throws {
        await start()
        copy("Xin chào")
        module.openLibrary()
        let library = try #require(module.library)
        library.select(try #require(items.first).id, mode: .replace)
        library.togglePreview()

        libraryWindow.close()

        #expect(!libraryPreview.isOpen)
        #expect(module.library == nil)
    }

    @Test func stoppingTheModuleClosesBothPreviews() async throws {
        await start()
        copy("Xin chào")
        _ = try openPanelPreview()
        module.openLibrary()
        let library = try #require(module.library)
        library.select(try #require(items.first).id, mode: .replace)
        library.togglePreview()
        #expect(panelPreview.isOpen && libraryPreview.isOpen)

        await harness.registry.setEnabled(false, for: "clipboard")

        #expect(!panelPreview.isOpen)
        #expect(!libraryPreview.isOpen)
    }

    @Test func eachWindowHasItsOwnPreview() async throws {
        await start()
        copy("Xin chào")
        _ = try openPanelPreview()
        module.openLibrary()
        let library = try #require(module.library)
        library.select(try #require(items.first).id, mode: .replace)
        library.togglePreview()

        panelPreview.clickOutside()

        #expect(!panelPreview.isOpen)
        #expect(libraryPreview.isOpen)
    }

    // MARK: Using the item

    @Test func returnFromAPinnedPanelClosesThePreviewBeforeTheKeyboardIsHandedBackAndBeforeCommandV() async throws {
        let (settings, keys) = try settings()
        settings.set(.paste, for: keys.clickAction)
        settings.set(true, for: keys.panelPinned)
        await start()
        copy("Xin chào")
        let panel = try openPanelPreview()
        var previewOpenAtHandBack: Bool?
        var writesWhenPreviewClosed: Int?
        panelWindow.onReturnKeyboard = { [self] in previewOpenAtHandBack = panelPreview.isOpen }
        panelPreview.onClose = { [self] in writesWhenPreviewClosed = pasteboard.writes.count }

        panel.activate(try #require(items.first).id)

        #expect(previewOpenAtHandBack == false)
        // Closed before anything was written to the pasteboard, so before the paste could start.
        #expect(writesWhenPreviewClosed == 0)
        #expect(keystrokes.pasteCount == 0)
        harness.scheduler.advance(by: .milliseconds(80))
        #expect(keystrokes.pasteCount == 1)
    }

    @Test func returnFromAnUnpinnedPanelClosesThePreviewThenThePanelThenChecksThenPastes() async throws {
        let (settings, keys) = try settings()
        settings.set(.paste, for: keys.clickAction)
        await start()
        copy("Xin chào")
        let panel = try openPanelPreview()
        var previewOpenAtCheck: Bool?
        panelWindow.onKeyboardCheck = { [self] in previewOpenAtCheck = panelPreview.isOpen }

        panel.activate(try #require(items.first).id)

        #expect(previewOpenAtCheck == false)
        #expect(panelWindow.closeCount == 1)
        harness.scheduler.advance(by: .milliseconds(80))
        #expect(keystrokes.pasteCount == 1)
    }

    @Test func returnInTheLibraryClosesThePreviewBeforeUsingTheCard() async throws {
        let (settings, keys) = try settings()
        settings.set(.copy, for: keys.clickAction)
        await start()
        copy("Xin chào")
        module.openLibrary()
        let library = try #require(module.library)
        library.select(try #require(items.first).id, mode: .replace)
        library.togglePreview()
        var writesWhenPreviewClosed: Int?
        libraryPreview.onClose = { [self] in writesWhenPreviewClosed = pasteboard.writes.count }

        #expect(library.activateSelection())

        #expect(writesWhenPreviewClosed == 0)
        #expect(pasteboard.writes.last?.content == .text("Xin chào"))
        #expect(!libraryPreview.isOpen)
    }

    // MARK: The notch's tab

    /// The notch's window as the tab's key hook would report it, and a recorder for the pin.
    func attachNotch(frame: CGRect = CGRect(x: 400, y: 700, width: 640, height: 200)) -> NotchRecorder {
        let recorder = NotchRecorder()
        module.tabPreview.hostWindow = { (frame, ObjectIdentifier(recorder)) }
        module.tabPreview.pinNotch = { recorder.pins.append($0) }
        return recorder
    }

    final class NotchRecorder {
        var pins: [Bool] = []
    }

    @Test func theNotchTabsPreviewIsShownOverTheNotchsDisplayAndPinsTheNotch() async throws {
        await start()
        copy("Xin chào")
        let notch = attachNotch()

        module.tabPreview.togglePreview()

        #expect(module.tabPreview.isPreviewOpen)
        #expect(tabPreview.isOpen)
        #expect(tabPreview.hostFrame == CGRect(x: 400, y: 700, width: 640, height: 200))
        #expect(tabPreview.hostWindow == ObjectIdentifier(notch))
        #expect(notch.pins == [true])
        #expect(!panelPreview.isOpen && !libraryPreview.isOpen)
    }

    @Test func closingTheNotchTabsPreviewTakesTheWindowAwayAndUnpinsTheNotch() async throws {
        await start()
        copy("Xin chào")
        let notch = attachNotch()
        module.tabPreview.togglePreview()

        module.tabPreview.closePreview()

        #expect(!tabPreview.isOpen)
        #expect(notch.pins == [true, false])
    }

    @Test func aClickOutsideTheNotchTabsPreviewClosesItAndUnpins() async throws {
        await start()
        copy("Xin chào")
        let notch = attachNotch()
        module.tabPreview.togglePreview()

        tabPreview.clickOutside()

        #expect(!module.tabPreview.isPreviewOpen)
        #expect(notch.pins == [true, false])
    }

    @Test func stoppingTheModuleClosesTheNotchTabsPreviewToo() async throws {
        await start()
        copy("Xin chào")
        let notch = attachNotch()
        module.tabPreview.togglePreview()

        await harness.registry.setEnabled(false, for: "clipboard")

        #expect(!tabPreview.isOpen)
        #expect(!module.tabPreview.isPreviewOpen)
        #expect(notch.pins == [true, false])
    }

    @Test func theNotchTabsPreviewFollowsTheNewestCopyThatArrivesWhileItIsOpenOnlyIfItWasNotChosen() async throws {
        await start()
        copy("một")
        _ = attachNotch()
        module.tabPreview.togglePreview()
        let shown = try #require(module.tabPreview.previewedItem)

        copy("hai")
        // The first card stood in for a selection nobody made; opening the preview made it the user's.
        #expect(module.tabPreview.previewedItem?.id == shown.id)
    }

    /// Return in the notch: the preview goes, then the notch's own paste path (write, close the notch, ⌘V after its short delay).
    @Test func returnWithTheNotchTabsPreviewOpenClosesItBeforeAnythingIsWrittenThenPastesThroughTheNotchsPath() async throws {
        let (settings, keys) = try settings()
        settings.set(.paste, for: keys.clickAction)
        await start()
        copy("Xin chào")
        let notch = attachNotch()
        module.tabPreview.togglePreview()
        var writesWhenPreviewClosed: Int?
        var notchClosesWhenPreviewClosed: Int?
        tabPreview.onClose = { [self] in
            writesWhenPreviewClosed = pasteboard.writes.count
            notchClosesWhenPreviewClosed = harness.presenter.closeCount
        }

        let key = ClipboardPreviewKeys.Key(keyCode: 36, characters: "\r", modifiers: [])
        #expect(module.tabPreview.handlePreviewKey(key, target: .searchField, hasMarkedText: false))

        #expect(writesWhenPreviewClosed == 0)
        #expect(notchClosesWhenPreviewClosed == 0)
        #expect(pasteboard.writes.last?.content == .text("Xin chào"))
        // The notch is closed by the paste, as for a click on the card; ⌘V goes out after the short delay.
        #expect(harness.presenter.closeCount == 1)
        #expect(keystrokes.pasteCount == 0)
        harness.scheduler.advance(by: .milliseconds(80))
        #expect(keystrokes.pasteCount == 1)
        #expect(notch.pins == [true, false])
    }

    // MARK: Pictures

    @Test func aStoredPictureIsReadFromItsFile() async throws {
        await start()
        let content = Self.image("a")
        guard case .image(let image) = content else { return }
        let store = try #require(module.store)
        try store.saveImage(Data("x".utf8), fileName: image.fileName)
        module.update { history in
            history.add(content, hash: ClipboardContent.hash(of: content), source: (nil, nil), at: system.now)
            return []
        }

        let item = try #require(items.first)
        #expect(module.previewImageSource(of: item) == .file(imageFile(image.fileName)))
    }

    @Test func aTextHasNoPictureToRead() async throws {
        await start()
        copy("Xin chào")
        #expect(module.previewImageSource(of: try #require(items.first)) == nil)
    }

    @Test func aStoppedModuleHasNoPictureToRead() {
        guard case .image = Self.image("a") else { return }
        let item = Self.item(Self.image("a"), copiedAt: system.now)
        #expect(module.previewImageSource(of: item) == nil)
    }

    // MARK: Nothing is written

    /// Every file under the module's folder with its size, to compare before and after.
    func snapshotOfTheModuleFolder() -> [String: Int] {
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return [:] }
        var found: [String: Int] = [:]
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { found[url.path(percentEncoded: false)] = values?.fileSize ?? 0 }
        }
        return found
    }

    @Test func previewingEveryKindWritesNothingToTheModulesFolder() async throws {
        await start()
        let store = try #require(module.store)
        let content = Self.image("b")
        guard case .image(let image) = content else { return }
        try store.saveImage(Data("x".utf8), fileName: image.fileName)
        module.update { history in
            for content in [
                ClipboardContent.text("Xin chào"), .link(URL(string: "https://example.com/a")!), .color(hex: "#FF8800"),
                .files([URL(fileURLWithPath: "/definitely/not/here.txt")]), content,
            ] {
                history.add(content, hash: ClipboardContent.hash(of: content), source: (nil, nil), at: system.now)
            }
            return []
        }
        await module.store?.flush()
        let before = snapshotOfTheModuleFolder()

        module.togglePanel()
        let panel = try #require(module.panel)
        for _ in 0..<panel.items.count {
            panel.togglePreview()
            // What the window would draw: every kind's content and its picture's source, built and thrown away.
            let item = try #require(panel.previewedItem)
            _ = ClipboardPreviewContent(item: item)
            _ = module.previewImageSource(of: item)
            panel.closePreview()
            _ = panel.handleKey(.next)
        }
        await module.store?.flush()

        #expect(snapshotOfTheModuleFolder() == before)
    }

    /// The preview, the editor and the inspector have no way to write: nothing in their sources creates, copies or writes a file (and
    /// the editor's words, which may be a secret of an open board, are never put anywhere but the history). A guard against the day
    /// someone reaches for a temporary file to hand something to Quick Look, or a draft of the editor to the disk.
    @Test func theSourcesThatShowOrEditNeverReachForTheFileSystemsWritingCalls() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(components: "Sources", "ClipboardModule")
        var files: [URL] = []
        for folder in ["Preview", "Editor", "Inspector"] {
            let found = try FileManager.default.contentsOfDirectory(at: sources.appending(path: folder), includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "swift" }
            #expect(found.count >= (folder == "Preview" ? 8 : 4), "\(folder) has \(found.count) sources")
            files += found
        }
        // The module's side of the editor lives beside the module, not in the folder.
        files.append(sources.appending(path: "ClipboardModule+Edit.swift"))
        let forbidden = [
            ".write(to", "createFile", "createDirectory", "copyItem", "moveItem", "temporaryDirectory", "NSTemporaryDirectory",
            "FileHandle(forWriting", "FileHandle(forUpdating", "NSSavePanel", "replaceItem", "atomically",
            "mkstemp", "mkdtemp", "fopen(", "Darwin.open", "FileManager", "CGImageDestination", "saveBestRepresentation", "FileWrapper",
            "NSFileCoordinator", "fwrite", "creat(", "NSSavePanel", "NSItemProvider", "registerFileRepresentation", "QLPreviewItem",
        ]
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for word in forbidden {
                #expect(!text.contains(word), "\(file.lastPathComponent) contains \(word)")
            }
        }
    }
}
