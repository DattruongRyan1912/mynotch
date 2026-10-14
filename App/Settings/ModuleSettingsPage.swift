import AppKit
import Combine
import MyNotchCore
import SwiftUI

struct ModuleSettingsPage: View {
    let id: ModuleID
    let registry: ModuleRegistry
    let permissions: any PermissionCenter
    @State private var permissionRevision = 0

    private var module: (any FeatureModule)? { registry.modules.first { $0.descriptor.id == id } }

    var body: some View {
        if let descriptor = module?.descriptor {
            Form {
                Section {
                    Toggle("Bật \(descriptor.displayName)", isOn: Binding(
                        get: { registry.isEnabled(id) },
                        set: { enabled in Task { await registry.setEnabled(enabled, for: id) } }
                    ))
                    LabeledContent("Trạng thái") { StateBadge(state: registry.state(of: id), isPaused: registry.isPaused && registry.isEnabled(id)) }
                    if case .failed = registry.state(of: id) { retryButton }
                    if case .unavailable = registry.state(of: id) { retryButton }
                }
                permissionSection("Quyền hệ thống", descriptor.permissions)
                permissionSection("Quyền tuỳ chọn", descriptor.optionalPermissions)
                if let settingsView = registry.settingsView(for: id) {
                    Section("Cài đặt") { settingsView }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(descriptor.displayName)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                permissionRevision += 1
            }
        }
    }

    private var retryButton: some View {
        Button("Thử lại") { Task { await registry.retry(id) } }
    }

    @ViewBuilder
    private func permissionSection(_ title: String, _ list: [Permission]) -> some View {
        if !list.isEmpty {
            Section(title) {
                ForEach(list, id: \.self) { permission in
                    PermissionRow(permission: permission, registry: registry, permissions: permissions)
                }
            }
            .id(permissionRevision)
        }
    }
}

/// TCC posts no notification when a permission changes, so the status is re-read every 2 s while the row is on screen.
private struct PermissionRow: View {
    let permission: Permission
    let registry: ModuleRegistry
    let permissions: any PermissionCenter
    /// Repeated taps while a prompt is pending would otherwise start parallel requests.
    @State private var isGranting = false

    var body: some View {
        LabeledContent(permission.displayName) {
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                let status = permissions.status(of: permission)
                HStack {
                    switch status {
                    case .granted: Text("Đã cấp").foregroundStyle(.green)
                    case .denied: Text("Chưa cấp").foregroundStyle(.orange)
                    case .notDetermined: Text("Chưa xin").foregroundStyle(.secondary)
                    case .unknown: Text("Chưa kiểm tra được").foregroundStyle(.secondary)
                    }
                    if status != .granted {
                        Button("Cấp quyền") {
                            isGranting = true
                            Task {
                                await registry.grant(permission)
                                isGranting = false
                            }
                        }
                        .disabled(isGranting)
                        .accessibilityLabel("Cấp quyền \(permission.displayName)")
                    }
                }
            }
        }
    }
}

private struct StateBadge: View {
    let state: ModuleState
    /// Pausing stops every enabled module without turning its switch off.
    let isPaused: Bool

    var body: some View {
        switch state {
        case .running: Text("Đang chạy").foregroundStyle(.green)
        case .disabled: Text(isPaused ? "Tạm dừng" : "Đã tắt").foregroundStyle(.secondary)
        case .starting: Text("Đang khởi động…")
        case .stopping: Text("Đang dừng…")
        case .needsPermission(let permission): Text("Thiếu quyền \(permission.displayName)").foregroundStyle(.orange)
        case .unavailable(let reason): Text(reason).foregroundStyle(.secondary)
        case .failed(let reason): Text("Lỗi: \(reason)").foregroundStyle(.red)
        }
    }
}
