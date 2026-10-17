import Foundation
@testable import FanHelperKit

/// An in-memory SMC with this Mac's fan keys, as the TH0 probe read them.
struct FanKeysChannel: SMCChannel {
    var entries: [String: (type: String, bytes: [UInt8])]

    static let thisMac: [String: (type: String, bytes: [UInt8])] = [
        "FNum": ("ui8 ", [2]),
        "F0Ac": ("flt ", [0x9d, 0x71, 0xa3, 0x45]), "F0Mn": ("flt ", [0x00, 0x00, 0x96, 0x44]),
        "F0Mx": ("flt ", [0x00, 0x98, 0xb4, 0x45]), "F0Md": ("ui8 ", [0]), "F0Tg": ("flt ", [0x00, 0x98, 0xa3, 0x45]),
        "F1Ac": ("flt ", [0x95, 0xc1, 0xb0, 0x45]), "F1Mn": ("flt ", [0x00, 0x00, 0x96, 0x44]),
        "F1Mx": ("flt ", [0x00, 0x08, 0xc3, 0x45]), "F1Md": ("ui8 ", [0]), "F1Tg": ("flt ", [0x00, 0xa8, 0xb0, 0x45]),
    ]

    init(_ entries: [String: (type: String, bytes: [UInt8])] = Self.thisMac) { self.entries = entries }

    func keyName(at index: Int) -> String? { nil }
    func info(of key: String) -> SMCKeyInfo? { entries[key].map { SMCKeyInfo(size: $0.bytes.count, type: $0.type) } }
    func bytes(of key: String, info: SMCKeyInfo) -> [UInt8]? { entries[key]?.bytes }
}

