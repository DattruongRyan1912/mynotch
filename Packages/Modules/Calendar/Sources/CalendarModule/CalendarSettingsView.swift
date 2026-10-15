import AppKit
import MyNotchCore
import SwiftUI

/// Plain rows: the Settings page provides the Form and the section. They work whether or not the module runs.
struct CalendarSettingsView: View {
    let settings: ModuleSettings
    let keys: CalendarSettingsKeys
    let permissions: any PermissionCenter
    let loadCalendars: () async -> [CalendarInfo]
    /// Called after the Reminders prompt is answered, so a running module reads the reminders at once.
    let remindersAccessAnswered: () -> Void

    @State private var calendars: [CalendarInfo]?
    /// Bumped when access may have changed (after the prompt, or on coming back from System Settings), so the
    /// rows that depend on it are checked and the calendars read again.
    @State private var accessRevision = 0

    var body: some View {
        Group {
            Toggle("Hiện lời nhắc đến hạn hôm nay", isOn: showReminders)
            if settings.value(keys.showReminders), permissions.status(of: .reminders) != .granted {
                LabeledContent {
                    Button("Cho phép…") { Task { await requestRemindersAccess(openSettingsIfDenied: true) } }
                } label: {
                    Text("Chưa có quyền truy cập Lời nhắc")
                    Text("Lời nhắc chỉ hiện sau khi bạn cho phép.")
                }
                .id(accessRevision)
            }
            Stepper(
                "Báo họp trước \(settings.value(keys.meetingLeadMinutes)) phút",
                value: settings.binding(keys.meetingLeadMinutes), in: CalendarSettingsKeys.meetingLeadRange
            )
            Toggle("Hiện sự kiện cả ngày", isOn: settings.binding(keys.showAllDay))
            daySummaryRows
            newEventCalendarRow
            calendarRows
        }
        .task(id: accessRevision) { calendars = await loadCalendars() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessRevision += 1
        }
    }

    /// Turning it on asks for access; turning it off asks for nothing.
    private var showReminders: Binding<Bool> {
        Binding(
            get: { settings.value(keys.showReminders) },
            set: { isOn in
                settings.set(isOn, for: keys.showReminders)
                if isOn { Task { await requestRemindersAccess(openSettingsIfDenied: false) } }
            }
        )
    }

    private func requestRemindersAccess(openSettingsIfDenied: Bool) async {
        await RemindersAccess(permissions: permissions).request(openSettingsIfDenied: openSettingsIfDenied)
        accessRevision += 1
        remindersAccessAnswered()
    }

    // MARK: Day summary

    @ViewBuilder
    private var daySummaryRows: some View {
        Toggle(isOn: settings.binding(keys.showDaySummary)) {
            Text("Hiện tóm tắt trong ngày")
            Text("Một dòng ở đầu tab Lịch: số sự kiện, khoảng rảnh và giờ kết thúc.")
        }
        Stepper(
            "Bắt đầu làm việc lúc \(Self.clock(workStart))",
            value: settings.binding(keys.workStartHour), in: 0...(workEnd - 1)
        )
        Stepper(
            "Kết thúc làm việc lúc \(Self.clock(workEnd))",
            value: settings.binding(keys.workEndHour), in: (workStart + 1)...24
        )
    }

    private var workStart: Int { settings.value(keys.workStartHour) }
    private var workEnd: Int { settings.value(keys.workEndHour) }

    static func clock(_ hour: Int) -> String { String(format: "%02d:00", hour) }

    // MARK: New events

    /// Where an event added with "+" goes. Only calendars that take events are offered; the first choice is the one
    /// the system uses, which also covers a calendar that has since been deleted.
    @ViewBuilder
    private var newEventCalendarRow: some View {
        let writable = HiddenCalendars.sorted((calendars ?? []).filter(\.allowsModifications))
        Picker(selection: newEventCalendar(among: writable)) {
            Text("Lịch mặc định của hệ thống").tag("")
            ForEach(writable) { calendar in
                Text(calendar.title).tag(calendar.id)
            }
        } label: {
            Text("Lịch cho sự kiện mới")
            Text("Nơi lưu sự kiện thêm bằng dấu + trong tab Lịch.")
        }
        .disabled(permissions.status(of: .calendars) != .granted)
    }

    private func newEventCalendar(among writable: [CalendarInfo]) -> Binding<String> {
        Binding(
            get: {
                let chosen = settings.value(keys.defaultCalendarID)
                return writable.contains { $0.id == chosen } ? chosen : ""
            },
            set: { settings.set($0, for: keys.defaultCalendarID) }
        )
    }

    // MARK: Calendars

    @ViewBuilder
    private var calendarRows: some View {
        LabeledContent {
            EmptyView()
        } label: {
            Text("Lịch hiển thị")
            Text("Bỏ chọn lịch để ẩn sự kiện của nó khỏi tab và thông báo họp.")
        }
        if permissions.status(of: .calendars) != .granted {
            Text("Cần quyền truy cập Lịch để chọn lịch cần ẩn.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let calendars {
            if calendars.isEmpty {
                Text("Không tìm thấy lịch nào.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(HiddenCalendars.sorted(calendars)) { calendar in
                Toggle(isOn: visibility(of: calendar)) {
                    HStack(spacing: 6) {
                        Circle().fill(Color(calendar.color)).frame(width: 8, height: 8)
                        Text(calendar.title)
                    }
                }
            }
        } else {
            Text("Đang tải…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func visibility(of calendar: CalendarInfo) -> Binding<Bool> {
        Binding(
            get: { HiddenCalendars.isVisible(calendar.id, hidden: settings.value(keys.hiddenCalendarIDs)) },
            set: { isVisible in
                settings.set(
                    HiddenCalendars.setting(calendar.id, visible: isVisible, in: settings.value(keys.hiddenCalendarIDs)),
                    for: keys.hiddenCalendarIDs
                )
            }
        )
    }
}
