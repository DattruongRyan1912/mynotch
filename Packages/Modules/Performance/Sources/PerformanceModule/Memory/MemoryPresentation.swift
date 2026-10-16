import Foundation

nonisolated enum MemoryFormat {
    /// "25,1 GB", "32 GB", "512 MB", "100 KB": 1024-based like Activity Monitor, a comma for the decimal like the rest of the text.
    static func bytes(_ count: UInt64) -> String {
        let (kilo, mega, giga) = (UInt64(1) << 10, UInt64(1) << 20, UInt64(1) << 30)
        if count >= giga {
            let tenths = Int((Double(count) / Double(giga) * 10).rounded())
            return tenths % 10 == 0 ? "\(tenths / 10) GB" : "\(tenths / 10),\(tenths % 10) GB"
        }
        if count >= mega { return "\(Int((Double(count) / Double(mega)).rounded())) MB" }
        return "\(count / kilo) KB"
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    static func pressure(_ pressure: MemoryPressure?) -> String {
        switch pressure {
        case .normal: "Bình thường"
        case .warning: "Cảnh báo"
        case .critical: "Nghiêm trọng"
        case nil: "—"
        }
    }
}

/// Everything the memory half of the tab says, decided in one place.
nonisolated struct MemoryPresentation: Equatable, Sendable {
    let used: String
    let total: String
    let percent: String
    let fraction: Double
    /// From the pressure; nil until something has been read or when the system would not say.
    let tone: Tone?
    let pressure: String
    let swap: String
    let compressed: String
    let accessibilityLabel: String

    init(_ usage: MemoryUsage?) {
        guard let usage else {
            (used, total, percent, fraction, tone) = ("—", "—", "—", 0, nil)
            (pressure, swap, compressed) = ("—", "—", "—")
            accessibilityLabel = "Chưa đọc được bộ nhớ"
            return
        }
        used = MemoryFormat.bytes(usage.used)
        total = MemoryFormat.bytes(usage.total)
        percent = MemoryFormat.percent(usage.fraction)
        fraction = usage.fraction
        tone = usage.pressure.map(Tone.init)
        pressure = MemoryFormat.pressure(usage.pressure)
        swap = MemoryFormat.bytes(usage.swapUsed)
        compressed = MemoryFormat.bytes(usage.compressed)
        accessibilityLabel = "Bộ nhớ đã dùng \(used) trên \(total), \(percent). Áp lực \(pressure). Swap \(swap). Bộ nhớ nén \(compressed)"
    }
}
