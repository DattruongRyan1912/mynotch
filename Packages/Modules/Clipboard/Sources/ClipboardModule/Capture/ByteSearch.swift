import Foundation

nonisolated extension StringProtocol {
    /// `contains` for a literal, by bytes. The standard search compares characters, which on 4 KB of code costs
    /// milliseconds where this costs microseconds.
    func containsBytes(_ needle: StaticString) -> Bool {
        var text = String(self)
        return text.withUTF8 { bytes in
            guard let base = bytes.baseAddress else { return false }
            return memmem(base, bytes.count, needle.utf8Start, needle.utf8CodeUnitCount) != nil
        }
    }

    func containsAnyBytes(_ needles: [StaticString]) -> Bool {
        var text = String(self)
        return text.withUTF8 { bytes in
            guard let base = bytes.baseAddress else { return false }
            return needles.contains { memmem(base, bytes.count, $0.utf8Start, $0.utf8CodeUnitCount) != nil }
        }
    }
}
