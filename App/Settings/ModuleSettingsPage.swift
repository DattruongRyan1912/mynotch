import MyNotchCore
import SwiftUI

struct ModuleSettingsPage: View {
    let id: ModuleID
    let registry: ModuleRegistry
    let permissions: any PermissionCenter

    private var module: (any FeatureModule)? { registry.modules.first { $0.descriptor.id == id } }

    var body: some View {
        if let descriptor = module?.descriptor {
            Form {
                Section {
                    Toggle("Bật \(descriptor.displayName)", isOn: Binding(
                        get: { registry.isEnabled(id) },
                        set: { enabled in Task { await registry.setEnabled(enabled, for: id) } }
                    ))
                    LabeledContent("Trạng thái") { StateBadge(state: registry.state(of: id)) }
                    if case .failed = registry.state(of: id) { retryButton }
                    if case .unavailable = registry.state(of: id) { retryButton }
                }
                if !descriptor.permissions.isEmpty {
                    Section("Quyền hệ thống") {
                        ForEach(descriptor.permissions, id: \.self) { permission in
                            LabeledContent(permission.displayName) {
                                if permissions.status(of: permission) == .granted {
                                    Text("Đã cấp").foregroundStyle(.green)
                                } else {
                                    Button("Cấp quyền") { permissions.openSystemSettings(for: permission) }
                                }
                            }
                        }
                    }
                }
                if let settingsView = registry.settingsView(for: id) {
                    Section("Cài đặt") { settingsView }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(descriptor.displayName)
        }
    }

    private var retryButton: some View {
        Button("Thử lại") { Task { await registry.retry(id) } }
    }
}

private struct StateBadge: View {
    let state: ModuleState

    var body: some View {
        switch state {
        case .running: Text("Đang chạy").foregroundStyle(.green)
        case .disabled: Text("Đã tắt").foregroundStyle(.secondary)
        case .starting: Text("Đang khởi động…")
        case .stopping: Text("Đang dừng…")
        case .needsPermission(let permission): Text("Thiếu quyền \(permission.displayName)").foregroundStyle(.orange)
        case .unavailable(let reason): Text(reason).foregroundStyle(.secondary)
        case .failed(let reason): Text("Lỗi: \(reason)").foregroundStyle(.red)
        }
    }
}
