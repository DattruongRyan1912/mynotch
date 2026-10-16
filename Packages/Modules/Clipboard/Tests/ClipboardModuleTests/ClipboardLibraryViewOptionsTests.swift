import AppKit
import NotchUI
import SwiftUI
import Testing
@testable import ClipboardModule

/// The card size and the grid or list choice live in a popover that opens from one button of the library's toolbar, and are built when it
/// opens: the library used to carry a slider and a segmented switch in its toolbar from the moment it opened, which was about 10 MB of
/// memory that stays resident. The popover is never presented here (a test must not put a window on the user's screen); its content is
/// hosted in a window that is not shown, and the real controls are driven the way AppKit drives them.
extension ClipboardModuleTests {
    static func views(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { views(in: $0) }
    }

    /// The popover's content, laid out in a window that is never shown.
    struct HostedOptions {
        let host: NSHostingView<ClipboardLibraryViewOptions>
        let window: NSWindow

        var slider: NSSlider? { ClipboardModuleTests.views(in: host).compactMap { $0 as? NSSlider }.first }
        var layoutSwitch: NSSegmentedControl? { ClipboardModuleTests.views(in: host).compactMap { $0 as? NSSegmentedControl }.first }

        /// What a pass of layout does after a change the controls made.
        func settle() {
            for _ in 0..<3 { host.layoutSubtreeIfNeeded() }
        }

        func close() {
            window.contentView = nil
        }
    }

    func hostOptions(of model: ClipboardLibraryModel) -> HostedOptions {
        let host = NSHostingView(rootView: ClipboardLibraryViewOptions(model: model))
        host.frame = CGRect(x: 0, y: 0, width: 240, height: 140)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        let hosted = HostedOptions(host: host, window: window)
        hosted.settle()
        return hosted
    }

    // MARK: Not built until it is opened

    @Test func theSizeSliderAndTheLayoutSwitchAreNotBuiltWhileTheLibraryIsOpenAndTheButtonIsNotPressed() async throws {
        await start()
        module.openLibrary()
        let model = try #require(module.library)
        let controller = ClipboardLibraryWindowController(interface: NotchInterface(), activation: .recorded(ClipboardEditorWindowTests.Recorder()))
        let window = controller.makeWindow(AnyView(ClipboardLibraryView(module: module, model: model)))
        controller.register(window, model: model, onClose: {})
        for _ in 0..<3 { window.contentViewController?.view.layoutSubtreeIfNeeded() }
        CATransaction.flush()

        // The toolbar is there, with its one button for these controls and no switch of its own.
        let items = try #require(window.toolbar).items
        #expect(items.count >= 8)
        #expect(items.filter { $0.label == "Cỡ thẻ và kiểu xem" }.count == 1)
        #expect(!items.contains { $0.label == "Kiểu xem" })
        // And no slider and no segmented control in the toolbar or in the window.
        let everything = (window.contentView.map { Self.views(in: $0) } ?? []) + items.compactMap(\.view).flatMap { Self.views(in: $0) }
        #expect(everything.count > 50, "the window was really built")
        #expect(!everything.contains { $0 is NSSlider })
        #expect(!everything.contains { $0 is NSSegmentedControl })
        #expect(!model.isViewOptionsOpen)

        // They are what the popover is made of, once it is.
        let hosted = hostOptions(of: model)
        #expect(hosted.slider != nil)
        #expect(hosted.layoutSwitch != nil)
        hosted.close()
        controller.close()
        libraryWindow.close()
    }

    @Test func thePopoverStartsClosed() async throws {
        await start()
        module.openLibrary()
        #expect(try #require(module.library).isViewOptionsOpen == false)
        #expect(ClipboardLibraryModel(state: state, actions: module).isViewOptionsOpen == false)
    }

    // MARK: The card size

    @Test func theSliderHasTheThreeSizesAndTheTickMarksItHadInTheToolbar() async throws {
        await start()
        module.openLibrary()
        let hosted = hostOptions(of: try #require(module.library))
        let slider = try #require(hosted.slider)

        #expect(slider.numberOfTickMarks == 3)
        #expect(slider.allowsTickMarkValuesOnly)
        hosted.close()
        libraryWindow.close()
    }

    @Test func movingTheSliderChoosesTheCardSizeAndStoresIt() async throws {
        let (settings, keys) = try settings()
        await start()
        module.openLibrary()
        let model = try #require(module.library)
        let hosted = hostOptions(of: model)
        let slider = try #require(hosted.slider)

        for (position, size) in [(0.0, ClipboardLibraryCardSize.small), (1.0, .large), (0.5, .medium), (0.0, .small)] {
            slider.doubleValue = position
            #expect(slider.sendAction(slider.action, to: slider.target))
            #expect(model.cardSize == size, "position \(position)")
            #expect(settings.value(keys.libraryCardSize) == size)
        }
        hosted.close()
        libraryWindow.close()
    }

    @Test func theSliderStartsAtTheStoredSize() async throws {
        let (settings, keys) = try settings()
        settings.set(.large, for: keys.libraryCardSize)
        await start()
        module.openLibrary()
        let hosted = hostOptions(of: try #require(module.library))

        #expect(try #require(hosted.slider).doubleValue == 1.0)
        hosted.close()
        libraryWindow.close()
    }

    @Test func aSizeChosenElsewhereMovesTheSlider() async throws {
        await start()
        module.openLibrary()
        let model = try #require(module.library)
        let hosted = hostOptions(of: model)
        #expect(try #require(hosted.slider).doubleValue == 0.5)

        model.cardSize = .small
        hosted.settle()

        #expect(try #require(hosted.slider).doubleValue == 0.0)
        hosted.close()
        libraryWindow.close()
    }

    @Test func theSliderBindingRoundsAndClampsLikeTheSliderAlwaysDid() async throws {
        await start()
        module.openLibrary()
        let model = try #require(module.library)
        let binding = ClipboardLibraryViewOptions.sliderBinding(for: model)

        binding.wrappedValue = 0.4
        #expect(model.cardSize == .small)
        binding.wrappedValue = 1.6
        #expect(model.cardSize == .large)
        binding.wrappedValue = 9
        #expect(model.cardSize == .large)
        binding.wrappedValue = -3
        #expect(model.cardSize == .small)
        binding.wrappedValue = .nan
        #expect(model.cardSize == .medium)
        #expect(binding.wrappedValue == 1.0)
        libraryWindow.close()
    }

    // MARK: The layout

    @Test func theGridAndListSwitchWorksThroughThePopoverAndIsStored() async throws {
        let (settings, keys) = try settings()
        await start()
        module.openLibrary()
        let model = try #require(module.library)
        let hosted = hostOptions(of: model)
        let layoutSwitch = try #require(hosted.layoutSwitch)
        #expect(layoutSwitch.segmentCount == 2)
        #expect(layoutSwitch.selectedSegment == 0)
        #expect(model.layout == .grid)

        layoutSwitch.selectedSegment = 1
        #expect(layoutSwitch.sendAction(layoutSwitch.action, to: layoutSwitch.target))
        #expect(model.layout == .list)
        #expect(settings.value(keys.libraryLayout) == .list)

        layoutSwitch.selectedSegment = 0
        #expect(layoutSwitch.sendAction(layoutSwitch.action, to: layoutSwitch.target))
        #expect(model.layout == .grid)
        #expect(settings.value(keys.libraryLayout) == .grid)
        hosted.close()
        libraryWindow.close()
    }

    @Test func cardsHaveASizeAndRowsHaveNone() async throws {
        await start()
        module.openLibrary()
        let model = try #require(module.library)
        let hosted = hostOptions(of: model)
        #expect(hosted.slider != nil)

        model.layout = .list
        hosted.settle()
        #expect(hosted.slider == nil, "a list has no card size to choose")
        #expect(hosted.layoutSwitch != nil)

        model.layout = .grid
        hosted.settle()
        #expect(hosted.slider != nil)
        hosted.close()
        libraryWindow.close()
    }

    @Test func theSwitchStartsAtTheStoredLayoutAndAListShowsNoSlider() async throws {
        let (settings, keys) = try settings()
        settings.set(.list, for: keys.libraryLayout)
        await start()
        module.openLibrary()
        let hosted = hostOptions(of: try #require(module.library))

        #expect(try #require(hosted.layoutSwitch).selectedSegment == 1)
        #expect(hosted.slider == nil)
        hosted.close()
        libraryWindow.close()
    }

    @Test func thePopoverGoesWithItsViewsWhenItIsDismissed() async throws {
        await start()
        module.openLibrary()
        let model = try #require(module.library)
        weak var weakHost: NSHostingView<ClipboardLibraryViewOptions>?
        autoreleasepool {
            let hosted = hostOptions(of: model)
            weakHost = hosted.host
            hosted.close()
        }
        #expect(await eventuallyFreed { weakHost == nil })
        libraryWindow.close()
    }
}
