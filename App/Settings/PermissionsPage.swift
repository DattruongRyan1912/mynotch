import MyNotchCore
import SwiftUI

/// Every permission the enabled modules need in one place, with a button that walks through the missing ones.
struct PermissionsPage: View {
    let overview: PermissionOverview

    var body: some View {
        Form {
            Section {
                summary
                if overview.walkthrough != .idle { walkthroughBanner }
            }
            rows("Quyền cần thiết", overview.requiredRows)
            rows("Quyền tuỳ chọn", overview.optionalRows)
        }
        .formStyle(.grouped)
        .onAppear { overview.setPageVisible(true) }
        .onDisappear { overview.setPageVisible(false) }
    }

    @ViewBuilder
    private var summary: some View {
        if overview.requirements.isEmpty {
            Text("Chưa có tính năng nào đang bật cần quyền hệ thống.").foregroundStyle(.secondary)
        } else {
            HStack {
                Text(overview.missingCount == 0 ? "Tất cả các quyền đã được cấp đầy đủ." : "Còn \(overview.missingCount) quyền hệ thống chưa cấp.")
                    .font(.system(size: 13))
                Spacer()
                Button("Cấp lần lượt…") { overview.startWalkthrough() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(overview.missingCount == 0 || overview.walkthrough != .idle)
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var walkthroughBanner: some View {
        switch overview.walkthrough {
        case .idle:
            EmptyView()
        case .requesting(let step):
            HStack {
                ProgressView().controlSize(.small)
                Text("Bước \(step.position)/\(step.total): \(step.permission.displayName). Hãy trả lời hộp thoại của macOS.")
                    .font(.system(size: 12))
                Spacer()
                Button("Dừng") { overview.stopWalkthrough() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        case .waiting(let step):
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bước \(step.position)/\(step.total): \(step.permission.displayName)").font(.headline)
                    Text(step.permission.instruction).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Mở Cài đặt") { Task { await overview.grant(step.permission) } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(overview.granting.contains(step.permission))
                Button("Bỏ qua") { overview.skipWalkthroughStep() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Dừng") { overview.stopWalkthrough() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func rows(_ title: String, _ requirements: [PermissionRequirement]) -> some View {
        if !requirements.isEmpty {
            Section(title) {
                ForEach(requirements) { PermissionRequirementRow(requirement: $0, overview: overview) }
            }
        }
    }
}

private struct PermissionRequirementRow: View {
    let requirement: PermissionRequirement
    let overview: PermissionOverview

    var body: some View {
        let permission = requirement.permission
        let status = overview.status(of: permission)
        let action = permission.grantAction(for: status)
        HStack(alignment: .top, spacing: 12) {
            AppleSidebarIconBadge(visuals: visual(for: permission), size: 26)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(permission.displayName)
                        .font(.system(size: 13, weight: .semibold))
                    StatusPill(status: status)
                }
                ForEach(requirement.uses, id: \.module) { use in
                    Text("\(use.moduleName): \(use.reason)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if permission.showsInstruction(for: status) {
                    Text(permission.instruction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if status != .granted {
                VStack(alignment: .trailing, spacing: 4) {
                    Button(action == .openSettings ? "Mở Cài đặt" : "Cấp quyền") {
                        Task { await overview.grant(permission) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(overview.granting.contains(permission))
                    .accessibilityLabel("\(action == .openSettings ? "Mở Cài đặt cho" : "Cấp quyền") \(permission.displayName)")

                    if permission == .accessibility && status == .denied {
                        Button("Khôi phục (Auto-Recovery)") {
                            Task { await overview.recoverAccessibility() }
                        }
                        .buttonStyle(.link)
                        .font(.caption2)
                        .foregroundStyle(.tint)
                        .help("Khôi phục quyền Accessibility bằng tccutil sau khi cập nhật ứng dụng")
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }

    private func visual(for permission: Permission) -> AppleSettingsVisuals {
        switch permission {
        case .accessibility:
            return AppleSettingsVisuals(color: .blue, systemImage: "figure.stand")
        case .screenRecording:
            return AppleSettingsVisuals(color: .indigo, systemImage: "record.circle.fill")
        case .calendars:
            return AppleSettingsVisuals(color: .red, systemImage: "calendar")
        case .reminders:
            return AppleSettingsVisuals(color: .orange, systemImage: "checklist")
        case .bluetooth:
            return AppleSettingsVisuals(color: .blue, systemImage: "dot.radiowaves.left.and.right")
        case .microphone:
            return AppleSettingsVisuals(color: .pink, systemImage: "mic.fill")
        case .systemAudio:
            return AppleSettingsVisuals(color: .red, systemImage: "speaker.wave.3.fill")
        case .downloadsFolder, .desktopFolder:
            return AppleSettingsVisuals(color: .cyan, systemImage: "folder.fill")
        case .pasteboard:
            return AppleSettingsVisuals(color: .teal, systemImage: "doc.on.clipboard.fill")
        case .automation:
            return AppleSettingsVisuals(color: .gray, systemImage: "applescript.fill")
        }
    }
}

/// Shared with the module pages so a permission reads the same everywhere.
struct StatusPill: View {
    let status: PermissionStatus

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 1.5)
            .background(color.opacity(0.12), in: .capsule)
    }

    private var title: String {
        switch status {
        case .granted: "Đã cấp"
        case .notDetermined: "Chưa cấp"
        case .denied: "Bị từ chối"
        case .unknown: "Chưa kiểm tra được"
        }
    }

    private var color: Color {
        switch status {
        case .granted: .green
        case .notDetermined: .orange
        case .denied: .red
        case .unknown: .secondary
        }
    }
}
