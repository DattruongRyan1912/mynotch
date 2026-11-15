import Foundation

/// Whether a line is a shell command and not a sentence that starts with a command's name: "git commit -m x" and "git is a
/// version control system" both start with git.
nonisolated enum CodeShellLine {
    /// The subcommands (or targets) that follow a command word. A command with a table is code when its first argument is
    /// one of them, or a flag or a path.
    private static let subcommands: [String: Set<String>] = [
        "git": [
            "add", "commit", "push", "pull", "clone", "status", "checkout", "rebase", "merge", "log", "diff", "init", "branch", "stash",
            "reset", "fetch", "remote", "tag", "switch", "restore", "show", "config", "cherry-pick", "blame", "bisect", "clean",
        ],
        "npm": ["install", "i", "run", "start", "test", "init", "publish", "ci", "build", "update", "uninstall", "exec", "link", "audit"],
        "yarn": ["add", "install", "run", "start", "build", "dev", "remove", "upgrade", "test", "init", "global"],
        "pnpm": ["add", "install", "run", "start", "build", "dev", "remove", "update", "test", "init", "dlx"],
        "docker": [
            "run", "build", "ps", "pull", "push", "exec", "compose", "images", "stop", "rm", "rmi", "logs", "up", "down", "start", "kill",
            "network", "volume", "tag",
        ],
        "kubectl": ["get", "apply", "describe", "delete", "logs", "exec", "config", "create", "rollout", "port-forward", "scale"],
        "brew": ["install", "update", "upgrade", "uninstall", "list", "search", "tap", "services", "cask", "info", "doctor", "cleanup"],
        "pip": ["install", "uninstall", "list", "freeze", "show", "download", "check"],
        "pip3": ["install", "uninstall", "list", "freeze", "show", "download", "check"],
        "cargo": ["build", "run", "test", "add", "install", "new", "check", "fmt", "clippy", "publish", "update", "doc", "bench"],
        "apt": ["install", "update", "upgrade", "remove", "search", "list", "purge", "autoremove"],
        "apt-get": ["install", "update", "upgrade", "remove", "purge", "autoremove", "dist-upgrade"],
        "systemctl": ["start", "stop", "restart", "status", "enable", "disable", "reload", "daemon-reload"],
        "go": ["run", "build", "test", "get", "mod", "fmt", "vet", "install", "version", "generate"],
        "swift": ["build", "test", "run", "package"],
        "make": ["test", "build", "all", "clean", "install", "run", "lint", "deploy", "check"],
        "xcrun": ["swift", "simctl", "xcodebuild", "altool", "notarytool"],
        "xcodebuild": ["build", "test", "clean", "archive"],
    ]
    /// Commands that take a flag, a path, a variable or a quoted text and nothing else.
    private static let plainCommands: Set<String> = [
        "rm", "mv", "cp", "ln", "chmod", "chown", "mkdir", "ssh", "scp", "grep", "sed", "awk", "curl", "wget", "rsync", "cat", "ls",
        "cd", "echo", "open", "find", "kill", "head", "tail", "touch", "ps", "man", "which", "env", "time", "python", "python3",
        "node", "source", "export", "tar", "java", "ruby", "php", "sort", "wc", "diff", "less", "npx",
    ]
    /// Words no command line has between its arguments.
    private static let sentenceWords: Set<String> = [
        "is", "the", "a", "an", "and", "or", "to", "of", "in", "on", "for", "with", "because", "when", "if", "then", "that", "this",
        "it", "are", "was", "be", "my", "me", "your", "you", "we", "they", "he", "she", "at", "by", "from", "as", "but", "not", "so",
        "do", "does", "did", "can", "will", "would", "should", "could", "has", "have", "had", "i", "our", "their", "its", "what", "who",
        "how", "why", "where", "please", "into", "about", "there", "here",
    ]

    /// Every line that starts no other way is asked, so the first word is looked at before anything is worked out.
    private static let commandWords: Set<String> = Set(subcommands.keys).union(plainCommands).union(["sudo"])

    static func isCommand(_ text: String) -> Bool {
        guard commandWords.contains(String(text.prefix { $0 != " " })) else { return false }
        let stripped = CodeLineText.strippingStrings(text)
        // Letters beyond ASCII outside quotes are a sentence's.
        guard !CodeLineText.hasProseLetters(stripped) else { return false }
        var tokens = stripped.split(separator: " ").map(String.init)
        // "sudo", and the flags it takes, are not the command.
        if tokens.first == "sudo" {
            tokens.removeFirst()
            while let flag = tokens.first, isFlag(flag) { tokens.removeFirst() }
        }
        guard tokens.count >= 2, let command = tokens.first else { return false }
        let arguments = tokens.dropFirst()
        let words = arguments.filter { !isFlag($0) && !isPathLike($0) }
        if words.contains(where: { sentenceWords.contains($0.lowercased()) }) { return false }
        guard let first = arguments.first else { return false }
        if let table = subcommands[command] { return table.contains(first) || isFlag(first) || isPathLike(first) }
        return plainCommands.contains(command) && (isFlag(first) || isPathLike(first))
    }

    private static func isFlag(_ token: String) -> Bool {
        guard token.count >= 2, token.first == "-", let second = token.dropFirst().first else { return false }
        return second.isLetter || second == "-"
    }

    /// A path, a file name with an extension, `user@host`, `NAME=value`, a variable or an empty quoted text.
    private static func isPathLike(_ token: String) -> Bool {
        if token == "\"\"" || token == "''" || token == "``" { return true }
        if token.contains("/") || token.contains("@") || token.contains("=") { return token.count > 1 }
        if let first = token.first, "~.$".contains(first) { return true }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" } }
    }
}
