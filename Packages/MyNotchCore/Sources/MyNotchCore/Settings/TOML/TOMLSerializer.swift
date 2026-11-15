import Foundation

/// Fast, canonical TOML serializer adhering to the TOML v1.0 specification.
nonisolated public enum TOMLSerializer {
    public static func serialize(_ table: TOMLTable) -> String {
        var lines: [String] = []
        serializeTable(table, prefix: [], lines: &lines)
        return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }

    private static func serializeTable(_ table: TOMLTable, prefix: [String], lines: inout [String]) {
        // Partition keys into scalars/arrays (printed first) and nested tables (printed as sections)
        var scalars: [(String, TOMLValue)] = []
        var subTables: [(String, TOMLTable)] = []
        var arrayTables: [(String, [TOMLTable])] = []

        for key in table.keys.sorted() {
            guard let val = table[key] else { continue }
            switch val {
            case .table(let t):
                subTables.append((key, t))
            case .array(let arr) where isArrayOfTables(arr):
                let tables = arr.compactMap { item -> TOMLTable? in
                    if case .table(let t) = item { return t }
                    return nil
                }
                arrayTables.append((key, tables))
            default:
                scalars.append((key, val))
            }
        }

        // Section header if this is a sub-table
        if !prefix.isEmpty && (!scalars.isEmpty || (subTables.isEmpty && arrayTables.isEmpty)) {
            if !lines.isEmpty && lines.last != "" {
                lines.append("")
            }
            lines.append("[\(formatKeyPath(prefix))]")
        }

        // Output scalars in this table
        for (key, val) in scalars {
            let keyStr = formatSingleKey(key)
            let valStr = serializeValue(val, inline: true)
            lines.append("\(keyStr) = \(valStr)")
        }

        // Output nested sub-tables
        for (key, subTable) in subTables {
            serializeTable(subTable, prefix: prefix + [key], lines: &lines)
        }

        // Output array-of-tables [[prefix.key]]
        for (key, items) in arrayTables {
            for item in items {
                if !lines.isEmpty && lines.last != "" {
                    lines.append("")
                }
                lines.append("[[\(formatKeyPath(prefix + [key]))]]")
                var itemLines: [String] = []
                serializeTable(item, prefix: [], lines: &itemLines)
                lines.append(contentsOf: itemLines)
            }
        }
    }

    private static func isArrayOfTables(_ arr: [TOMLValue]) -> Bool {
        guard !arr.isEmpty else { return false }
        for item in arr {
            if case .table = item { continue }
            return false
        }
        return false // Prefer inline tables inside arrays for compactness unless multi-table document
    }

    public static func serializeValue(_ value: TOMLValue, inline: Bool = false) -> String {
        switch value {
        case .string(let s):
            return escapeString(s)
        case .integer(let i):
            return "\(i)"
        case .float(let d):
            if d.isNaN { return "nan" }
            if d.isInfinite { return d < 0 ? "-inf" : "inf" }
            let s = "\(d)"
            if !s.contains(".") && !s.contains("e") && !s.contains("E") {
                return s + ".0"
            }
            return s
        case .boolean(let b):
            return b ? "true" : "false"
        case .array(let arr):
            let parts = arr.map { serializeValue($0, inline: true) }
            return "[" + parts.joined(separator: ", ") + "]"
        case .table(let t):
            let pairs = t.keys.sorted().map { k -> String in
                let kStr = formatSingleKey(k)
                let vStr = serializeValue(t[k]!, inline: true)
                return "\(kStr) = \(vStr)"
            }
            return "{ " + pairs.joined(separator: ", ") + " }"
        }
    }

    public static func escapeString(_ s: String) -> String {
        var res = "\""
        for scalar in s.unicodeScalars {
            switch scalar.value {
            case 0x22: res.append("\\\"")
            case 0x5C: res.append("\\\\")
            case 0x08: res.append("\\b")
            case 0x09: res.append("\\t")
            case 0x0A: res.append("\\n")
            case 0x0C: res.append("\\f")
            case 0x0D: res.append("\\r")
            case 0x7F: res.append("\\u007F")
            default:
                if scalar.value < 0x20 {
                    res.append(String(format: "\\u%04X", scalar.value))
                } else {
                    res.append(Character(scalar))
                }
            }
        }
        res.append("\"")
        return res
    }

    public static func formatSingleKey(_ key: String) -> String {
        guard !key.isEmpty else { return "\"\"" }
        let isBare = key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        return isBare ? key : escapeString(key)
    }

    public static func formatKeyPath(_ path: [String]) -> String {
        path.map { formatSingleKey($0) }.joined(separator: ".")
    }
}
