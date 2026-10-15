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
    ///   - trustedUser: whose app is spoken to; the helper's own user. Nothing is sent to a folder or a listener that is
    ///     not that user's, however the agent's hook is set up.
    ///   - parentProcessID: the process that ran the helper, which is the agent; it goes to the app so a click on the session can
    ///     find the terminal it runs in. The init process (1) and anything below it say nothing.
    ///   - output: where the decision JSON goes; standard output for the real helper.
    public static func run(
        arguments: [String], stdin: Data, socketPath: String, now: Date,
        permissionTimeout: TimeInterval = PermissionClient.defaultTimeout, trustedUser: uid_t = geteuid(),
        parentProcessID: pid_t = getppid(), output: (Data) -> Void = writeToStandardOutput
    ) -> Int32 {
        guard let flag = arguments.firstIndex(of: "--source"), arguments.indices.contains(flag + 1),
              var payload = HookPayloadFilter.make(source: arguments[flag + 1], hookJSON: stdin, now: now)
        else { return 0 }
        if parentProcessID > 1 { payload.processID = parentProcessID }
        guard let datagram = payload.encodedDatagram() else { return 0 }
        if payload.event == PermissionWire.eventName, let tool = payload.tool, !toolsThatAskTheUser.contains(tool) {
            let path = AgentSocket.permissionPath(besides: socketPath)
            switch PermissionClient.ask(payload, socketPath: path, timeout: permissionTimeout, trustedUser: trustedUser) {
            case let .answered(answer):
                if let decision = PermissionWire.hookOutput(for: answer) { output(decision) }
                return 0
            case .noAnswer, .untrusted:
                return 0
            case .unreachable:
                break
            }
        }
        // The status goes only to the user's own app: the tool and the folder are not for whoever made the folder first.
        if SocketTrust.inspect(socketPath: socketPath, user: trustedUser) == .trusted { HookDatagramSender.send(datagram, to: socketPath) }
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
