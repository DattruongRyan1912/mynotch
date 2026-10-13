import os

/// Central `os.Logger` factory. Never log user content.
public enum Log {
    public static let subsystem = "io.lucasvu.mynotch"

    public static func logger(category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
