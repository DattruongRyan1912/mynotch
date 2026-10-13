import AgentHookKit
import Foundation

// Claude Code and Codex run this with the hook's JSON on stdin; it never prints or fails (see HookCLI).
exit(HookCLI.run(
    arguments: Array(CommandLine.arguments.dropFirst()),
    stdin: FileHandle.standardInput.readDataToEndOfFile(),
    socketPath: AgentSocket.defaultPath(),
    now: Date()
))
