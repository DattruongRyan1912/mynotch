import Foundation

/// The AppleScript that picks a tab in Terminal.app or iTerm2. It only selects: it types nothing, runs nothing and closes
/// nothing. The tty goes into the text, so it must be a plain device path.
nonisolated enum TerminalScript {
    static let found = "found"
    static let notFound = "none"

    /// True for `/dev/tty` followed by letters and digits only, such as `/dev/ttys003`.
    static func isDevicePath(_ path: String) -> Bool {
        guard path.hasPrefix("/dev/tty") else { return false }
        let name = path.dropFirst("/dev/tty".count)
        return !name.isEmpty && name.count <= 16 && name.unicodeScalars.allSatisfy { $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0)) }
    }

    /// Nil for an app that has no script, and for a tty that is not a device path.
    static func selectTab(of kind: TerminalTarget.Kind, tty: String) -> String? {
        guard isDevicePath(tty) else { return nil }
        switch kind {
        case .terminal:
            return """
            tell application id "com.apple.Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            if tty of t is "\(tty)" then
                                try
                                    set miniaturized of w to false
                                end try
                                set selected tab of w to t
                                set index of w to 1
                                return "\(found)"
                            end if
                        end try
                    end repeat
                end repeat
            end tell
            return "\(notFound)"
            """
        case .iTerm:
            return """
            tell application id "com.googlecode.iterm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            try
                                if tty of s is "\(tty)" then
                                    select w
                                    select t
                                    select s
                                    return "\(found)"
                                end if
                            end try
                        end repeat
                    end repeat
                end repeat
            end tell
            return "\(notFound)"
            """
        case .editor, .other:
            return nil
        }
    }
}

nonisolated enum AppleScriptResult: Equatable, Sendable {
    /// The script ran; this is what it returned.
    case value(String?)
    /// macOS did not let MyNotch send Apple events to the app (Automation).
    case notPermitted
    case failed
}

nonisolated protocol AppleScriptRunning: Sendable {
    func run(_ source: String) async -> AppleScriptResult
}

/// Runs the script with `NSAppleScript`, one at a time on a queue of its own: asking a terminal about its tabs, or the
/// system asking the user for permission, takes time that the notch must not wait through.
nonisolated struct SystemAppleScriptRunner: AppleScriptRunning {
    private static let queue = DispatchQueue(label: "io.lucasvu.mynotch.aiagents.applescript", qos: .userInitiated)

    func run(_ source: String) async -> AppleScriptResult {
        await withCheckedContinuation { continuation in
            Self.queue.async {
                var error: NSDictionary?
                let output = NSAppleScript(source: source)?.executeAndReturnError(&error)
                continuation.resume(returning: Self.result(errorNumber: error?[NSAppleScript.errorNumber] as? Int, value: output?.stringValue))
            }
        }
    }

    /// -1743 is "not authorized to send Apple events", -1744 "would require user consent".
    static func result(errorNumber: Int?, value: String?) -> AppleScriptResult {
        switch errorNumber {
        case nil: .value(value)
        case -1743, -1744: .notPermitted
        default: .failed
        }
    }
}
