import AppKit
import Foundation
import NotchUI
import SwiftUI
import Testing
@testable import NotchUI
@testable import ClipboardModule

/// What the views draw on Liquid Glass, read from an offscreen render (glass itself cannot be drawn there, so the content is
/// drawn over a flat light or dark grey that stands in for it). Lightness is the least of red, green and blue: white is 1, black
/// and every saturated colour are low, so a white glyph on light glass shows up as a pixel lighter than the background.
@Suite struct ClipboardGlassTests {
    struct Reading {
        let background: Double
        let pixels: [Double]
        func lighter(than margin: Double) -> Int { pixels.filter { $0 > background + margin }.count }
        func darker(than margin: Double) -> Int { pixels.filter { $0 < background - margin }.count }
    }

    func read(_ view: some View, glass: Bool, scheme: ColorScheme, size: CGSize) throws -> Reading {
        let state = NotchLookState()
        state.isGlass = glass
        let shade = !glass ? 0.0 : scheme == .light ? 0.75 : 0.15
        return try NotchLookState.$current.withValue(state) {
            @MainActor func lightness(of view: some View) throws -> [Double] {
                let content = view.frame(width: size.width, height: size.height).background(Color(.sRGB, white: shade))
                    .environment(\.colorScheme, scheme)
                    .environment(\.notchSurface, glass ? .liquidGlass(tinted: false) : .solid)
                let host = NSHostingView(rootView: content)
                host.frame = CGRect(origin: .zero, size: size)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                // AppKit controls follow the window's appearance, not SwiftUI's colour scheme.
                window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                let bitmap = try #require(NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4,
                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
                bitmap.size = size
                host.cacheDisplay(in: host.bounds, to: bitmap)
                var pixels: [Double] = []
                for y in 0..<bitmap.pixelsHigh {
                    for x in 0..<bitmap.pixelsWide {
                        let colour = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                        pixels.append(Double(min(colour.redComponent, colour.greenComponent, colour.blueComponent)))
                    }
                }
                return pixels
            }
            // The renderer lifts tones a little, so the background is what an empty picture reads, not the grey that was set.
            return Reading(background: try lightness(of: Color.clear)[0], pixels: try lightness(of: view))
        }
    }

    struct Fixture {
        let name: String
        let view: AnyView
        let size: CGSize
        /// How far above the background a pixel may be on light glass: a system control lifts its own fill a little. Nil where
        /// the view draws light on a dark fill of its own on purpose.
        let wash: Double?
        /// Pixels of ink the view draws: at least this many are `reach` or more away from the background.
        let ink: Int
        var reach = 0.3
        /// The appearances the classic notch is checked in: a view that draws with the system's colours has only the dark one.
        var classicSchemes: [ColorScheme] = [.dark, .light]
    }

    /// The modules the fixtures draw, kept so they outlive the call that made them.
    static var kept: [ClipboardModuleTests] = []
    static var keptVaults: [ClipboardBoardLockModuleTests] = []

    /// The tab of a started module that has copied `texts`, with the copy stack on first when asked.
    func tab(copying texts: [String], stack: Bool = false) async -> AnyView {
        let fixture = ClipboardModuleTests()
        await fixture.start()
        if stack { fixture.module.startStack() }
        for text in texts { fixture.copy(text) }
        Self.kept.append(fixture)
        guard let tab = fixture.module.makeTab() else { preconditionFailure("a started module has its tab") }
        return tab.content
    }

    var board: ClipboardBoard { ClipboardBoard(id: UUID(), name: "Việc", systemImage: "star", itemIDs: []) }

    var suggestions: ClipboardSuggestionList {
        var list = ClipboardSuggestionList()
        list.update(text: "@", apps: SearchFixtureApps.all)
        return list
    }

    func vault() -> AnyView {
        let fixture = ClipboardBoardLockModuleTests()
        Self.keptVaults.append(fixture)
        return AnyView(
            ClipboardBoardVaultView(module: fixture.module, look: .notch, mode: .setUp, board: board, onDone: {}, onCancel: {})
        )
    }

    /// An item with no source app: an app's icon has white of its own, which is not what is being looked for.
    func item(_ content: ClipboardContent) -> ClipboardItem {
        ClipboardItem(
            id: UUID(), content: content, contentHash: ClipboardContent.hash(of: content), copiedAt: Date(timeIntervalSince1970: 1_800_000_000),
            sourceBundleID: nil, sourceAppName: nil, codeDetection: ClipboardCodeDetector.detect(content)
        )
    }

    func card(_ content: ClipboardContent, selected: Bool = false) -> some View {
        let item = item(content)
        return ClipboardCardView(
            item: item, isSelected: selected, isPinned: true, now: item.copiedAt, imageURL: nil, thumbnails: ClipboardThumbnailCache()
        )
    }

    /// The kind chips and the board row of the tab, with a board chosen: the notch's pills and its "+" button.
    var filters: some View {
        VStack(alignment: .leading, spacing: 6) {
            ClipboardKindChips(selection: .constant(.text))
            ClipboardBoardBar(
                boards: [board], selection: .constant(board.id), editing: nil, name: .constant(""),
                onEdit: { _ in }, onFinish: { _ in }, onDelete: { _ in }, onMove: { _, _ in }, onStep: { _, _ in },
                onIcon: { _, _ in }, onColor: { _, _ in }
            )
        }
    }

    // MARK: What AppKit draws, and what is chosen by the look

    func host(_ view: AnyView) -> (NSHostingView<AnyView>, NSWindow) {
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 40), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return (hosting, window)
    }

    func searchField(onGlass: Bool) -> AnyView {
        AnyView(
            ClipboardSearchField(text: .constant(""), look: .notch, onGlass: onGlass, takesFocus: false, focusRequest: 0) { _ in false }
                .frame(width: 200, height: 24)
        )
    }

    func passwordField(onGlass: Bool) -> AnyView {
        AnyView(
            ClipboardPasswordField(placeholder: "Mật khẩu", text: .constant(""), look: .notch, onGlass: onGlass, onCommit: {}, onCancel: {})
                .frame(width: 200, height: 24)
        )
    }

    @Test func theNotchsFieldsAreDarkOnTheClassicNotchAndTakeTheWindowsAppearanceOnGlass() {
        #expect(ClipboardLook.notch.fieldAppearance(onGlass: false) == .darkAqua)
        #expect(ClipboardLook.notch.fieldAppearance(onGlass: true) == nil)
        for look in [ClipboardLook.library, .panel] {
            #expect(look.fieldAppearance(onGlass: false) == nil, "the windows that follow the system do not force one")
            #expect(look.fieldAppearance(onGlass: true) == nil)
        }
    }

    @Test func theSearchAndPasswordFieldsOfTheNotchFollowTheLookAsItChanges() {
        let makers: [(name: String, make: (Bool) -> AnyView, type: NSView.Type)] = [
            ("search", searchField(onGlass:), NSSearchField.self), ("password", passwordField(onGlass:), NSSecureTextField.self),
        ]
        for (name, make, type) in makers {
            let (hosting, window) = host(make(false))
            func field() -> NSView? {
                var found: NSView?
                func walk(_ view: NSView) {
                    if view.isKind(of: type) { found = view }
                    view.subviews.forEach(walk)
                }
                walk(hosting)
                return found
            }
            #expect(field() != nil, "\(name): the field is drawn")
            #expect(field()?.appearance?.name == .darkAqua, "\(name): dark on the classic notch")
            hosting.rootView = make(true)
            hosting.layoutSubtreeIfNeeded()
            #expect(field()?.appearance == nil, "\(name): the window's on glass, once the look changes")
            hosting.rootView = make(false)
            hosting.layoutSubtreeIfNeeded()
            #expect(field()?.appearance?.name == .darkAqua, "\(name): and dark again")
            window.contentView = nil
        }
    }

    @Test func theTabAndTheLockFormGiveTheirFieldsTheLookOfTheNotch() async {
        let tabView = await tab(copying: [])
        let views: [(name: String, view: AnyView, type: NSView.Type)] = [
            ("the tab's search field", tabView, NSSearchField.self), ("the lock form's password field", vault(), NSSecureTextField.self),
        ]
        for (name, view, type) in views {
            for glass in [false, true] {
                let surface: NotchSurface = glass ? .liquidGlass(tinted: false) : .solid
                let (hosting, window) = host(AnyView(view.environment(\.notchSurface, surface).frame(width: 540, height: 190)))
                var fields: [NSView] = []
                func walk(_ view: NSView) {
                    if view.isKind(of: type) { fields.append(view) }
                    view.subviews.forEach(walk)
                }
                walk(hosting)
                #expect(!fields.isEmpty, "\(name) is drawn")
                #expect(
                    fields.allSatisfy { ($0.appearance?.name == .darkAqua) == !glass },
                    "\(name) is dark on the classic notch and the window's on glass"
                )
                window.contentView = nil
            }
        }
    }

    @Test func theNotchsCardColoursCodeForTheBlackNotchAndForTheSystemOnGlass() {
        let classic = NotchLookState()
        NotchLookState.$current.withValue(classic) {
            let style = ClipboardContentPreview.Style.notch(onGlass: false)
            #expect(style.codePalette == .dark)
            #expect(style.primary == Color.white)
            #expect(style.secondary == Color.white.opacity(0.6))
            #expect(style.swatchBorder == Color.white.opacity(0.2))
        }
        let glass = NotchLookState()
        glass.isGlass = true
        NotchLookState.$current.withValue(glass) {
            let style = ClipboardContentPreview.Style.notch(onGlass: true)
            #expect(style.codePalette == .adaptive)
            #expect(style.primary == Color.primary)
            #expect(style.secondary == Color.secondary)
            #expect(style.swatchBorder == Color.primary.opacity(0.2))
        }
    }

    @Test func theSuggestionsOfTheNotchKeepLightTextOnTheirDarkCardOnLightGlass() async throws {
        let list = ClipboardSuggestionListView(look: .notch, list: suggestions) { _ in }
        let reading = try read(list, glass: true, scheme: .light, size: CGSize(width: 260, height: 150))
        #expect(reading.lighter(than: 0.05) >= 100, "light rows on the dark card, not black on dark")
    }

    var fixtures: [Fixture] {
        get async {
            let tabSize = CGSize(width: 520, height: 190)
            let texts = ["Xin chào, buổi họp lúc 3h chiều", "func add(_ a: Int, _ b: Int) -> Int { a + b }", "https://example.com/bao-cao"]
            let start = ClipboardModuleTests()
            await start.start()
            Self.kept.append(start)
            let stackEntry = CopyStackEntry(id: UUID(), item: item(.text("Xin chào")))
            return [
                // The pieces the tab is made of, one by one: the tab itself has an AppKit search field whose bezel is light on
                // light glass, so it cannot be held to "nothing white".
                Fixture(
                    name: "cards",
                    view: AnyView(HStack(spacing: 6) {
                        card(.text("Xin chào, buổi họp lúc 3h chiều"), selected: true)
                        card(.text("func add(_ a: Int, _ b: Int) -> Int { a + b }"))
                        card(.link(URL(string: "https://example.com/bao-cao")!))
                        card(.color(hex: "#FF8800"))
                    }),
                    size: CGSize(width: 480, height: 130), wash: 0.005, ink: 200, reach: 0.15
                ),
                Fixture(name: "kind chips and boards", view: AnyView(filters), size: CGSize(width: 520, height: 60), wash: 0.005, ink: 100, reach: 0.15),
                Fixture(
                    name: "stack row",
                    view: AnyView(ClipboardStackRow(entry: stackEntry, isNext: false, canMoveUp: false, canMoveDown: false, remove: {}, move: { _ in })),
                    size: CGSize(width: 300, height: 40), wash: 0.005, ink: 50, reach: 0.15
                ),
                Fixture(name: "stack button", view: AnyView(ClipboardStackStartButton(module: start.module)), size: CGSize(width: 110, height: 30), wash: 0.005, ink: 30, reach: 0.15),
                Fixture(name: "tab", view: await tab(copying: texts), size: tabSize, wash: nil, ink: 150, reach: 0.15),
                Fixture(name: "stack", view: await tab(copying: texts, stack: true), size: tabSize, wash: nil, ink: 100, reach: 0.15),
                Fixture(
                    name: "board style strip",
                    view: AnyView(ClipboardBoardStyleStrip(board: board, onIcon: { _ in }, onColor: { _ in }, onDone: {})),
                    size: CGSize(width: 520, height: 40), wash: 0.005, ink: 50, reach: 0.15
                ),
                // A card that is dark on any look, so its light text is meant to be light.
                Fixture(
                    name: "suggestions", view: AnyView(ClipboardSuggestionListView(look: .notch, list: suggestions) { _ in }),
                    size: CGSize(width: 260, height: 150), wash: nil, ink: 100, reach: 0.15
                ),
                Fixture(name: "lock form", view: vault(), size: CGSize(width: 540, height: 150), wash: nil, ink: 100, reach: 0.15),
            ]
        }
    }
    @Test func onLightGlassTheViewsDrawDarkAndNothingWhite() async throws {
        for fixture in await fixtures {
            let reading = try read(fixture.view, glass: true, scheme: .light, size: fixture.size)
            if let wash = fixture.wash {
                #expect(reading.lighter(than: wash) == 0, "\(fixture.name): something is drawn white on light glass")
            }
            #expect(reading.darker(than: fixture.reach) >= fixture.ink, "\(fixture.name): what it draws reads dark")
        }
    }

    @Test func onDarkGlassTheViewsDrawLight() async throws {
        for fixture in await fixtures {
            let reading = try read(fixture.view, glass: true, scheme: .dark, size: fixture.size)
            #expect(reading.lighter(than: fixture.reach) >= fixture.ink, "\(fixture.name): what it draws reads light")
        }
    }

    @Test func onTheClassicNotchTheViewsStayWhiteOnBlackWhateverTheAppearanceIs() async throws {
        for fixture in await fixtures {
            for scheme in fixture.classicSchemes {
                let reading = try read(fixture.view, glass: false, scheme: scheme, size: fixture.size)
                #expect(reading.lighter(than: fixture.reach) >= fixture.ink, "\(fixture.name) in \(scheme)")
            }
        }
    }
}
