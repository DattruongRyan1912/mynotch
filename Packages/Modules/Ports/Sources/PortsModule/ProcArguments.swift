import Foundation

/// The arguments a process was started with, as `sysctl(KERN_PROCARGS2)` lays them out.
nonisolated enum ProcArguments {
    /// The buffer is `argc` (an Int32), the executable's path and its padding of NULs, `argc` arguments, then the environment.
    /// Only the arguments are read: the environment can hold secrets and is never looked at.
    static func parse(_ buffer: [UInt8]) -> [String] {
        let header = MemoryLayout<Int32>.size
        guard buffer.count > header else { return [] }
        let argc = buffer.prefix(header).withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        var index = header
        while index < buffer.count, buffer[index] != 0 { index += 1 }   // the executable's path
        while index < buffer.count, buffer[index] == 0 { index += 1 }   // its padding
        var arguments: [String] = []
        while arguments.count < argc, index < buffer.count {
            let start = index
            while index < buffer.count, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }

    /// `node /Users/me/app/server.js --port 3000` shown as `node server.js --port 3000`: the program and the first file by name,
    /// so the line is short enough to read in a row. Secrets are masked first (`SecretMask`), so they are not in the line that
    /// the rest of the module keeps, and a long line is cut after that, not through the middle of one.
    static func display(_ arguments: [String], limit: Int = 200) -> String? {
        let arguments = SecretMask.mask(arguments)
        guard var program = arguments.first.map({ URL(fileURLWithPath: $0).lastPathComponent }), !program.isEmpty else { return nil }
        var rest = Array(arguments.dropFirst())
        if let first = rest.first, first.hasPrefix("/") { rest[0] = URL(fileURLWithPath: first).lastPathComponent }
        program = ([program] + rest).joined(separator: " ")
        return program.count > limit ? String(program.prefix(limit)) + "…" : program
    }
}
