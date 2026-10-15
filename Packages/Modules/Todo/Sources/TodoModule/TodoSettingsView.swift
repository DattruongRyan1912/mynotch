import AppKit
import MyNotchCore
import SwiftUI

/// Plain rows: the Settings page provides the Form and the section. They work whether or not the module runs.
struct TodoSettingsView: View {
    let settings: ModuleSettings
    let keys: TodoSettingsKeys
    let permissions: any PermissionCenter
    let loadLists: () async -> [TodoListInfo]
    /// Called after the Reminders prompt is answered, so a running module reads the reminders at once.
    let accessAnswered: () -> Void

    @State private var lists: [TodoListInfo]?
    /// Bumped when access may have changed (after the prompt, or on coming back from System Settings), so the rows that
    /// depend on it are checked and the lists read again.
    @State private var accessRevision = 0

    var body: some View {
        Group {
            if permissions.status(of: .reminders) != .granted {
                LabeledContent {
                    Button("Cho phép…") { Task { await requestAccess() } }
                } label: {
                    Text("Chưa có quyền truy cập Lời nhắc")
                    Text("Việc cần làm chỉ hiện sau khi bạn cho phép.")
                }
                .id(accessRevision)
            }
            Toggle(isOn: settings.binding(keys.includeUndated)) {
                Text("Cả việc không có ngày")
                Text("Hiện cả việc chưa đặt ngày trong danh sách mặc định.")
            }
            defaultListRow
            Toggle(isOn: settings.binding(keys.showRemaining)) {
                Text("Hiện số việc còn lại")
                Text("Trên notch khi đang đóng, ví dụ “Còn 3 việc”.")
            }
            listRows
        }
        .task(id: accessRevision) { lists = await loadLists() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessRevision += 1
        }
    }

    private func requestAccess() async {
        await RemindersAccess(permissions: permissions).request(openSettingsIfDenied: true)
        accessRevision += 1
        accessAnswered()
    }

    // MARK: Default list

    /// Where a quick-added reminder goes, and where undated ones are read from. Only lists that take reminders are offered;
    /// the first choice is the one the system uses, which also covers a list that has since been deleted.
    @ViewBuilder
    private var defaultListRow: some View {
        let writable = TodoListChoice.sorted((lists ?? []).filter(\.allowsModifications))
        Picker(selection: defaultList(among: writable)) {
            Text("Danh sách mặc định của hệ thống").tag("")
            ForEach(writable) { list in
                Text(list.title).tag(list.id)
            }
        } label: {
            Text("Danh sách cho việc mới")
            Text("Nơi lưu việc thêm từ tab, và nơi lấy việc không có ngày.")
        }
        .disabled(permissions.status(of: .reminders) != .granted)
    }

    private func defaultList(among writable: [TodoListInfo]) -> Binding<String> {
        Binding(
            get: {
                let chosen = settings.value(keys.defaultListID)
                return writable.contains { $0.id == chosen } ? chosen : ""
            },
            set: { settings.set($0, for: keys.defaultListID) }
        )
    }

    // MARK: Lists

    @ViewBuilder
    private var listRows: some View {
        LabeledContent {
            EmptyView()
        } label: {
            Text("Danh sách hiển thị")
            Text("Bỏ chọn danh sách để ẩn việc của nó khỏi tab. Mặc định là tất cả.")
        }
        if permissions.status(of: .reminders) != .granted {
            Text("Cần quyền truy cập Lời nhắc để chọn danh sách.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let lists {
            if lists.isEmpty {
                Text("Không tìm thấy danh sách nào.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(TodoListChoice.sorted(lists)) { list in
                Toggle(isOn: visibility(of: list)) {
                    HStack(spacing: 6) {
                        Circle().fill(Color(list.color)).frame(width: 8, height: 8)
                        Text(list.title)
                    }
                }
            }
        } else {
            Text("Đang tải…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func visibility(of list: TodoListInfo) -> Binding<Bool> {
        Binding(
            get: { TodoListChoice.isVisible(list.id, hidden: settings.value(keys.hiddenListIDs)) },
            set: { isVisible in
                settings.set(
                    TodoListChoice.setting(list.id, visible: isVisible, in: settings.value(keys.hiddenListIDs)),
                    for: keys.hiddenListIDs
                )
            }
        )
    }
}
