import Foundation

/// What the `mynotch-hook` executable does. It always returns 0 and prints nothing, except the one decision JSON an
/// answered permission request calls for: Claude Code can put a hook's stdout into the model's context, and a failing
/// hook must not disturb the agent.
public enum HookCLI {
    /// Tools whose "permission" is a question for the user, which an allow from the notch would answer with nothing.
    static let toolsThatAskTheUser: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

    /// - Parameters:
    ///   - arguments: the command line without the program name, e.g. `["--source", "claude"]`.
    ///   - permissionTimeout: how long a permission request waits for the user.
    ///   - output: where the decision JSON goes; standard output for the real helper.
    public static func run(
        arguments: [String], stdin: Data, socketPath: String, now: Date,
        permissionTimeout: TimeInterval = PermissionClient.defaultTimeout, output: (Data) -> Void = writeToStandardOutput
    ) -> Int32 {
        guard let flag = arguments.firstIndex(of: "--source"), arguments.indices.contains(flag + 1),
              let payload = HookPayloadFilter.make(source: arguments[flag + 1], hookJSON: stdin, now: now),
              let datagram = payload.encodedDatagram()
        else { return 0 }
        if payload.event == PermissionWire.eventName, let tool = payload.tool, !toolsThatAskTheUser.contains(tool) {
            switch PermissionClient.ask(payload, socketPath: AgentSocket.permissionPath(besides: socketPath), timeout: permissionTimeout) {
            case let .answered(answer):
                if let decision = PermissionWire.hookOutput(for: answer) { output(decision) }
                return 0
            case .noAnswer:
                return 0
            case .unreachable:
                break
            }
        }
        HookDatagramSender.send(datagram, to: socketPath)
        return 0
    }

    /// A closed stdout is ignored: the hook still ends quietly.
    public static func writeToStandardOutput(_ data: Data) {
        var offset = 0
        while offset < data.count {
            let written = data.withUnsafeBytes { write(STDOUT_FILENO, $0.baseAddress! + offset, data.count - offset) }
            if written > 0 {
                offset += written
            } else if written < 0, errno == EINTR {
                continue
            } else {
                return
            }
        }
    }
}
