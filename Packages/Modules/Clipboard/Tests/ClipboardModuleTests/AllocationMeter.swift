import Darwin
import Foundation
import os

/// Counts what the process allocates while a block runs, and who asks for it. It hooks `malloc_logger`, the hook libmalloc's own stack
/// logging uses, which sees every malloc, calloc, realloc and free with the size. Nothing in the hook allocates or checks exclusivity
/// (it works on raw memory set up before it is switched on), and a block's own allocations are followed to their frees, so the
/// report has both the bytes asked for (the churn that leaves freed pages resident in the process) and the most that was live at once.
///
/// Only allocations made on the main thread are counted by default (the block runs there), so tests running at the same time on other
/// threads do not add to it; frees on any thread still take a block out of what is held. A block must not spin the run loop, which lets
/// other tests' main-actor work in.
nonisolated enum AllocationMeter {
    typealias Hook = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void

    struct Stack {
        var count: Int
        var bytes: Int
        var frames: [UInt]
    }

    struct Report {
        /// Bytes asked for by the allocations that were made, and how many there were.
        var allocatedBytes = 0
        var allocations = 0
        /// Bytes still held, by blocks the block allocated, when it ended.
        var liveBytesAtEnd = 0
        /// The most bytes held at once by blocks the block allocated.
        var peakLiveBytes = 0
        /// Events the table had no room for (nothing is lost when this is 0).
        var dropped = 0
        var stacks: [Stack] = []
    }

    // Raw memory, made before the hook is on: the hook must not allocate.
    private nonisolated(unsafe) static let counters = UnsafeMutablePointer<Int>.allocate(capacity: 16)
    private nonisolated(unsafe) static let lock: UnsafeMutablePointer<os_unfair_lock> = {
        let pointer = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        pointer.initialize(to: os_unfair_lock())
        return pointer
    }()

    private static let tableCapacity = 1 << 20
    private static let stackCapacity = 1 << 17
    private static let frameCount = 32
    // Words per stack entry: key, count, bytes, then the frames.
    private static let stackWords = 3 + frameCount

    private enum Slot {
        static let enabled = 0, mainOnly = 1, attribute = 2
        static let allocatedBytes = 3, allocations = 4, live = 5, peak = 6, dropped = 7
        // The tables' addresses, kept with the counters: a static variable would be checked for exclusivity, which allocates.
        static let table = 8, stackTable = 9
        // The thread that holds the lock, so an allocation made by the hook itself is not counted (and cannot deadlock).
        static let owner = 10
    }

    /// Frames of the stack being taken; used with the lock held.
    private nonisolated(unsafe) static let scratch = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 64)

    private static func enter() -> Bool {
        let me = Int(pthread_mach_thread_np(pthread_self()))
        if counters[Slot.owner] == me { return false }
        os_unfair_lock_lock(lock)
        counters[Slot.owner] = me
        return true
    }

    private static func leave() {
        counters[Slot.owner] = 0
        os_unfair_lock_unlock(lock)
    }

    private static func table() -> UnsafeMutablePointer<UInt>? {
        UnsafeMutablePointer<UInt>(bitPattern: UInt(bitPattern: counters[Slot.table]))
    }

    private static func stackTable() -> UnsafeMutablePointer<UInt>? {
        UnsafeMutablePointer<UInt>(bitPattern: UInt(bitPattern: counters[Slot.stackTable]))
    }

    private static func map(words: Int) -> UnsafeMutablePointer<UInt> {
        let size = words * MemoryLayout<UInt>.stride
        let memory = mmap(nil, size, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0)
        precondition(memory != MAP_FAILED)
        return memory!.assumingMemoryBound(to: UInt.self)
    }

    private static func unmap(_ pointer: UnsafeMutablePointer<UInt>?, words: Int) {
        if let pointer { munmap(pointer, words * MemoryLayout<UInt>.stride) }
    }

    // MARK: Hook

    private static let hook: Hook = { type, _, arg2, arg3, result, _ in
        let c = AllocationMeter.counters
        guard c[Slot.enabled] != 0 else { return }
        let isAlloc = type & 2 != 0, isFree = type & 4 != 0
        // A free (or the free half of a realloc) takes the block out of what is held, whichever thread frees it.
        if isFree, arg2 != 0 { AllocationMeter.forget(pointer: arg2) }
        guard isAlloc, result != 0 else { return }
        if c[Slot.mainOnly] != 0, pthread_main_np() == 0 { return }
        let size = isFree ? Int(arg3) : Int(arg2)
        AllocationMeter.remember(pointer: result, size: size)
    }

    // The hook's code uses `while` loops and raw memory only: a `for` over a range goes through generic code that allocates in a debug build.
    private static func remember(pointer: UInt, size: Int) {
        guard enter() else { return }
        defer { leave() }
        let c = counters
        guard let table = table() else { return }
        c[Slot.allocatedBytes] += size
        c[Slot.allocations] += 1
        var index = Int(pointer >> 4) & (tableCapacity - 1)
        var probes = 0
        while table[index * 2] != 0, table[index * 2] != pointer {
            index = (index + 1) & (tableCapacity - 1)
            probes += 1
            if probes > tableCapacity {
                c[Slot.dropped] += 1
                return
            }
        }
        table[index * 2] = pointer
        table[index * 2 + 1] = UInt(size)
        c[Slot.live] += size
        if c[Slot.live] > c[Slot.peak] { c[Slot.peak] = c[Slot.live] }
        // Stacks are kept for the allocations that carry the bytes: the small ones are most of the count and little of the size.
        if c[Slot.attribute] != 0, size >= 128 { attribute(size: size) }
    }

    private static func forget(pointer: UInt) {
        guard enter() else { return }
        defer { leave() }
        let c = counters
        guard let table = table() else { return }
        var index = Int(pointer >> 4) & (tableCapacity - 1)
        while table[index * 2] != 0 {
            if table[index * 2] == pointer {
                c[Slot.live] -= Int(table[index * 2 + 1])
                // Backward-shift deletion keeps the probe runs intact without tombstones.
                var hole = index
                var next = (index + 1) & (tableCapacity - 1)
                while table[next * 2] != 0 {
                    let home = Int(table[next * 2] >> 4) & (tableCapacity - 1)
                    // The entry may move into the hole when its home is not between the hole (exclusive) and itself (inclusive).
                    let distanceFromHome = (next - home) & (tableCapacity - 1)
                    let distanceFromHole = (next - hole) & (tableCapacity - 1)
                    if distanceFromHome >= distanceFromHole {
                        table[hole * 2] = table[next * 2]
                        table[hole * 2 + 1] = table[next * 2 + 1]
                        hole = next
                    }
                    next = (next + 1) & (tableCapacity - 1)
                }
                table[hole * 2] = 0
                table[hole * 2 + 1] = 0
                return
            }
            index = (index + 1) & (tableCapacity - 1)
        }
    }

    /// Adds the call stack of this allocation to the table of stacks; the lock is held.
    private static func attribute(size: Int) {
        guard let stacks = stackTable() else { return }
        let frames = scratch
        let depth = Int(backtrace(frames, Int32(frameCount)))
        guard depth > 0 else { return }
        var key: UInt = 14_695_981_039_346_656_037
        var index = 0
        while index < depth {
            key = (key ^ UInt(bitPattern: frames[index])) &* 1_099_511_628_211
            index += 1
        }
        if key == 0 { key = 1 }
        var slot = Int(truncatingIfNeeded: key) & (stackCapacity - 1)
        var probes = 0
        while stacks[slot * stackWords] != 0, stacks[slot * stackWords] != key {
            slot = (slot + 1) & (stackCapacity - 1)
            probes += 1
            if probes > stackCapacity { return }
        }
        let base = slot * stackWords
        if stacks[base] == 0 {
            stacks[base] = key
            index = 0
            while index < depth {
                stacks[base + 3 + index] = UInt(bitPattern: frames[index])
                index += 1
            }
        }
        stacks[base + 1] += 1
        stacks[base + 2] += UInt(size)
    }

    // MARK: Measuring

    /// Runs `body` on this thread with the hook on, and reports what it allocated. `attribution` also keeps the call stacks.
    static func measure(attribution: Bool = false, mainThreadOnly: Bool = true, _ body: () -> Void) -> Report {
        // Everything the hook touches exists before it is switched on.
        _ = counters
        _ = lock
        _ = backtrace(scratch, Int32(frameCount))
        counters.update(repeating: 0, count: 16)
        let entries = map(words: tableCapacity * 2)
        let stacks = attribution ? map(words: stackCapacity * stackWords) : nil
        counters[Slot.table] = Int(bitPattern: entries)
        counters[Slot.stackTable] = Int(bitPattern: stacks)
        counters[Slot.mainOnly] = mainThreadOnly ? 1 : 0
        counters[Slot.attribute] = attribution ? 1 : 0

        let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger")!
        let variable = symbol.assumingMemoryBound(to: UInt.self)
        variable.pointee = unsafeBitCast(hook, to: UInt.self)
        counters[Slot.enabled] = 1
        body()
        counters[Slot.enabled] = 0
        variable.pointee = 0

        var report = Report()
        report.allocatedBytes = counters[Slot.allocatedBytes]
        report.allocations = counters[Slot.allocations]
        report.liveBytesAtEnd = counters[Slot.live]
        report.peakLiveBytes = counters[Slot.peak]
        report.dropped = counters[Slot.dropped]
        if let stacks {
            for slot in 0..<stackCapacity where stacks[slot * stackWords] != 0 {
                let base = slot * stackWords
                let frames = (0..<frameCount).map { stacks[base + 3 + $0] }.prefix { $0 != 0 }
                report.stacks.append(Stack(count: Int(stacks[base + 1]), bytes: Int(stacks[base + 2]), frames: Array(frames)))
            }
        }
        counters[Slot.table] = 0
        counters[Slot.stackTable] = 0
        unmap(entries, words: tableCapacity * 2)
        unmap(stacks, words: stackCapacity * stackWords)
        return report
    }

    // MARK: Who asked

    @_silgen_name("swift_demangle")
    private static func swiftDemangle(
        _ name: UnsafePointer<CChar>?, _ length: UInt, _ output: UnsafeMutablePointer<CChar>?, _ outputLength: UnsafeMutablePointer<UInt>?, _ flags: UInt32
    ) -> UnsafeMutablePointer<CChar>?

    static func symbol(of address: UInt) -> (name: String, image: String)? {
        var info = Dl_info()
        guard dladdr(UnsafeRawPointer(bitPattern: address), &info) != 0 else { return nil }
        let image = info.dli_fname.map { URL(fileURLWithPath: String(cString: $0)).lastPathComponent } ?? "?"
        guard let raw = info.dli_sname else { return (String(format: "0x%lx", address), image) }
        let mangled = String(cString: raw)
        let demangled = swiftDemangle(mangled, UInt(mangled.utf8.count), nil, nil, 0)
        defer { free(demangled) }
        return (demangled.map { String(cString: $0) } ?? mangled, image)
    }

    /// The allocations grouped by the innermost frame that is code of the clipboard module (its name, trimmed), or, for stacks with none,
    /// by the innermost frame that is not the allocator's or the standard library's, with the framework it is in. Biggest first.
    static func groups(of report: Report, limit: Int = 30) -> [(bytes: Int, count: Int, label: String)] {
        var totals: [String: (bytes: Int, count: Int)] = [:]
        var cache: [UInt: (name: String, image: String)] = [:]
        func resolve(_ address: UInt) -> (name: String, image: String) {
            if let known = cache[address] { return known }
            let value = symbol(of: address) ?? ("?", "?")
            cache[address] = value
            return value
        }
        let skippedImages: Set<String> = ["libsystem_malloc.dylib", "libswiftCore.dylib", "libsystem_kernel.dylib", "libdyld.dylib", "libsystem_pthread.dylib"]
        for stack in report.stacks {
            var label: String?
            var framework: String?
            for address in stack.frames {
                let (name, image) = resolve(address)
                if name.contains("ClipboardModule.") || name.contains("ClipboardModule)") {
                    // The function, without its arguments and generics, so every call of one function is one line.
                    label = "clipboard: " + String(name.prefix { $0 != "(" && $0 != "<" }).replacing("ClipboardModule.", with: "")
                    break
                }
                if framework == nil, !skippedImages.contains(image), !name.hasPrefix("AllocationMeter"), !name.contains("AllocationMeter") {
                    framework = "\(image): " + String(name.prefix { $0 != "(" && $0 != "<" }.prefix(90))
                }
            }
            let key = label ?? framework ?? "unknown"
            let total = totals[key] ?? (0, 0)
            totals[key] = (total.bytes + stack.bytes, total.count + stack.count)
        }
        return totals.sorted { $0.value.bytes > $1.value.bytes }.prefix(limit).map { ($0.value.bytes, $0.value.count, $0.key) }
    }

    /// The allocations by what the work was, found by looking for the first marker, in this order, among the names of every frame of the stack.
    static let categories: [(name: String, markers: [String])] = [
        ("toolbar", ["Toolbar", "NSToolbar"]),
        ("app and file icons", ["IconServices", "ISIcon", "NSISIconImageRep", "icon(forFile"]),
        ("SF symbols and named images", ["CUICatalog", "NamedImage", "CUIStructured", "CoreGlyphs", "SymbolImage"]),
        ("text layout and drawing", ["NSCoreTypesetter", "CTTypesetter", "CTLine", "NSLayoutManager", "NSTextStorage", "UIFoundation", "ResolvedStyledText", "StyledTextLayout", "TextLayout", "SwiftUI.Text", "CoreText"]),
        ("accessibility", ["Accessibility", "AXPlatform", "NSAccessibility"]),
        ("lists and the sidebar", ["NSTableView", "NSOutlineView", "ListCoreCoordinator", "SidebarList", "NSCollectionView", "ListContainer"]),
        ("lazy grid and view lists", ["LazyLayout", "LazyVGrid", "_ViewList", "ForEach"]),
        ("display list and layers", ["DisplayList", "ViewUpdater", "CALayer", "CA::", "ImageLayer"]),
        ("drawing into the bitmap", ["cacheDisplay", "CGBitmap", "RenderBox", "RB::"]),
        ("window and hosting setup", ["NSWindow", "NSHostingView", "NSHostingController", "viewDidMoveToWindow"]),
        ("graph updates and layout", ["AttributeGraph", "AG::", "ViewGraph", "Layout", "layout"]),
    ]

    /// The name of the category a stack falls in.
    static func category(of stack: Stack, cache: inout [UInt: String]) -> String {
        var names: [String] = []
        for address in stack.frames {
            if let known = cache[address] {
                names.append(known)
            } else {
                let name = symbol(of: address).map { $0.name + " " + $0.image } ?? ""
                cache[address] = name
                names.append(name)
            }
        }
        for (name, markers) in categories {
            for frame in names where markers.contains(where: { frame.contains($0) }) { return name }
        }
        return "other"
    }

    /// The biggest stacks of one category.
    static func topStacks(of report: Report, inCategory name: String, limit: Int = 4, depth: Int = 22) -> [(bytes: Int, count: Int, frames: [String])] {
        var cache: [UInt: String] = [:]
        var chosen = Report()
        chosen.stacks = report.stacks.filter { category(of: $0, cache: &cache) == name }
        return topStacks(of: chosen, limit: limit, depth: depth)
    }

    static func categoryTotals(of report: Report) -> [(bytes: Int, count: Int, name: String)] {
        var totals: [String: (bytes: Int, count: Int)] = [:]
        var cache: [UInt: String] = [:]
        for stack in report.stacks {
            var names: [String] = []
            for address in stack.frames {
                if let known = cache[address] {
                    names.append(known)
                } else {
                    let name = symbol(of: address).map { $0.name + " " + $0.image } ?? ""
                    cache[address] = name
                    names.append(name)
                }
            }
            var chosen = "other"
            outer: for (name, markers) in categories {
                for frame in names where markers.contains(where: { frame.contains($0) }) {
                    chosen = name
                    break outer
                }
            }
            let total = totals[chosen] ?? (0, 0)
            totals[chosen] = (total.bytes + stack.bytes, total.count + stack.count)
        }
        return totals.sorted { $0.value.bytes > $1.value.bytes }.map { ($0.value.bytes, $0.value.count, $0.key) }
    }

    /// The biggest single stacks, innermost frame first, without the allocator's own frames and the hook's, each frame as "image: function".
    static func topStacks(of report: Report, limit: Int = 12, depth: Int = 16) -> [(bytes: Int, count: Int, frames: [String])] {
        report.stacks.sorted { $0.bytes > $1.bytes }.prefix(limit).map { stack in
            var lines: [String] = []
            for address in stack.frames {
                guard let (name, image) = symbol(of: address) else { continue }
                if image == "libsystem_malloc.dylib" || name.contains("AllocationMeter") || name.contains("withUnsafeTemporaryAllocation") { continue }
                lines.append("\(image): " + String(name.prefix(110)))
                if lines.count >= depth { break }
            }
            return (stack.bytes, stack.count, lines)
        }
    }

    // MARK: The process

    /// What the default malloc zone says of the process, and its footprint, for before and after.
    struct Process {
        var sizeAllocated = 0
        var sizeInUse = 0
        var blocksInUse = 0
        var maxSizeInUse = 0
        var footprint = 0
    }

    static func process() -> Process {
        var statistics = malloc_statistics_t()
        malloc_zone_statistics(nil, &statistics)
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return Process(
            sizeAllocated: Int(statistics.size_allocated), sizeInUse: Int(statistics.size_in_use), blocksInUse: Int(statistics.blocks_in_use),
            maxSizeInUse: Int(statistics.max_size_in_use), footprint: result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
        )
    }
}
