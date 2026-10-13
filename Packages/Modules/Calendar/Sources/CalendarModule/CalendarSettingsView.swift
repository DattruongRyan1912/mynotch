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
    /// Bumped after the prompt, so the "no access" note is checked again.
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
            calendarRows
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
                .task { calendars = await loadCalendars() }
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
