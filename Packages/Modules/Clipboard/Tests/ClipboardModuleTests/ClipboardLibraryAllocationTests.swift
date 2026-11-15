import AppKit
import CoreGraphics
import Foundation
import ImageIO
import MyNotchCore
import MyNotchTestSupport
import NotchUI
import SwiftUI
import Testing
@testable import ClipboardModule

/// Opening the library on a history like a real one: what it allocates while it opens. macOS 26's allocator does not give freed pages
/// back to the system (`malloc_zone_pressure_relief` returns nothing), so what is allocated and freed while the window opens stays
/// resident in the process, mostly in `MALLOC_SMALL`; the open has to ask for as little as it can.
///
/// The history is made up from a fixed seed: short and long texts, code, rich text, pictures, links, colours and files from a dozen
/// apps, 500 items (the default limit). `AllocationMeter` counts every malloc of the thread that opens the window.
///
/// `MYNOTCH_ALLOC_LAB=1 xcrun swift test --filter ClipboardLibraryAllocationTests` also runs the lab, which prints (lines that start with
/// `ALLOC`) what the open allocates, by kind of work and by call stack, and the footprint of one open in a process of its own
/// (`MYNOTCH_ALLOC_WARM=1` first shows a panel of SwiftUI, as the notch does, so the window server and Core UI are warm).
/// The ordinary run only checks the budgets.
@Suite(.serialized) final class ClipboardLibraryAllocationTests {
    nonisolated static let lab = ProcessInfo.processInfo.environment["MYNOTCH_ALLOC_LAB"] != nil
    static let itemCount = 500

    let pasteboard = FakePasteboard()
    let keystrokes = FakeKeystrokeSender()
    let libraryWindow = FakeLibraryWindow()
    let panelWindow = FakePanelWindow()
    let system = FakeSystem()
    let modifiers = FakeModifierState()
    let module: ClipboardModule
    let harness: RegistryHarness
    let temporaryRoot: URL

    init() {
        let system = system
        module = ClipboardModule(
            pasteboard: pasteboard, keystrokes: keystrokes,
            frontmostApp: { system.frontmost }, isTrusted: { system.trusted },
            pasteboardAccessBehavior: { system.accessBehavior }, modifiers: modifiers, now: { system.now },
            libraryWindow: libraryWindow, panelWindow: panelWindow
        )
        harness = RegistryHarness([module])
        temporaryRoot = harness.storageRoot.applicationSupport.deletingLastPathComponent()
    }

    deinit {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func start() async {
        await harness.registry.bootstrap()
        #expect(harness.registry.state(of: "clipboard") == .running)
    }

    // MARK: A history like a real one

    /// A small fixed-seed generator, so every run opens the same history.
    struct Generator: RandomNumberGenerator {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    static let apps: [(bundleID: String, name: String)] = [
        ("com.apple.Safari", "Safari"), ("com.apple.dt.Xcode", "Xcode"), ("com.apple.Terminal", "Terminal"), ("com.apple.finder", "Finder"),
        ("com.apple.Notes", "Ghi chú"), ("com.apple.mail", "Mail"), ("com.apple.TextEdit", "TextEdit"), ("com.apple.Preview", "Xem trước"),
        ("com.apple.iCal", "Lịch"), ("com.apple.MobileSMS", "Tin nhắn"), ("com.apple.systempreferences", "Cài đặt hệ thống"), ("com.apple.Music", "Nhạc"),
    ]

    static let sentences = [
        "Hôm nay trời đẹp quá, mình đi dạo công viên nhé.", "Họp lúc 3 giờ chiều, nhớ mang laptop.", "https://example.com/bai-viet/1234?ref=abc",
        "Giá: 1.500.000đ (đã gồm VAT); giao hàng trong 2–3 ngày!", "ssh deploy@10.0.3.17 -p 2222", "Meeting notes: ship the beta on Friday",
        "Cảm ơn anh nhiều, em sẽ gửi lại bản chỉnh sửa trước 5h.", "TODO: kiểm tra lại cấu hình proxy", "The quick brown fox jumps over the lazy dog",
        "Địa chỉ: 12 Nguyễn Huệ, Quận 1, TP. Hồ Chí Minh", "Mã đơn hàng DH-2026-004821", "npm run build && npm run test -- --watch",
    ]

    static let hosts = ["github.com", "developer.apple.com", "vnexpress.net", "stackoverflow.com", "docs.swift.org", "tuoitre.vn", "youtube.com", "medium.com"]

    /// Some prose of about `length` characters.
    static func prose(_ length: Int, _ generator: inout Generator) -> String {
        var text = ""
        var size = 0
        while size < length {
            let piece = sentences.randomElement(using: &generator)! + (Bool.random(using: &generator) ? "\n" : " ")
            text += piece
            size += piece.utf8.count
        }
        return text
    }

    /// A made-up picture as PNG data: a gradient with a little noise, so it is neither flat nor incompressible.
    static func picture(_ index: Int, width: Int, height: Int) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
        var seed = UInt32(truncatingIfNeeded: index &* 2_654_435_761)
        for y in 0..<height {
            for x in 0..<width {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let offset = y * context.bytesPerRow + x * 4
                pixels[offset] = UInt8(truncatingIfNeeded: x * 255 / width + index * 7 + Int(seed >> 29))
                pixels[offset + 1] = UInt8(truncatingIfNeeded: y * 255 / height + Int(seed >> 29))
                pixels[offset + 2] = UInt8(truncatingIfNeeded: (x + y) / 3 + index * 13)
                pixels[offset + 3] = 255
            }
        }
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// `count` items, newest first, the pictures saved. `light` makes the pictures small and leaves out the huge texts, which only the
    /// lab needs, so the tests that always run are quick.
    func makeHistory(count: Int = ClipboardLibraryAllocationTests.itemCount, light: Bool = false) throws -> ClipboardHistory {
        var generator = Generator()
        let store = try #require(module.store)
        let side = light ? (width: 160, height: 100) : (width: 480, height: 320)
        let pictures: [(name: String, bytes: Int)] = (0..<(light ? 8 : 30)).map { index in
            let data = Self.picture(index, width: side.width, height: side.height)
            let name = data.sha256Hex + ".png"
            try? store.saveImage(data, fileName: name)
            return (name, data.count)
        }
        let code = CodeSamples.code
        var items: [ClipboardItem] = []
        for index in 0..<count {
            let app = Self.apps[Int.random(in: 0..<Self.apps.count, using: &generator)]
            let content: ClipboardContent
            switch index % 100 {
            case 0..<44:
                content = .text(Self.prose(Int.random(in: 12...180, using: &generator), &generator) + " #\(index)")
            case 44..<54:
                // A page or two of text; a real history has several of these.
                content = .text(Self.prose(Int.random(in: 2_000...20_000, using: &generator), &generator) + " #\(index)")
            case 54..<56:
                // The rare huge copy: a log, a whole file.
                let size = light ? 20_000 : [200_000, 1_000_000, 600_000, 2_000_000][index / 100 % 4]
                content = .text(Self.prose(size, &generator) + " #\(index)")
            case 56..<70:
                content = .text(code[index % code.count].text + "\n// #\(index)")
            case 70..<76:
                let plain = Self.prose(Int.random(in: 80...1_500, using: &generator), &generator) + " #\(index)"
                let attributed = NSAttributedString(string: plain, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.systemBlue])
                let rtf = try #require(attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:]))
                content = .richText(plain: plain, rtf: rtf)
            case 76..<86:
                let picture = pictures[index % pictures.count]
                content = .image(ClipboardImage(fileName: picture.name, pixelWidth: side.width, pixelHeight: side.height, byteCount: picture.bytes))
            case 86..<94:
                let host = Self.hosts[index % Self.hosts.count]
                content = .link(URL(string: "https://\(host)/articles/\(index)/xem-chi-tiet?utm_source=clipboard&id=\(index * 7)")!)
            case 94..<97:
                content = .color(hex: String(format: "#%02X%02X%02X", (index * 37) & 255, (index * 91) & 255, (index * 53) & 255))
            default:
                content = .files((0..<(1 + index % 3)).map { URL(fileURLWithPath: "/Users/me/Tài liệu/Báo cáo quý \(index)-\($0).pdf") })
            }
            items.append(ClipboardItem(
                id: UUID(), content: content, contentHash: ClipboardContent.hash(of: content),
                copiedAt: system.now.addingTimeInterval(-Double(index) * 1_100), sourceBundleID: app.bundleID, sourceAppName: app.name,
                codeDetection: ClipboardCodeDetector.detect(content)
            ))
        }
        return ClipboardHistory(items: items)
    }

    // MARK: Opening

    /// The library as the module opens it, without a screen: the model, then the real view in a window that is laid out and committed.
    /// Nothing here lets the run loop run, so only this work is in the measure.
    struct Opened {
        let model: ClipboardLibraryModel
        let controller: ClipboardLibraryWindowController
        let window: NSWindow
    }

    func buildModel() -> ClipboardLibraryModel {
        ClipboardLibraryModel(
            state: module.state, actions: module,
            thumbnails: ClipboardThumbnailCache(maxPixelSize: ClipboardThumbnailCache.libraryPixelSize, sharing: module.thumbnails),
            now: { [system] in system.now }
        )
    }

    /// How far the window is taken: laid out only; with Core Animation's commit (what a window on a screen goes through); or drawn into a
    /// bitmap by software on top of that, which a real window never is, so it is for comparison only.
    enum Depth { case layout, commit, bitmap }

    func open(model: ClipboardLibraryModel, depth: Depth = .commit) -> Opened {
        let controller = ClipboardLibraryWindowController(interface: NotchInterface(), activation: .recorded(ClipboardEditorWindowTests.Recorder()))
        let window = controller.makeWindow(AnyView(ClipboardLibraryView(module: module, model: model)))
        controller.register(window, model: model, onClose: {})
        let view = window.contentViewController!.view
        // The width SwiftUI measured is applied by a second pass, as it is when the window comes up.
        for _ in 0..<3 { view.layoutSubtreeIfNeeded() }
        if depth != .layout { CATransaction.flush() }
        if depth == .bitmap, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
        }
        return Opened(model: model, controller: controller, window: window)
    }

    struct Opening {
        var model: AllocationMeter.Report
        var views: AllocationMeter.Report
        var columns: Int
        var shown: Int

        var allocatedBytes: Int { model.allocatedBytes + views.allocatedBytes }
        var peakLiveBytes: Int { max(model.peakLiveBytes, views.peakLiveBytes) }
    }

    /// Opens the library once, in two measured parts (the model, then the views), and closes it. Closed inside an autorelease pool, as an
    /// event of the run loop does, so no window of an earlier measure is still held.
    func measureOpening(attribution: Bool = false, depth: Depth = .commit) -> Opening {
        var model: ClipboardLibraryModel?
        let modelReport = AllocationMeter.measure(attribution: attribution) { model = buildModel() }
        var opened: Opened?
        let viewReport = AllocationMeter.measure(attribution: attribution) { opened = open(model: model!, depth: depth) }
        let result = Opening(model: modelReport, views: viewReport, columns: model?.columns ?? 0, shown: model?.items.count ?? 0)
        autoreleasepool {
            opened?.controller.close()
            opened = nil
            model = nil
        }
        return result
    }

    static func mb(_ bytes: Int) -> String { String(format: "%.2f MB", Double(bytes) / 1_048_576) }

    func report(_ title: String, _ report: AllocationMeter.Report) {
        Swift.print("ALLOC \(title): allocated \(Self.mb(report.allocatedBytes)) in \(report.allocations) allocations, peak live \(Self.mb(report.peakLiveBytes)), live at the end \(Self.mb(report.liveBytesAtEnd))")
    }

    func printGroups(_ title: String, _ report: AllocationMeter.Report) {
        Swift.print("ALLOC --- by kind of work, \(title) ---")
        for total in AllocationMeter.categoryTotals(of: report) {
            Swift.print("ALLOC \(String(format: "%9.1f KB", Double(total.bytes) / 1024)) \(String(format: "%8d", total.count))  \(total.name)")
        }
    }

    // MARK: The budgets

    /// Nothing is done for the items that are not on screen: opening on 500 items costs what opening on 50 does, less a few kilobytes
    /// per item for the model's own counts. The cost of the open is the window's (its toolbar, sidebar and the dozen cards on screen).
    @Test func openingTheLibraryDoesNotAllocateInProportionToTheHistory() async throws {
        await start()
        let full = try makeHistory(count: Self.itemCount, light: true)
        module.state.history = ClipboardHistory(items: Array(full.items.prefix(50)))
        _ = measureOpening()
        let small = measureOpening()
        module.state.history = full
        let large = measureOpening()

        Swift.print("ALLOC budget: 50 items allocate \(Self.mb(small.allocatedBytes)) (model \(small.model.allocatedBytes / 1024) KB), 500 items \(Self.mb(large.allocatedBytes)) (model \(large.model.allocatedBytes / 1024) KB)")
        #expect(small.shown == 50 && large.shown == Self.itemCount)
        // Ten times the items, the same window: the views differ by what the cards on screen hold (a different first screen), not by the count.
        #expect(large.views.allocatedBytes - small.views.allocatedBytes < 6 * 1_048_576)
        // The model: counts and the list, about a kilobyte for each item (in a debug build, where the generic code is not specialised).
        #expect(large.model.allocatedBytes < Self.itemCount * 1_500)
        #expect(small.model.dropped == 0 && large.views.dropped == 0)
    }

    /// The whole open on 500 items, counting this thread only. The numbers are the second open of a process (the first pays for what the
    /// system loads once); the budgets have room for the machines this runs on.
    @Test func openingTheLibraryOn500ItemsStaysWithinItsAllocationBudget() async throws {
        await start()
        module.state.history = try makeHistory(count: Self.itemCount, light: true)
        _ = measureOpening()

        let opening = measureOpening()

        Swift.print("ALLOC budget: opening on \(opening.shown) items, \(opening.columns) columns: allocated \(Self.mb(opening.allocatedBytes)) in \(opening.model.allocations + opening.views.allocations) allocations, peak live \(Self.mb(opening.peakLiveBytes))")
        #expect(opening.shown == Self.itemCount)
        #expect(opening.columns >= 2, "the width SwiftUI measured was applied")
        #expect(opening.allocatedBytes < 90 * 1_048_576)
        #expect(opening.peakLiveBytes < 32 * 1_048_576)
        #expect(opening.model.dropped == 0 && opening.views.dropped == 0)
    }

    @Test func scrollingAndRedrawingCardsInSmallGridDoesNotReallocateIconsOrLabels() async throws {
        await start()
        module.state.history = try makeHistory(count: Self.itemCount, light: true)
        let model = buildModel()
        model.cardSize = .small
        let opened = open(model: model, depth: .commit)
        let visible = Array(model.items.prefix(48))
        #expect(model.columns >= 5)

        // First pass warms the lazy label cache and app/file icon caches.
        var warmIndex = 0
        while warmIndex < visible.count {
            let item = visible[warmIndex]
            _ = model.timeLabel(for: item)
            _ = model.accessibilityLabel(for: item)
            if let bundleID = item.sourceBundleID, let icon = ClipboardIcons.app(bundleID: bundleID) {
                var rect = NSRect(x: 0, y: 0, width: 14, height: 14)
                _ = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil)
            }
            if case .files(let urls) = item.content, let first = urls.first {
                var rect = NSRect(x: 0, y: 0, width: 28, height: 28)
                _ = ClipboardIcons.file(first).cgImage(forProposedRect: &rect, context: nil, hints: nil)
            }
            warmIndex += 1
        }

        let labelsReport = AllocationMeter.measure {
            var index = 0
            while index < visible.count {
                let item = visible[index]
                _ = model.timeLabel(for: item)
                _ = model.accessibilityLabel(for: item)
                if let bundleID = item.sourceBundleID {
                    _ = ClipboardIcons.app(bundleID: bundleID)
                }
                if case .files(let urls) = item.content, let first = urls.first {
                    _ = ClipboardIcons.file(first)
                }
                index += 1
            }
        }
        #expect(labelsReport.allocatedBytes < 4_096)

        let drawReport = AllocationMeter.measure(attribution: true) {
            var index = 0
            while index < visible.count {
                let item = visible[index]
                if let bundleID = item.sourceBundleID, let icon = ClipboardIcons.app(bundleID: bundleID) {
                    var rect = NSRect(x: 0, y: 0, width: 14, height: 14)
                    _ = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil)
                }
                if case .files(let urls) = item.content, let first = urls.first {
                    var rect = NSRect(x: 0, y: 0, width: 28, height: 28)
                    _ = ClipboardIcons.file(first).cgImage(forProposedRect: &rect, context: nil, hints: nil)
                }
                index += 1
            }
        }
        #expect(AllocationMeter.categoryTotals(of: drawReport).first(where: { $0.name == "app and file icons" }) == nil)
        #expect(drawReport.allocatedBytes < 80_000)

        autoreleasepool { opened.controller.close() }
    }

    // MARK: The lab

    @Test(.enabled(if: ClipboardLibraryAllocationTests.lab)) func labOpeningTheLibraryOn500Items() async throws {
        await start()
        let full = try makeHistory()
        module.state.history = full
        // The first open of a process pays for first uses (icons from LaunchServices, formatters, the symbols, Core UI).
        let first = measureOpening()
        Swift.print("ALLOC items \(first.shown), columns \(first.columns)")
        report("first open, model", first.model)
        report("first open, views", first.views)

        let second = measureOpening(attribution: true)
        report("second open, model", second.model)
        report("second open, views", second.views)
        printGroups("model", second.model)
        printGroups("views", second.views)
        Swift.print("ALLOC --- who allocates in the module's own code, views ---")
        for group in AllocationMeter.groups(of: second.views, limit: 400).filter({ $0.label.hasPrefix("clipboard:") }).prefix(12) {
            Swift.print("ALLOC \(String(format: "%9.1f KB", Double(group.bytes) / 1024)) \(String(format: "%8d", group.count))  \(group.label)")
        }
        Swift.print("ALLOC --- the biggest single stacks, views ---")
        for stack in AllocationMeter.topStacks(of: second.views, limit: 6, depth: 14) {
            Swift.print("ALLOC STACK \(String(format: "%.1f KB", Double(stack.bytes) / 1024)) in \(stack.count)")
            for line in stack.frames { Swift.print("ALLOC     \(line)") }
        }

        for depth in [Depth.layout, .commit, .bitmap] {
            _ = measureOpening(depth: depth)
            report("depth \(depth), views", measureOpening(depth: depth).views)
        }

        // What grows with the number of items, and what does not.
        for count in [0, 50, 500, 2_000] {
            let items = count <= full.items.count ? Array(full.items.prefix(count)) : try makeHistory(count: count).items
            module.state.history = ClipboardHistory(items: items)
            _ = measureOpening()
            let measured = measureOpening()
            report("\(count) items, model", measured.model)
            report("\(count) items, views", measured.views)
        }
    }

    /// One open in a process of its own, by the footprint the system keeps for it (what Activity Monitor shows), before the window, while
    /// it is open, and after it is closed and its objects released.
    @Test(.enabled(if: ClipboardLibraryAllocationTests.lab)) func labFootprintOfOneOpen() async throws {
        let environment = ProcessInfo.processInfo.environment
        let count = Int(environment["MYNOTCH_ALLOC_ITEMS"] ?? "") ?? 120
        await start()
        module.state.history = try makeHistory(count: count, light: true)
        func settle(_ seconds: TimeInterval) { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: seconds)) }
        if environment["MYNOTCH_ALLOC_WARM"].map({ !$0.isEmpty }) == true { warmLikeTheApp() }
        settle(1)
        let before = AllocationMeter.process()
        let categoriesBefore = Self.footprintCategories()
        var opened: Opened?
        autoreleasepool { opened = open(model: buildModel()) }
        settle(2)
        let whileOpen = AllocationMeter.process()
        autoreleasepool {
            opened?.controller.close()
            opened = nil
        }
        settle(3)
        let closed = AllocationMeter.process()
        let returned = malloc_zone_pressure_relief(nil, 0)
        let categoriesAfter = Self.footprintCategories()
        for (name, bytes) in categoriesAfter.sorted(by: { ($0.value - (categoriesBefore[$0.key] ?? 0)) > ($1.value - (categoriesBefore[$1.key] ?? 0)) }).prefix(8) {
            Swift.print("ALLOC CATEGORY \(name): +\(Self.mb(bytes - (categoriesBefore[name] ?? 0)))")
        }
        Swift.print("ALLOC FOOTPRINT items=\(count): before \(Self.mb(before.footprint)), open +\(Self.mb(whileOpen.footprint - before.footprint)), closed +\(Self.mb(closed.footprint - before.footprint)) (relief returned \(returned) bytes); in use open +\(Self.mb(whileOpen.sizeInUse - before.sizeInUse)), closed +\(Self.mb(closed.sizeInUse - before.sizeInUse))")
    }

    /// The small pieces a card is made of, each by itself: bytes per call. The module's own code is a few hundred bytes to a few kilobytes
    /// for each item, which is why opening on more items costs almost nothing.
    @Test(.enabled(if: ClipboardLibraryAllocationTests.lab)) func labThePieces() async throws {
        await start()
        let history = try makeHistory(light: true)
        let items = Array(history.items.prefix(100))
        let now = system.now
        func perCall(_ title: String, calls: Int, _ body: () -> Void) {
            body()
            let report = AllocationMeter.measure { body() }
            Swift.print("ALLOC piece \(title): \(report.allocatedBytes / calls) bytes and \(report.allocations / calls) allocations per call")
        }
        perCall("relativeTime", calls: 100) { for item in items { _ = ClipboardCardText.relativeTime(item.copiedAt, now: now) } }
        perCall("accessibilityLabel", calls: 100) { for item in items { _ = ClipboardCardText.accessibilityLabel(for: item, isPinned: false, now: now) } }
        perCall("summary", calls: 100) { for item in items { _ = ClipboardCardText.summary(of: item.content) } }
        perCall("preview of a text", calls: 100) { for item in items { _ = ClipboardCardText.preview(of: item.content.plainText ?? "") } }
        perCall("app icon lookup (cached)", calls: 100) { for item in items { _ = item.sourceBundleID.flatMap { ClipboardIcons.app(bundleID: $0) } } }
        perCall("ClipboardLibraryContent.counts of 500", calls: 1) { _ = ClipboardLibraryContent.counts(of: history) }
    }

    /// What one kind of toolbar item costs on its own: a window with a toolbar of just that item, opened and laid out (the second time).
    @Test(.enabled(if: ClipboardLibraryAllocationTests.lab)) func labToolbarItems() async throws {
        var sort = ClipboardLibrarySort.newest
        var kind: ClipboardKind?
        var layout = ClipboardLibraryLayout.grid
        var size = 1.0
        let sortBinding = Binding(get: { sort }, set: { sort = $0 })
        let kindBinding = Binding(get: { kind }, set: { kind = $0 })
        let layoutBinding = Binding(get: { layout }, set: { layout = $0 })
        let sizeBinding = Binding(get: { size }, set: { size = $0 })

        func measureToolbar<Content: ToolbarContent>(@ToolbarContentBuilder _ content: () -> Content) -> AllocationMeter.Report {
            let toolbar = content()
            func once() -> AllocationMeter.Report {
                AllocationMeter.measure {
                    let controller = NSHostingController(rootView: Text("x").frame(width: 600, height: 300).toolbar { toolbar })
                    controller.sceneBridgingOptions = .all
                    let window = NSWindow(contentViewController: controller)
                    window.styleMask = [.titled, .closable, .resizable]
                    window.isReleasedWhenClosed = false
                    controller.view.layoutSubtreeIfNeeded()
                    controller.view.layoutSubtreeIfNeeded()
                    CATransaction.flush()
                    window.contentViewController = nil
                    window.close()
                }
            }
            _ = once()
            return once()
        }
        report("one plain button", measureToolbar { ToolbarItem { Button { } label: { Label("A", systemImage: "folder.badge.plus") } } })
        report("three plain buttons", measureToolbar {
            ToolbarItem { Button { } label: { Label("A", systemImage: "folder.badge.plus") } }
            ToolbarItem { Button { } label: { Label("B", systemImage: "sidebar.right") } }
            ToolbarItem { Button { } label: { Label("C", systemImage: "sidebar.left") } }
        })
        report("the sort menu (a menu of an inline picker)", measureToolbar {
            ToolbarItem {
                Menu {
                    Picker("Sắp xếp", selection: sortBinding) { ForEach(ClipboardLibrarySort.allCases, id: \.self) { Text($0.title).tag($0) } }
                        .pickerStyle(.inline).labelsHidden()
                } label: { Label("Sắp xếp", systemImage: "arrow.up.arrow.down") }
            }
        })
        report("the filter menu (a picker of labels with symbols)", measureToolbar {
            ToolbarItem {
                Menu {
                    Picker("Loại", selection: kindBinding) {
                        Text("Tất cả loại").tag(ClipboardKind?.none)
                        ForEach(ClipboardKind.libraryOrder, id: \.self) { Label($0.title, systemImage: $0.systemImage).tag(ClipboardKind?.some($0)) }
                    }
                    .pickerStyle(.inline).labelsHidden()
                } label: { Label("Lọc", systemImage: "line.3.horizontal.decrease.circle") }
            }
        })
        report("the card-size slider", measureToolbar { ToolbarItem { Slider(value: sizeBinding, in: 0...2, step: 1).frame(width: 80).labelsHidden() } })
        report("the layout switch (a segmented picker of two labels)", measureToolbar {
            ToolbarItem {
                Picker("Kiểu xem", selection: layoutBinding) {
                    Label("Lưới", systemImage: "square.grid.2x2").tag(ClipboardLibraryLayout.grid)
                    Label("Danh sách", systemImage: "list.bullet").tag(ClipboardLibraryLayout.list)
                }
                .pickerStyle(.segmented).labelsHidden()
            }
        })
    }

    // MARK: Helpers of the lab

    /// What the app has done before the library is first opened: a panel of SwiftUI (like the notch's) with text, symbols and a search
    /// field, shown and gone. It pays for the window server, Core UI and SwiftUI's first uses, which the library then does not.
    func warmLikeTheApp() {
        autoreleasepool {
            let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 600, height: 200), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            panel.isReleasedWhenClosed = false
            var text = ""
            let binding = Binding(get: { text }, set: { text = $0 })
            let host = NSHostingView(rootView: VStack(alignment: .leading) {
                HStack {
                    Image(systemName: "doc.on.clipboard")
                    Image(systemName: "link")
                    Image(systemName: "photo")
                    Image(systemName: "paintpalette")
                    Image(systemName: "pin.fill")
                    ClipboardSearchField(text: binding, onGlass: false, takesFocus: false, focusRequest: 0, onCommand: { _ in false }).frame(width: 140)
                }
                Text("Xin chào, đây là một dòng chữ để khởi động chữ").font(.system(size: 11)).lineLimit(4)
                Text("2 phút trước").font(.system(size: 10))
            }.frame(width: 600, height: 200))
            panel.contentView = host
            host.layoutSubtreeIfNeeded()
            CATransaction.flush()
            panel.contentView = nil
            panel.close()
        }
        RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 1))
    }

    /// The dirty bytes per kind of memory, as `footprint` reports them for this process.
    static func footprintCategories() -> [String: Int] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/footprint")
        process.arguments = ["-p", String(ProcessInfo.processInfo.processIdentifier), "--format", "bytes"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [:] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        var result: [String: Int] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            // "   12345 B   12345 B   0 B   6    MALLOC_SMALL": dirty, clean, reclaimable, the regions, then the name.
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 8, parts[1] == "B", let dirty = Int(parts[0]), parts[3] == "B", parts[5] == "B" else { continue }
            result[parts[7...].joined(separator: " ")] = dirty
        }
        return result
    }
}
