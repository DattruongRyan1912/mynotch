/// Four-character SMC key names ("F0Ac") and the 32-bit codes the SMC takes them as.
nonisolated enum SMCKey {
    static func code(_ name: String) -> UInt32? {
        let bytes = Array(name.utf8)
        guard bytes.count == 4 else { return nil }
        return bytes.reduce(0) { $0 << 8 | UInt32($1) }
    }

    static func name(_ code: UInt32) -> String {
        String(decoding: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }, as: UTF8.self)
    }
}

/// What the SMC hands back as bytes, as a number. Only the types this Mac returns for the keys the module reads: floats
/// (little-endian, unlike everything else the SMC does) and unsigned integers (big-endian). Anything else is not a number
/// here, so a key of another type is skipped instead of being misread.
nonisolated enum SMCValue {
    static func number(type: String, bytes: [UInt8]) -> Double? {
        switch (type, bytes.count) {
        case ("flt ", 4):
            let bits = UInt32(bytes[3]) << 24 | UInt32(bytes[2]) << 16 | UInt32(bytes[1]) << 8 | UInt32(bytes[0])
            let value = Double(Float(bitPattern: bits))
            return value.isFinite ? value : nil
        case ("ui8 ", 1), ("ui16", 2), ("ui32", 4):
            return Double(bytes.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        default:
            return nil
        }
    }
}
