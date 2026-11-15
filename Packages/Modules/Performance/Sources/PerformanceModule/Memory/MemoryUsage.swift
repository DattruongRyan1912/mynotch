import Darwin

/// How hard macOS is working to keep memory free: the level it reports itself, the one Activity Monitor's pressure graph shows.
nonisolated enum MemoryPressure: Equatable, Sendable {
    case normal
    case warning
    case critical

    /// From `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical. Nil for any other number.
    init?(level: Int) {
        switch level {
        case 1: self = .normal
        case 2: self = .warning
        case 4: self = .critical
        default: return nil
        }
    }
}

/// The page counts of the VM statistics that make up the memory in use. Pages, not bytes.
nonisolated struct VMCounters: Equatable, Sendable {
    var internalPages: UInt64
    var purgeablePages: UInt64
    var wiredPages: UInt64
    var compressedPages: UInt64

    init(internalPages: UInt64, purgeablePages: UInt64, wiredPages: UInt64, compressedPages: UInt64) {
        self.internalPages = internalPages
        self.purgeablePages = purgeablePages
        self.wiredPages = wiredPages
        self.compressedPages = compressedPages
    }

    init(_ statistics: vm_statistics64) {
        self.init(
            internalPages: UInt64(statistics.internal_page_count), purgeablePages: UInt64(statistics.purgeable_count),
            wiredPages: UInt64(statistics.wire_count), compressedPages: UInt64(statistics.compressor_page_count)
        )
    }
}

/// The memory numbers of the Mac at one moment, in bytes.
nonisolated struct MemoryUsage: Equatable, Sendable {
    var total: UInt64
    /// What Activity Monitor calls "Memory Used": app memory (the pages of apps, less the purgeable ones, which are free for the
    /// taking) plus wired plus compressed.
    var used: UInt64
    /// Memory that holds compressed pages; part of `used`.
    var compressed: UInt64
    var swapUsed: UInt64
    /// Nil when the system would not say.
    var pressure: MemoryPressure?

    init(total: UInt64, counters: VMCounters, pageSize: UInt64, swapUsed: UInt64, pressure: MemoryPressure?) {
        self.total = total
        let app = counters.internalPages > counters.purgeablePages ? counters.internalPages - counters.purgeablePages : 0
        used = (app + counters.wiredPages + counters.compressedPages) * pageSize
        compressed = counters.compressedPages * pageSize
        self.swapUsed = swapUsed
        self.pressure = pressure
    }

    init(total: UInt64, used: UInt64, compressed: UInt64, swapUsed: UInt64, pressure: MemoryPressure?) {
        self.total = total
        self.used = used
        self.compressed = compressed
        self.swapUsed = swapUsed
        self.pressure = pressure
    }

    /// The share of memory in use, 0 to 1.
    var fraction: Double {
        total > 0 ? min(Double(used) / Double(total), 1) : 0
    }
}

/// One process and the memory it holds: its physical footprint, the number Activity Monitor's "Memory" column shows.
nonisolated struct ProcessMemory: Equatable, Identifiable, Sendable {
    let pid: Int32
    let name: String
    let footprint: UInt64
    /// Where its executable is, so an app's helper can be shown with the app's icon.
    let path: String?

    var id: Int32 { pid }
}

/// What one read of the memory returns.
nonisolated struct MemorySnapshot: Equatable, Sendable {
    var usage: MemoryUsage?
    /// The heaviest processes, heaviest first; empty when they were not asked for.
    var processes: [ProcessMemory]
}
