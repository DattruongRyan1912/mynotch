import Foundation

public typealias TOMLTable = [String: TOMLValue]

/// A strongly typed representation of any valid TOML value.
nonisolated public enum TOMLValue: Equatable, Sendable {
    case string(String)
    case integer(Int64)
    case float(Double)
    case boolean(Bool)
    case array([TOMLValue])
    case table(TOMLTable)

    public static func == (lhs: TOMLValue, rhs: TOMLValue) -> Bool {
        switch (lhs, rhs) {
        case (.string(let l), .string(let r)):
            return l == r
        case (.integer(let l), .integer(let r)):
            return l == r
        case (.float(let l), .float(let r)):
            if l.isNaN && r.isNaN { return true }
            return l == r
        case (.boolean(let l), .boolean(let r)):
            return l == r
        case (.array(let l), .array(let r)):
            return l == r
        case (.table(let l), .table(let r)):
            return l == r
        default:
            return false
        }
    }

    /// Converts the TOMLValue to an untyped Foundation/Swift object representation.
    public func toAny() -> Any {
        switch self {
        case .string(let s):
            return s
        case .integer(let i):
            return Int(i)
        case .float(let f):
            return f
        case .boolean(let b):
            return b
        case .array(let arr):
            return arr.map { $0.toAny() }
        case .table(let tbl):
            return tbl.mapValues { $0.toAny() }
        }
    }

    /// Converts a TOMLTable into a standard `[String: Any]` dictionary.
    public static func toDictionary(_ table: TOMLTable) -> [String: Any] {
        table.mapValues { $0.toAny() }
    }

    /// Encodes this value to canonical UTF-8 JSON data matching SettingsStore output.
    public func toCanonicalJSONData() throws -> Data {
        Data(try canonicalJSONString().utf8)
    }

    private func canonicalJSONString() throws -> String {
        switch self {
        case .string(let s):
            let data = try JSONEncoder().encode(s)
            return String(decoding: data, as: UTF8.self)
        case .integer(let i):
            return "\(i)"
        case .float(let d):
            guard d.isFinite else {
                throw TOMLError(line: 0, column: 0, kind: .nonFiniteFloatInJSON)
            }
            let data = try JSONEncoder().encode(d)
            return String(decoding: data, as: UTF8.self)
        case .boolean(let b):
            return b ? "true" : "false"
        case .array(let arr):
            let elements = try arr.map { try $0.canonicalJSONString() }
            return "[" + elements.joined(separator: ",") + "]"
        case .table(let tbl):
            let pairs = try tbl.keys.sorted().map { k -> String in
                let keyData = try JSONEncoder().encode(k)
                let keyStr = String(decoding: keyData, as: UTF8.self)
                let valStr = try tbl[k]!.canonicalJSONString()
                return "\(keyStr):\(valStr)"
            }
            return "{" + pairs.joined(separator: ",") + "}"
        }
    }

    /// Reconstructs a TOMLValue from JSON data, handling NSNumber boolean/integer/float distinctions.
    public static func fromJSONData(_ data: Data) -> TOMLValue? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        return fromJSONObject(object)
    }

    public static func fromJSONObject(_ object: Any) -> TOMLValue? {
        if let s = object as? String {
            return .string(s)
        } else if let num = object as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                return .boolean(num.boolValue)
            } else if !CFNumberIsFloatType(num) {
                return .integer(num.int64Value)
            } else {
                return .float(num.doubleValue)
            }
        } else if let arr = object as? [Any] {
            var result: [TOMLValue] = []
            for item in arr {
                guard let val = fromJSONObject(item) else { return nil }
                result.append(val)
            }
            return .array(result)
        } else if let dict = object as? [String: Any] {
            var result: TOMLTable = [:]
            for (k, v) in dict {
                guard let val = fromJSONObject(v) else { return nil }
                result[k] = val
            }
            return .table(result)
        }
        return nil
    }
}

extension Dictionary where Key == String, Value == TOMLValue {
    /// Attempts to extract, convert to canonical JSON, and decode a typed setting value.
    public func settingValue<T: Codable & Sendable>(for key: SettingKey<T>) -> T? {
        guard let tomlVal = ConfigKeyMapper.findValue(in: self, forSettingKey: key.name),
              let jsonData = try? tomlVal.toCanonicalJSONData(),
              let decoded = try? JSONDecoder().decode(T.self, from: jsonData) else {
            return nil
        }
        return key.normalize(decoded)
    }
}
