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
                // Header Banner Section (Apple Style)
                Section {
                    HStack(spacing: 14) {
                        AppleSidebarIconBadge(
                            visuals: AppleSettingsVisuals.forModule(id, fallbackImage: descriptor.systemImage),
                            size: 34
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(descriptor.displayName)
                                .font(.system(size: 14, weight: .semibold))

                            HStack(spacing: 6) {
                                StateBadge(state: registry.state(of: id), isPaused: registry.isPaused && registry.isEnabled(id))
                                if case .failed = registry.state(of: id) { retryButton }
                                if case .unavailable = registry.state(of: id) { retryButton }
                            }
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { registry.isEnabled(id) },
                            set: { enabled in Task { await registry.setEnabled(enabled, for: id) } }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                    .padding(.vertical, 4)
                }

                permissionSection("Quyền hệ thống", descriptor.permissions)
                permissionSection("Quyền tuỳ chọn", descriptor.optionalPermissions)

                if let settingsView = registry.settingsView(for: id) {
                    Section("Cài đặt") { settingsView }
                }
            }
            .formStyle(.grouped)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                permissionRevision += 1
            }
        }
    }

    private var retryButton: some View {
        Button("Thử lại") { Task { await registry.retry(id) } }
            .buttonStyle(.bordered)
            .controlSize(.small)
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
        HStack(spacing: 10) {
            AppleSidebarIconBadge(
                visuals: AppleSettingsVisuals(color: .blue, systemImage: "hand.raised.fill"),
                size: 20
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(permission.displayName)
                    .font(.system(size: 13))
            }

            Spacer()

            TimelineView(.periodic(from: .now, by: 2)) { _ in
                let status = permissions.status(of: permission)
                let action = permission.grantAction(for: status)
                HStack(spacing: 8) {
                    StatusPill(status: status)
                    if status != .granted {
                        Button(action == .openSettings ? "Mở Cài đặt" : "Cấp quyền") {
                            isGranting = true
                            Task {
                                await registry.grant(permission)
                                isGranting = false
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isGranting)
                        .accessibilityLabel("\(action == .openSettings ? "Mở Cài đặt cho" : "Cấp quyền") \(permission.displayName)")
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct StateBadge: View {
    let state: ModuleState
    /// Pausing stops every enabled module without turning its switch off.
    let isPaused: Bool

    var body: some View {
        switch state {
        case .running:
            Text("Đang chạy")
                .font(.system(size: 12))
                .foregroundStyle(.green)
        case .disabled:
            Text(isPaused ? "Tạm dừng" : "Đã tắt")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        case .starting:
            Text("Đang khởi động…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        case .stopping:
            Text("Đang dừng…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        case .needsPermission(let permission):
            Text("Thiếu quyền \(permission.displayName)")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
        case .unavailable(let reason):
            Text(reason)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        case .failed(let reason):
            Text("Lỗi: \(reason)")
                .font(.system(size: 12))
                .foregroundStyle(.red)
        }
    }
}
