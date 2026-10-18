import Foundation

/// Which cache files the automatic rule deletes. Pure, so the rule is tested without a disk.
nonisolated enum CachePolicy {
    /// First every file older than `maxAge`; then, while what is left is over `maxBytes`, the oldest of it. Files of the same age
    /// go in path order, so the same folder always gives the same answer.
    static func removals(from files: [StorageFile], now: Date, maxAge: TimeInterval, maxBytes: Int64) -> [StorageFile] {
        let cutoff = now.addingTimeInterval(-maxAge)
        let expired = files.filter { $0.modified < cutoff }.sorted(by: isOlder)
        let remaining = files.filter { $0.modified >= cutoff }.sorted(by: isOlder)
        var total = remaining.reduce(0) { $0 + $1.bytes }
        var removals = expired
        for file in remaining where total > maxBytes {
            removals.append(file)
            total -= file.bytes
        }
        return removals
    }

    private static func isOlder(_ lhs: StorageFile, _ rhs: StorageFile) -> Bool {
        lhs.modified != rhs.modified ? lhs.modified < rhs.modified : lhs.url.path(percentEncoded: false) < rhs.url.path(percentEncoded: false)
    }
}
