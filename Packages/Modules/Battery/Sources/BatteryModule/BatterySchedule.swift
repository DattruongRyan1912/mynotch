import Foundation

public enum BatteryScheduleAction: Codable, Equatable, Sendable {
    case chargeLimit(Int)
    case forceDischarge(target: Int)
    case sailing(lower: Int, upper: Int)
    case topUp100

    public var title: String {
        switch self {
        case .chargeLimit(let limit):
            return "Khóa sạc \(limit)%"
        case .forceDischarge(let target):
            return "Xả pin về \(target)%"
        case .sailing(let lower, let upper):
            return "Đi thuyền \(lower)% - \(upper)%"
        case .topUp100:
            return "Sạc đầy 100%"
        }
    }
}

public struct BatteryScheduleRule: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var isEnabled: Bool
    public var daysOfWeek: [Int] // 1: Chủ Nhật, 2: Thứ Hai, ..., 7: Thứ Bảy (Calendar standard)
    public var startHour: Int
    public var startMinute: Int
    public var endHour: Int
    public var endMinute: Int
    public var action: BatteryScheduleAction

    public init(
        id: UUID = UUID(),
        title: String,
        isEnabled: Bool = true,
        daysOfWeek: [Int],
        startHour: Int,
        startMinute: Int = 0,
        endHour: Int,
        endMinute: Int = 0,
        action: BatteryScheduleAction
    ) {
        self.id = id
        self.title = title
        self.isEnabled = isEnabled
        self.daysOfWeek = daysOfWeek
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.action = action
    }

    public func matches(date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled, !daysOfWeek.isEmpty else { return false }
        let weekday = calendar.component(.weekday, from: date)

        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let currentMinutes = hour * 60 + minute

        let startMinutes = startHour * 60 + startMinute
        let endMinutes = endHour * 60 + endMinute

        if startMinutes < endMinutes {
            // Cùng trong ngày: ví dụ 08:00 đến 18:00, hoặc 18:00 đến 22:00
            guard daysOfWeek.contains(weekday) else { return false }
            if endHour == 23 && endMinute == 59 {
                return currentMinutes >= startMinutes && currentMinutes <= endMinutes
            } else {
                return currentMinutes >= startMinutes && currentMinutes < endMinutes
            }
        } else {
            // Qua nửa đêm: ví dụ 22:00 đến 06:00
            // Nửa trước nửa đêm (22:00 -> 23:59): tính theo ngày bắt đầu (weekday hiện tại)
            if currentMinutes >= startMinutes {
                return daysOfWeek.contains(weekday)
            }
            // Nửa sau nửa đêm (00:00 -> 05:59): tính theo ngày bắt đầu (ngày hôm trước)
            if currentMinutes < endMinutes {
                let previousWeekday = (weekday == 1) ? 7 : (weekday - 1)
                return daysOfWeek.contains(previousWeekday)
            }
            return false
        }
    }

    public var daysDisplayString: String {
        let sorted = daysOfWeek.sorted()
        if sorted == [2, 3, 4, 5, 6] {
            return "T2 - T6"
        } else if sorted == [1, 7] || sorted == [7, 1] {
            return "Cuối tuần (T7 - CN)"
        } else if sorted == [1, 2, 3, 4, 5, 6, 7] {
            return "Mỗi ngày"
        } else {
            let names = sorted.map { day -> String in
                switch day {
                case 1: return "CN"
                case 2: return "T2"
                case 3: return "T3"
                case 4: return "T4"
                case 5: return "T5"
                case 6: return "T6"
                case 7: return "T7"
                default: return ""
                }
            }
            return names.joined(separator: ", ")
        }
    }

    public var timeRangeString: String {
        String(format: "%02d:%02d - %02d:%02d", startHour, startMinute, endHour, endMinute)
    }
}

public final class BatteryScheduleEngine: @unchecked Sendable {
    public static let rulesKey = "io.lucasvu.mynotch.batteryScheduleRules"
    public static let isEnabledKey = "io.lucasvu.mynotch.batteryScheduleEnabled"

    private let userDefaults: UserDefaults
    private let lock = NSLock()
    private var lastAppliedRuleId: UUID?
    private var lastAppliedAction: BatteryScheduleAction?

    public var isEnabled: Bool {
        didSet {
            userDefaults.set(isEnabled, forKey: Self.isEnabledKey)
        }
    }

    public var rules: [BatteryScheduleRule] {
        didSet {
            saveRules()
        }
    }

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.isEnabled = userDefaults.bool(forKey: Self.isEnabledKey)

        if let data = userDefaults.data(forKey: Self.rulesKey),
           let decoded = try? JSONDecoder().decode([BatteryScheduleRule].self, from: data),
           !decoded.isEmpty {
            self.rules = decoded
        } else {
            self.rules = Self.defaultRules
            if let encoded = try? JSONEncoder().encode(Self.defaultRules) {
                userDefaults.set(encoded, forKey: Self.rulesKey)
            }
        }
    }

    public static var defaultRules: [BatteryScheduleRule] {
        [
            BatteryScheduleRule(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID(),
                title: "Giờ làm việc văn phòng",
                isEnabled: true,
                daysOfWeek: [2, 3, 4, 5, 6],
                startHour: 8,
                startMinute: 0,
                endHour: 18,
                endMinute: 0,
                action: .chargeLimit(80)
            ),
            BatteryScheduleRule(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID(),
                title: "Buổi tối xả pin tự nhiên",
                isEnabled: true,
                daysOfWeek: [2, 3, 4, 5, 6],
                startHour: 18,
                startMinute: 0,
                endHour: 22,
                endMinute: 0,
                action: .forceDischarge(target: 60)
            ),
            BatteryScheduleRule(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333") ?? UUID(),
                title: "Cuối tuần đi thuyền an toàn",
                isEnabled: true,
                daysOfWeek: [1, 7],
                startHour: 0,
                startMinute: 0,
                endHour: 23,
                endMinute: 59,
                action: .sailing(lower: 70, upper: 80)
            )
        ]
    }

    public func saveRules() {
        if let encoded = try? JSONEncoder().encode(rules) {
            userDefaults.set(encoded, forKey: Self.rulesKey)
        }
    }

    public func activeRule(at date: Date = Date(), calendar: Calendar = .current) -> BatteryScheduleRule? {
        guard isEnabled else { return nil }
        lock.lock()
        defer { lock.unlock() }
        for rule in rules where rule.isEnabled {
            if rule.matches(date: date, calendar: calendar) {
                return rule
            }
        }
        return nil
    }

    @discardableResult
    public func applyActiveRule(
        at date: Date = Date(),
        to module: BatteryModule,
        calendar: Calendar = .current,
        force: Bool = false
    ) -> BatteryScheduleRule? {
        guard let rule = activeRule(at: date, calendar: calendar) else {
            return nil
        }

        lock.lock()
        let shouldApply = force || (lastAppliedRuleId != rule.id) || (lastAppliedAction != rule.action)
        if shouldApply {
            lastAppliedRuleId = rule.id
            lastAppliedAction = rule.action
        }
        lock.unlock()

        if shouldApply {
            apply(action: rule.action, to: module)
        }
        return rule
    }

    public func apply(action: BatteryScheduleAction, to module: BatteryModule) {
        switch action {
        case .chargeLimit(let limit):
            module.setChargeLimit(limit)
            module.setAllowDischarge(false)
        case .forceDischarge(let target):
            module.setChargeLimit(target)
            module.setAllowDischarge(true)
        case .sailing(let lower, let upper):
            module.setChargeLimit(upper)
            let delta = max(2, min(20, upper - lower))
            module.setSailing(enabled: true, delta: delta)
        case .topUp100:
            if !module.studioStatus().isTopUpActive {
                module.toggleTopUpOnce()
            }
        }
    }

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    public func toggleRule(id: UUID) {
        if let idx = rules.firstIndex(where: { $0.id == id }) {
            rules[idx].isEnabled.toggle()
            saveRules()
        }
    }

    public func addRule(_ rule: BatteryScheduleRule) {
        rules.append(rule)
        saveRules()
    }

    public func updateRule(_ rule: BatteryScheduleRule) {
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[idx] = rule
            saveRules()
        }
    }

    public func deleteRule(id: UUID) {
        rules.removeAll(where: { $0.id == id })
        saveRules()
        lock.lock()
        if lastAppliedRuleId == id {
            lastAppliedRuleId = nil
            lastAppliedAction = nil
        }
        lock.unlock()
    }

    public func resetToDefaults() {
        rules = Self.defaultRules
        saveRules()
    }
}
