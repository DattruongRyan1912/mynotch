import AgentHookKit
import Foundation

// Claude Code and Codex run this with the hook's JSON on stdin. It never fails and prints only the decision of an
// answered permission request (see HookCLI); a closed pipe must end it quietly, not with SIGPIPE.
signal(SIGPIPE, SIG_IGN)
exit(HookCLI.run(
    arguments: Array(CommandLine.arguments.dropFirst()),
    stdin: FileHandle.standardInput.readDataToEndOfFile(),
    socketPath: AgentSocket.defaultPath(),
    now: Date()
))
