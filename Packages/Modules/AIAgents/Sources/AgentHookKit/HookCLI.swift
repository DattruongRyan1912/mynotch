import Foundation

/// What the `mynotch-hook` executable does. It always returns 0 and prints nothing: Claude Code can put a
/// hook's stdout into the model's context, and a failing hook must not disturb the agent.
public enum HookCLI {
    /// - Parameter arguments: the command line without the program name, e.g. `["--source", "claude"]`.
    public static func run(arguments: [String], stdin: Data, socketPath: String, now: Date) -> Int32 {
        guard let flag = arguments.firstIndex(of: "--source"), arguments.indices.contains(flag + 1),
              let payload = HookPayloadFilter.make(source: arguments[flag + 1], hookJSON: stdin, now: now),
              let datagram = payload.encodedDatagram()
        else { return 0 }
        HookDatagramSender.send(datagram, to: socketPath)
        return 0
    }
}
