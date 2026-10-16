import AppKit
import MyNotchCore
import SwiftUI
import UniformTypeIdentifiers

/// Where the storage usage row reads from.
enum ClipboardUsageSource {
    /// The running module's history, observed so the row follows new copies.
    case live(ClipboardState)
    /// The files of a stopped module.
    case disk(URL)
}

/// Plain rows: the Settings page provides the Form and the section. They work whether or not the module runs.
struct ClipboardSettingsView: View {
    private static let pasteboardSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard")!

    let settings: ModuleSettings
    let keys: ClipboardSettingKeys
    let usage: ClipboardUsageSource
    let clear: (ClipboardClearRange) async -> Void
    let pasteboardAccessBehavior: () -> NSPasteboard.AccessBehavior
    /// Whether the module runs, which backup and restore need.
    let canBackUp: Bool
    let mcp: ClipboardMCPActions

    @State private var diskUsage: ClipboardStorageUsage?
    /// Bumped after clearing, so the disk usage is read again.
    @State private var usageRevision = 0
    @State private var pendingClear: ClipboardClearRange?
    /// Kept by the view, not by whoever builds it, so a backup under way outlives a rebuild of the page.
    @State private var backup: ClipboardBackupModel

    init(
        settings: ModuleSettings, keys: ClipboardSettingKeys, usage: ClipboardUsageSource, clear: @escaping (ClipboardClearRange) async -> Void,
        pasteboardAccessBehavior: @escaping () -> NSPasteboard.AccessBehavior, canBackUp: Bool, mcp: ClipboardMCPActions,
        backupActions: ClipboardBackupActions
    ) {
        self.settings = settings
        self.keys = keys
        self.usage = usage
        self.clear = clear
        self.pasteboardAccessBehavior = pasteboardAccessBehavior
        self.canBackUp = canBackUp
        self.mcp = mcp
        _backup = State(initialValue: ClipboardBackupModel(actions: backupActions))
    }

    var body: some View {
        Group {
            Toggle("Tạm dừng ghi lịch sử", isOn: settings.binding(keys.paused))
            Stepper(
                "Giữ tối đa \(settings.value(keys.historyLimit)) mục",
                value: settings.binding(keys.historyLimit), in: ClipboardSettingKeys.historyLimitRange, step: 50
            )
            Picker("Thời gian giữ", selection: settings.binding(keys.retention)) {
                ForEach(Retention.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Stepper(
                "Dung lượng ảnh tối đa \(settings.value(keys.imageStorageLimitMB)) MB",
                value: settings.binding(keys.imageStorageLimitMB), in: ClipboardSettingKeys.imageStorageLimitMBRange, step: 50
            )
            Toggle("Bỏ qua dữ liệu nhạy cảm (mật khẩu, mã tạm thời)", isOn: settings.binding(keys.ignoreSensitive))
            Toggle("Nhận mã màu không có dấu #", isOn: settings.binding(keys.colorsWithoutHash))
            Picker("Khi bấm vào mục", selection: settings.binding(keys.clickAction)) {
                ForEach(ClickAction.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if settings.value(keys.clickAction) == .paste {
                Text("Dán trực tiếp cần quyền Accessibility; khi chưa có quyền, mục chỉ được chép.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle("Đóng notch sau khi chép hoặc dán", isOn: settings.binding(keys.closeAfterAction))
            Toggle("Hiện thông báo khi chép", isOn: settings.binding(keys.showCopiedActivity))
            soundsAndPreviews
            copyStack
            boardLocks
            excludedApps
            storage
            ClipboardBackupRows(backup: backup, isAvailable: canBackUp)
            ClipboardMCPRows(isOn: settings.binding(keys.mcpEnabled), actions: mcp, isRunning: canBackUp)
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                pasteboardAccess(pasteboardAccessBehavior())
            }
        }
    }

    // MARK: Sounds and link previews

    static let soundsNote = "Phát một tiếng nhẹ khi MyNotch ghi lại một mục mới và khi MyNotch dán một mục. Mục nhạy cảm, mục trông giống mật khẩu và mục trong board đã khoá không phát tiếng."
    static let linkPreviewsNote = "Khi bật, MyNotch sẽ mở trang của link để đọc tiêu đề và ảnh xem trước; trang đó thấy địa chỉ IP của bạn. Chỉ link công khai: địa chỉ nội bộ, link có mật khẩu, mục nhạy cảm và board đã khoá không bao giờ được mở."

    @ViewBuilder
    private var soundsAndPreviews: some View {
        Toggle("Âm thanh khi chép và dán", isOn: settings.binding(keys.playSounds))
        Text(Self.soundsNote)
            .font(.caption)
            .foregroundStyle(.secondary)
        Toggle("Xem trước link (cần mạng)", isOn: settings.binding(keys.linkPreviews))
        Text(Self.linkPreviewsNote)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: Copy stack

    @ViewBuilder
    private var copyStack: some View {
        Picker("Thứ tự dán của ngăn xếp", selection: settings.binding(keys.stackOrder)) {
            ForEach(CopyStackOrder.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        Toggle("Giữ ngăn xếp khi mở lại MyNotch", isOn: settings.binding(keys.stackPersist))
        Text("Ngăn xếp có thể chứa dữ liệu riêng tư, nên mặc định mất khi thoát. Mục mà trình quản lý mật khẩu đánh dấu là bí mật không bao giờ vào ngăn xếp.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: Locked boards

    /// What the notch and the library say of a locked board's idle time and of closing the notch.
    static let boardLockNote = "Board đã khoá luôn khoá lại khi máy ngủ, khi khoá màn hình và khi MyNotch thoát. Quên mật khẩu thì không có cách khôi phục; chỉ xoá được board."

    @ViewBuilder
    private var boardLocks: some View {
        Stepper(
            "Tự khoá lại board sau \(settings.value(keys.boardLockIdleMinutes)) phút không dùng",
            value: settings.binding(keys.boardLockIdleMinutes), in: ClipboardSettingKeys.boardLockIdleMinutesRange
        )
        Toggle("Khoá lại board khi đóng notch", isOn: settings.binding(keys.boardLockOnNotchClose))
        Text(Self.boardLockNote)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: Excluded apps

    @ViewBuilder
    private var excludedApps: some View {
        LabeledContent("Không ghi khi dùng app") {
            Button("Thêm app…", action: addApps)
        }
        ForEach(settings.value(keys.excludedBundleIDs), id: \.self) { bundleID in
            HStack {
                ExcludedAppLabel(bundleID: bundleID)
                Spacer()
                Button {
                    settings.set(settings.value(keys.excludedBundleIDs).filter { $0 != bundleID }, for: keys.excludedBundleIDs)
                } label: {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Bỏ khỏi danh sách")
            }
        }
    }

    /// Starts in /Applications and accepts only apps; their bundle IDs are added once each.
    private func addApps() {
        let panel = NSOpenPanel()
        panel.title = "Chọn app không ghi lịch sử clipboard"
        panel.prompt = "Thêm"
        panel.directoryURL = URL(filePath: "/Applications", directoryHint: .isDirectory)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        var excluded = settings.value(keys.excludedBundleIDs)
        for bundleID in panel.urls.compactMap({ Bundle(url: $0)?.bundleIdentifier }) where !excluded.contains(bundleID) {
            excluded.append(bundleID)
        }
        settings.set(excluded, for: keys.excludedBundleIDs)
    }

    // MARK: Storage

    @ViewBuilder
    private var storage: some View {
        LabeledContent("Dung lượng đang dùng") {
            switch usage {
            case .live(let state):
                Text(ClipboardStorageUsage(history: state.history).summary())
            case .disk(let directory):
                Text(diskUsage?.summary() ?? "Đang tính…")
                    .task(id: usageRevision) { diskUsage = await ClipboardStorageUsage.read(directory: directory) }
            }
        }
        LabeledContent("Lịch sử") {
            Menu("Xoá lịch sử…") {
                ForEach(ClipboardClearRange.allCases, id: \.self) { range in
                    Button(range.title) { pendingClear = range }
                }
            }
            .fixedSize()
        }
        .confirmationDialog(
            pendingClear.map { "Xoá lịch sử \($0.title.lowercased())?" } ?? "",
            isPresented: Binding(get: { pendingClear != nil }, set: { if !$0 { pendingClear = nil } }),
            presenting: pendingClear
        ) { range in
            Button("Xoá", role: .destructive) {
                Task {
                    await clear(range)
                    usageRevision += 1
                }
            }
        } message: { _ in
            Text("Mục đã ghim vào board được giữ lại.")
        }
    }

    // MARK: Pasteboard access

    /// macOS asks before each read unless the user picks "Luôn cho phép"; "always deny" leaves the history empty.
    @ViewBuilder
    private func pasteboardAccess(_ behavior: NSPasteboard.AccessBehavior) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Quyền đọc clipboard") {
                Text(behavior.title).foregroundStyle(behavior == .alwaysAllow ? .green : .orange)
            }
            if behavior != .alwaysAllow {
                Text("Để MyNotch ghi lại mọi lần chép mà macOS không hỏi lại, mở Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Dán từ app khác và chọn “Luôn cho phép” cho MyNotch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Mở Cài đặt hệ thống…") { NSWorkspace.shared.open(Self.pasteboardSettingsURL) }
            }
        }
    }
}

/// Name and icon of an excluded app, or just its bundle ID when it is not installed.
private struct ExcludedAppLabel: View {
    let bundleID: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Label {
                Text(FileManager.default.displayName(atPath: url.path(percentEncoded: false)).replacing(/\.app$/, with: ""))
            } icon: {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                    .resizable()
                    .frame(width: 16, height: 16)
            }
        } else {
            Label(bundleID, systemImage: "app.dashed")
        }
    }
}

private extension Retention {
    var title: String {
        switch self {
        case .day: "1 ngày"
        case .week: "1 tuần"
        case .month: "1 tháng"
        case .year: "1 năm"
        case .forever: "Mãi mãi"
        }
    }
}

private extension CopyStackOrder {
    var title: String {
        switch self {
        case .firstIn: "Vào trước, dán trước"
        case .lastIn: "Vào sau, dán trước"
        }
    }
}

private extension ClickAction {
    var title: String {
        switch self {
        case .copy: "Chép"
        case .paste: "Dán vào app đang dùng"
        }
    }
}

private extension NSPasteboard.AccessBehavior {
    var title: String {
        switch self {
        case .alwaysAllow: "Luôn cho phép"
        case .alwaysDeny: "Luôn chặn"
        case .ask: "Hỏi mỗi lần"
        case .default: "Chưa chọn"
        @unknown default: "Không rõ"
        }
    }
}
