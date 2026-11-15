import Foundation
import Observation
import os

/// Path resolver for `config.toml` following XDG and standard dotfiles conventions.
nonisolated public enum ConfigPaths {
    public static func resolve(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)
    ) -> URL {
        let standardDefault = homeDirectory
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("mynotch", isDirectory: true)
            .appendingPathComponent("config.toml", isDirectory: false)

        if fileExists(standardDefault.path) {
            return standardDefault
        }

        if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            let expandedXdg = (xdg as NSString).expandingTildeInPath
            let xdgURL = URL(fileURLWithPath: expandedXdg, isDirectory: true)
                .appendingPathComponent("mynotch", isDirectory: true)
                .appendingPathComponent("config.toml", isDirectory: false)

            let dotConfigMyNotchExists = fileExists(homeDirectory.appendingPathComponent(".config", isDirectory: true).appendingPathComponent("mynotch", isDirectory: true).path)
            if fileExists(xdgURL.path) || !dotConfigMyNotchExists {
                return xdgURL
            }
        }

        return standardDefault
    }
}

/// Service managing dotfiles `config.toml` lifecycle, file monitoring, and live settings synchronization.
@Observable
public final class ConfigSyncService {
    @ObservationIgnored private let logger = Log.logger(category: "config")
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let scheduler: any Scheduler
    @ObservationIgnored private let debounceInterval: Duration
    @ObservationIgnored private let onReload: (@MainActor (_ updatedKeys: Set<String>) -> Void)?

    @ObservationIgnored private var watcher: ConfigFileWatcher?
    @ObservationIgnored private var pendingReload: ScheduledAction?
    @ObservationIgnored private var lastProcessedData: Data?

    public let configFileURL: URL

    public var displayPath: String {
        let path = configFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    public private(set) var lastLoadError: String?
    public private(set) var lastLoadedAt: Date?
    public private(set) var appliedKeyCount: Int = 0

    public init(
        settings: SettingsStore,
        configFileURL: URL = ConfigPaths.resolve(),
        scheduler: any Scheduler = TaskScheduler(),
        debounceInterval: Duration = .milliseconds(120),
        onReload: (@MainActor (_ updatedKeys: Set<String>) -> Void)? = nil
    ) {
        self.settings = settings
        self.configFileURL = configFileURL
        self.scheduler = scheduler
        self.debounceInterval = debounceInterval
        self.onReload = onReload
    }

    deinit {
        watcher?.cancel()
    }

    /// Initializes config directory and template if needed, then starts watching.
    public func bootstrap(startWatching: Bool = true) {
        let parentDir = configFileURL.deletingLastPathComponent()
        let fm = FileManager.default

        if !fm.fileExists(atPath: parentDir.path) {
            try? fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        if !fm.fileExists(atPath: configFileURL.path) {
            let starter = ConfigTemplate.starterTemplate()
            let data = Data(starter.utf8)
            lastProcessedData = data
            try? data.write(to: configFileURL, options: .atomic)
        } else {
            _ = reload()
        }

        if startWatching {
            startWatchingFile()
        }
    }

    /// Reads and parses `config.toml`, applying valid settings to `SettingsStore`.
    @discardableResult
    public func reload() -> Bool {
        guard let data = try? Data(contentsOf: configFileURL) else {
            lastLoadError = "Không thể đọc tệp cấu hình"
            return false
        }
        lastProcessedData = data

        guard let content = String(data: data, encoding: .utf8) else {
            lastLoadError = "Tệp cấu hình không phải UTF-8 hợp lệ"
            return false
        }

        do {
            let table = try TOMLParser.parse(content)
            let flattened = try ConfigKeyMapper.flattenToJSONSettings(table)

            var updatedKeys = Set<String>()
            for (key, jsonData) in flattened {
                settings.setRawJSONData(jsonData, forKey: key)
                updatedKeys.insert(key)
            }

            lastLoadError = nil
            lastLoadedAt = Date()
            appliedKeyCount = updatedKeys.count
            onReload?(updatedKeys)
            return true
        } catch let err as TOMLError {
            lastLoadError = err.errorDescription
            logger.error("\(err.logSummary, privacy: .public)")
            return false
        } catch {
            lastLoadError = error.localizedDescription
            logger.error("Lỗi phân tích TOML: lỗi cú pháp không xác định")
            return false
        }
    }

    /// Exports current `SettingsStore` state into the `config.toml` file with documentation comments.
    @discardableResult
    public func exportCurrentSettings() throws -> String {
        let raw = settings.storedRawSettings()
        let content = ConfigTemplate.renderExport(storedRaw: raw)
        let data = Data(content.utf8)

        lastProcessedData = data
        let parentDir = configFileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        try data.write(to: configFileURL, options: .atomic)

        lastLoadError = nil
        lastLoadedAt = Date()
        return content
    }

    public func stopWatching() {
        pendingReload?.cancel()
        pendingReload = nil
        watcher?.cancel()
        watcher = nil
    }

    private func startWatchingFile() {
        watcher?.cancel()
        watcher = ConfigFileWatcher(fileURL: configFileURL) { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleFileChangeDebounced()
            }
        }
    }

    private func handleFileChangeDebounced() {
        pendingReload?.cancel()
        pendingReload = scheduler.schedule(after: debounceInterval) { [weak self] in
            guard let self = self else { return }
            guard let currentData = try? Data(contentsOf: self.configFileURL),
                  currentData != self.lastProcessedData else {
                return
            }
            self.reload()
        }
    }
}
