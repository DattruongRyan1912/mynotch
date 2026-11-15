import AppKit
import MyNotchCore
import NotchUI
import SwiftUI
import os

/// Phân hệ theo dõi thói quen hàng ngày trên Notch macOS.
public final class HabitModule: FeatureModule {
    nonisolated public static let activityID = "remaining"

    public let descriptor = ModuleDescriptor(
        id: "habit",
        displayName: "Thói quen",
        systemImage: "arrow.triangle.2.circlepath",
        defaultEnabled: true,
        order: 660
    )

    public let state: HabitState
    private let now: () -> Date
    private let calendar: Calendar
    private let dayChangeCenter: NotificationCenter
    private let wakeCenter: NotificationCenter

    private var context: ModuleContext?
    private var fileURL: URL?
    private var dayChangeObserver: (any NSObjectProtocol)?
    private var wakeObserver: (any NSObjectProtocol)?

    public init(
        now: @escaping () -> Date = { .now },
        calendar: Calendar = .autoupdatingCurrent,
        dayChangeCenter: NotificationCenter = .default,
        wakeCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.now = now
        self.calendar = calendar
        self.dayChangeCenter = dayChangeCenter
        self.wakeCenter = wakeCenter
        self.state = HabitState(
            today: DayKey(date: now(), calendar: calendar),
            calendar: calendar
        )
    }

    public func start(_ context: ModuleContext) async throws(ModuleError) {
        do {
            try context.storage.ensureDirectories()
        } catch {
            throw .failed(reason: "Không tạo được thư mục lưu trữ thói quen")
        }

        let url = context.storage.directory.appending(path: "habits.json")
        self.fileURL = url
        self.context = context

        // Đọc dữ liệu từ file habits.json
        let loaded = Self.load(from: url, logger: context.logger)
        state.habits = loaded
        state.calendar = calendar
        state.updateToday(date: now())

        // Đăng ký nhận thông báo chuyển ngày để reset tiến độ hôm nay
        dayChangeObserver = dayChangeCenter.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleDayChanged()
            }
        }

        // Đăng ký nhận thông báo máy tính thức dậy từ Sleep
        wakeObserver = wakeCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleDayChanged()
            }
        }

        // Lắng nghe thay đổi settings để cập nhật Live Activity tức thì
        let moduleSettings = context.settings
        context.run { [weak self] in
            for await _ in Observations({ HabitSettings(moduleSettings) }) {
                self?.publishActivity()
            }
        }

        publishActivity()
    }

    public func stop() async {
        save()
        if let dayChangeObserver {
            dayChangeCenter.removeObserver(dayChangeObserver)
            self.dayChangeObserver = nil
        }
        if let wakeObserver {
            wakeCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        context?.activities.clear(id: Self.activityID)
        self.context = nil
    }

    public func makeTab() -> NotchTab? {
        NotchTab(
            id: descriptor.id,
            title: descriptor.displayName,
            systemImage: descriptor.systemImage,
            preferredHeight: HabitTabView.height,
            acceptsKeyboard: true,
            content: AnyView(
                HabitTabView(
                    state: state,
                    onSave: { [weak self] in self?.save() },
                    onAppear: { [weak self] in self?.handleDayChanged() }
                )
            )
        )
    }

    public func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? {
        AnyView(HabitSettingsView(settings: environment.settings))
    }

    // MARK: - Persistence & Activity

    public func save() {
        guard let fileURL else { return }
        let storeData = HabitStoreData(habits: state.habits)
        do {
            let data = try JSONEncoder().encode(storeData)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            context?.logger.error("Không ghi được habits.json: \(error.localizedDescription)")
        }
        publishActivity()
    }

    public static func load(from url: URL, logger: Logger? = nil) -> [Habit] {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            let storeData = try JSONDecoder().decode(HabitStoreData.self, from: data)
            return storeData.habits
        } catch {
            logger?.error("Không đọc được habits.json, bắt đầu với danh sách rỗng: \(error.localizedDescription)")
            return []
        }
    }

    private func handleDayChanged() {
        state.updateToday(date: now())
        publishActivity()
    }

    public func publishActivity() {
        guard let context else { return }
        let keys = HabitSettingsKeys(context.settings)
        let showRemaining = context.settings.value(keys.showRemaining)

        let progress = state.progress
        if showRemaining && progress.remaining > 0 {
            let content = HabitActivityContent(
                remaining: progress.remaining,
                done: progress.done,
                total: progress.total
            )
            context.activities.set(content.liveActivity)
        } else {
            context.activities.clear(id: Self.activityID)
        }
    }
}
