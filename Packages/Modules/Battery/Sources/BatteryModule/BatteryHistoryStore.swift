import Foundation
import Observation

nonisolated public enum BatteryPowerMode: String, Codable, Sendable {
    case charging
    case acPassthrough
    case discharging

    public var title: String {
        switch self {
        case .charging: return "Đang sạc"
        case .acPassthrough: return "Nguồn AC (Bypass)"
        case .discharging: return "Dùng pin"
        }
    }
}

nonisolated public enum BatteryHistoryRange: String, CaseIterable, Identifiable, Sendable {
    case last24Hours
    case last7Days

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .last24Hours: return "24 Giờ"
        case .last7Days: return "7 Ngày"
        }
    }

    public var duration: TimeInterval {
        switch self {
        case .last24Hours: return 86_400
        case .last7Days: return 7 * 86_400
        }
    }
}

nonisolated public struct BatteryHistoryPoint: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var percent: Int
    public var mode: BatteryPowerMode
    public var watts: Double

    public init(id: UUID = UUID(), timestamp: Date, percent: Int, mode: BatteryPowerMode, watts: Double = 0.0) {
        self.id = id
        self.timestamp = timestamp
        self.percent = min(100, max(0, percent))
        self.mode = mode
        self.watts = watts
    }
}

nonisolated public struct BatteryHistorySummary: Equatable, Sendable {
    public var minPercent: Int
    public var maxPercent: Int
    public var averagePercent: Int
    public var peakWatts: Double
    public var sampleCount: Int
    public var dischargingMinutes: Int

    public init(
        minPercent: Int = 0,
        maxPercent: Int = 0,
        averagePercent: Int = 0,
        peakWatts: Double = 0.0,
        sampleCount: Int = 0,
        dischargingMinutes: Int = 0
    ) {
        self.minPercent = minPercent
        self.maxPercent = maxPercent
        self.averagePercent = averagePercent
        self.peakWatts = peakWatts
        self.sampleCount = sampleCount
        self.dischargingMinutes = dischargingMinutes
    }
}

@Observable
@MainActor
public final class BatteryHistoryStore {
    nonisolated public static let storageKey = "battery.history.points.v1"
    nonisolated public static let maxHistoryAge: TimeInterval = 7 * 86_400
    nonisolated public static let deduplicationWindow: TimeInterval = 300 // 5 minutes

    private let userDefaults: UserDefaults
    public private(set) var points: [BatteryHistoryPoint] = []
    private var hasSeededPmset = false

    public init(userDefaults: UserDefaults = .standard, enablePmsetSeed: Bool = true) {
        self.userDefaults = userDefaults
        loadPersistedPoints()
        if enablePmsetSeed {
            seedFromPmsetIfNeeded()
        }
    }

    public func record(percent: Int, mode: BatteryPowerMode, watts: Double, timestamp: Date = Date()) {
        let clampedPercent = min(100, max(0, percent))

        // Coalescing: if within 5 minutes, monotonically forward in time, same mode and same percent, update latest point rather than duplicate
        if let last = points.last,
           timestamp >= last.timestamp,
           timestamp.timeIntervalSince(last.timestamp) < Self.deduplicationWindow,
           last.percent == clampedPercent,
           last.mode == mode {
            points[points.count - 1].watts = watts
            points[points.count - 1].timestamp = timestamp
            persistPoints()
            return
        }

        let newPoint = BatteryHistoryPoint(timestamp: timestamp, percent: clampedPercent, mode: mode, watts: watts)
        points.append(newPoint)
        points.sort { $0.timestamp < $1.timestamp }
        pruneAndPersist(now: timestamp)
    }

    public func points(for range: BatteryHistoryRange, now: Date = Date()) -> [BatteryHistoryPoint] {
        let cutoff = now.addingTimeInterval(-range.duration)
        return points.filter { $0.timestamp >= cutoff }
    }

    public func summary(for range: BatteryHistoryRange, now: Date = Date()) -> BatteryHistorySummary {
        let subset = points(for: range, now: now)
        guard !subset.isEmpty else {
            return BatteryHistorySummary()
        }
        let percents = subset.map(\.percent)
        let minP = percents.min() ?? 0
        let maxP = percents.max() ?? 0
        let avgP = Int(round(Double(percents.reduce(0, +)) / Double(percents.count)))
        let maxW = subset.map { abs($0.watts) }.max() ?? 0.0

        // Estimate discharging minutes: time interval where mode == .discharging
        var dischargingSeconds: TimeInterval = 0
        if subset.count > 1 {
            for i in 0..<(subset.count - 1) {
                if subset[i].mode == .discharging {
                    let delta = min(3600, subset[i + 1].timestamp.timeIntervalSince(subset[i].timestamp))
                    if delta > 0 { dischargingSeconds += delta }
                }
            }
        }
        return BatteryHistorySummary(
            minPercent: minP,
            maxPercent: maxP,
            averagePercent: avgP,
            peakWatts: maxW,
            sampleCount: subset.count,
            dischargingMinutes: Int(dischargingSeconds / 60)
        )
    }

    public func seedFromPmsetIfNeeded() {
        guard !hasSeededPmset else { return }
        hasSeededPmset = true

        Task.detached(priority: .utility) { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", "/usr/bin/pmset -g log | /usr/bin/tail -n 300"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if let output = String(data: data, encoding: .utf8) {
                    let parsed = Self.parsePmsetLog(output)
                    await MainActor.run { [weak self] in
                        self?.mergeParsedPoints(parsed)
                    }
                }
            } catch {
                // pmset failed, ignore gracefully
            }
        }
    }

    public func mergeParsedPoints(_ newPoints: [BatteryHistoryPoint]) {
        guard !newPoints.isEmpty else { return }
        var combined = points
        for point in newPoints {
            // Avoid inserting duplicates if timestamp is already close to an existing point
            if !combined.contains(where: { abs($0.timestamp.timeIntervalSince(point.timestamp)) < 120 }) {
                combined.append(point)
            }
        }
        combined.sort { $0.timestamp < $1.timestamp }
        points = combined
        pruneAndPersist()
    }

    nonisolated public static func parsePmsetLog(_ log: String, now: Date = Date(), maxAge: TimeInterval = maxHistoryAge) -> [BatteryHistoryPoint] {
        guard !log.isEmpty else { return [] }
        let cutoff = now.addingTimeInterval(-maxAge)
        var result: [BatteryHistoryPoint] = []

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"

        let lines = log.components(separatedBy: .newlines)
        var previousPercent: Int? = nil

        for line in lines {
            // Must have timestamp (at least 25 characters)
            guard line.count >= 25 else { continue }
            let dateStr = String(line.prefix(25))
            guard let timestamp = formatter.date(from: dateStr), timestamp >= cutoff, timestamp <= now.addingTimeInterval(3600) else {
                continue
            }

            // Look for Using AC or Using Batt
            let isBatt = line.localizedCaseInsensitiveContains("Using Batt") || line.localizedCaseInsensitiveContains("Using BATT")
            let isAC = line.localizedCaseInsensitiveContains("Using AC")
            guard isBatt || isAC else { continue }

            // Extract Charge: (\d+)%?
            guard let chargeRange = line.range(of: "Charge:", options: .caseInsensitive) else { continue }
            let remainder = line[chargeRange.upperBound...].trimmingCharacters(in: .whitespaces)
            var numStr = ""
            for ch in remainder {
                if ch.isNumber {
                    numStr.append(ch)
                } else if ch == "%" || ch == ")" || ch == " " {
                    break
                } else {
                    break
                }
            }
            guard let percent = Int(numStr), percent >= 0, percent <= 100 else { continue }

            let mode: BatteryPowerMode
            if isBatt {
                mode = .discharging
            } else {
                if let prev = previousPercent, percent > prev {
                    mode = .charging
                } else {
                    mode = .acPassthrough
                }
            }
            previousPercent = percent

            result.append(BatteryHistoryPoint(timestamp: timestamp, percent: percent, mode: mode))
        }

        result.sort { $0.timestamp < $1.timestamp }
        return result
    }

    private func pruneAndPersist(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Self.maxHistoryAge)
        points.removeAll { $0.timestamp < cutoff }
        persistPoints()
    }

    private func persistPoints() {
        do {
            let data = try JSONEncoder().encode(points)
            userDefaults.set(data, forKey: Self.storageKey)
        } catch {
            // Ignore encoding errors
        }
    }

    private func loadPersistedPoints() {
        guard let data = userDefaults.data(forKey: Self.storageKey) else { return }
        do {
            let loaded = try JSONDecoder().decode([BatteryHistoryPoint].self, from: data)
            let cutoff = Date().addingTimeInterval(-Self.maxHistoryAge)
            points = loaded.filter { $0.timestamp >= cutoff }.sorted { $0.timestamp < $1.timestamp }
        } catch {
            points = []
        }
    }
}
