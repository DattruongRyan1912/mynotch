import Foundation

/// Maps between hierarchical TOML tables and flat SettingsStore keys (`"interface.*"`, `"app.*"`, `"module.<id>.*"`).
nonisolated public enum ConfigKeyMapper {
    private static let appSubGroups: Set<String> = ["menuBarHider", "storage", "equalizer"]

    /// Flattens a TOMLTable into a dictionary of flat setting keys and their canonical JSON data.
    public static func flattenToJSONSettings(_ table: TOMLTable) throws -> [String: Data] {
        var result: [String: Data] = [:]

        // 1. Process explicit flat keys at root (e.g. "interface.openDelayMs" = 150)
        for (rootKey, rootVal) in table {
            if rootKey.contains(".") {
                if rootKey == "app.permissionIdentity" { continue }
                if isValidKey(rootKey) {
                    let jsonData = try rootVal.toCanonicalJSONData()
                    result[rootKey] = jsonData
                }
            }
        }

        // 2. Process hierarchical sections
        if case .table(let ifaceTable) = table["interface"] {
            for (key, val) in ifaceTable {
                let fullKey = "interface.\(key)"
                result[fullKey] = try val.toCanonicalJSONData()
            }
        }

        if case .table(let appTable) = table["app"] {
            for (key, val) in appTable {
                if appSubGroups.contains(key), case .table(let subTable) = val {
                    for (subKey, subVal) in subTable {
                        let fullKey = "app.\(key).\(subKey)"
                        result[fullKey] = try subVal.toCanonicalJSONData()
                    }
                } else {
                    let fullKey = "app.\(key)"
                    if fullKey == "app.permissionIdentity" { continue }
                    result[fullKey] = try val.toCanonicalJSONData()
                }
            }
        }

        if case .table(let moduleTable) = table["module"] {
            for (modIdStr, modVal) in moduleTable {
                guard ModuleID(rawValue: modIdStr) != nil else { continue }
                if case .table(let modKeys) = modVal {
                    for (k, v) in modKeys {
                        let fullKey = "module.\(modIdStr).\(k)"
                        result[fullKey] = try v.toCanonicalJSONData()
                    }
                }
            }
        }

        return result
    }

    /// Reconstructs a hierarchical TOMLTable from flat SettingsStore keys.
    public static func unflattenFromJSONSettings(_ raw: [String: Data]) -> TOMLTable {
        var root: TOMLTable = [:]
        var ifaceTable: TOMLTable = [:]
        var appTable: TOMLTable = [:]
        var appSubTables: [String: TOMLTable] = [:]
        var moduleTable: [String: TOMLTable] = [:]

        for (fullKey, data) in raw {
            if fullKey == "app.permissionIdentity" { continue }
            guard let tomlVal = TOMLValue.fromJSONData(data) else { continue }

            let parts = fullKey.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2 else {
                root[fullKey] = tomlVal
                continue
            }

            let top = parts[0]
            if top == "interface" {
                let remainder = parts.dropFirst().joined(separator: ".")
                ifaceTable[remainder] = tomlVal
            } else if top == "app" {
                if parts.count == 3 && appSubGroups.contains(parts[1]) {
                    let subGroup = parts[1]
                    let key = parts[2]
                    appSubTables[subGroup, default: [:]][key] = tomlVal
                } else {
                    let remainder = parts.dropFirst().joined(separator: ".")
                    appTable[remainder] = tomlVal
                }
            } else if top == "module" {
                guard parts.count >= 3 else { continue }
                let modId = parts[1]
                let remainder = parts.dropFirst(2).joined(separator: ".")
                moduleTable[modId, default: [:]][remainder] = tomlVal
            } else {
                root[fullKey] = tomlVal
            }
        }

        if !ifaceTable.isEmpty {
            root["interface"] = .table(ifaceTable)
        }

        for (subGroup, subT) in appSubTables {
            appTable[subGroup] = .table(subT)
        }
        if !appTable.isEmpty {
            root["app"] = .table(appTable)
        }

        if !moduleTable.isEmpty {
            var modRoot: TOMLTable = [:]
            for (modId, t) in moduleTable {
                modRoot[modId] = .table(t)
            }
            root["module"] = .table(modRoot)
        }

        return root
    }

    /// Looks up a TOMLValue for a given full setting key (e.g. "interface.openDelayMs").
    public static func findValue(in table: TOMLTable, forSettingKey keyName: String) -> TOMLValue? {
        // Direct root match
        if let direct = table[keyName] { return direct }

        let parts = keyName.split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return nil }

        let top = parts[0]
        if top == "interface", case .table(let iface) = table["interface"] {
            let sub = parts.dropFirst().joined(separator: ".")
            return iface[sub]
        } else if top == "app", case .table(let appT) = table["app"] {
            if parts.count == 3 && appSubGroups.contains(parts[1]) {
                if case .table(let subT) = appT[parts[1]] {
                    return subT[parts[2]]
                }
            }
            let sub = parts.dropFirst().joined(separator: ".")
            return appT[sub]
        } else if top == "module", case .table(let modT) = table["module"] {
            guard parts.count >= 3 else { return nil }
            let modId = parts[1]
            if case .table(let singleMod) = modT[modId] {
                let sub = parts.dropFirst(2).joined(separator: ".")
                return singleMod[sub]
            }
        }

        return nil
    }

    private static func isValidKey(_ key: String) -> Bool {
        if key.hasPrefix("app.") || key.hasPrefix("interface.") { return true }
        if key.hasPrefix("module.") {
            let parts = key.split(separator: ".")
            return parts.count >= 3 && ModuleID(rawValue: String(parts[1])) != nil
        }
        return false
    }
}
