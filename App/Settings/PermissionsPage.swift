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
            rows("Cần thiết", overview.requiredRows)
            rows("Tuỳ chọn", overview.optionalRows)
        }
        .formStyle(.grouped)
        .navigationTitle("Quyền")
        .onAppear { overview.setPageVisible(true) }
        .onDisappear { overview.setPageVisible(false) }
    }

    @ViewBuilder
    private var summary: some View {
        if overview.requirements.isEmpty {
            Text("Chưa có tính năng nào đang bật cần quyền hệ thống.").foregroundStyle(.secondary)
        } else {
            HStack {
                Text(overview.missingCount == 0 ? "Đã đủ quyền." : "Còn \(overview.missingCount) quyền chưa cấp.")
                Spacer()
                Button("Cấp lần lượt") { overview.startWalkthrough() }
                    .disabled(overview.missingCount == 0 || overview.walkthrough != .idle)
            }
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
                Spacer()
                Button("Dừng") { overview.stopWalkthrough() }
            }
        case .waiting(let step):
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bước \(step.position)/\(step.total): \(step.permission.displayName)").font(.headline)
                    Text(step.permission.instruction).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Bỏ qua") { overview.skipWalkthroughStep() }
                Button("Dừng") { overview.stopWalkthrough() }
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
            Image(systemName: permission.systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(permission.displayName).font(.headline)
                    StatusPill(status: status)
                }
                ForEach(requirement.uses, id: \.module) { use in
                    Text("\(use.moduleName): \(use.reason)").font(.caption).foregroundStyle(.secondary)
                }
                if status.isMissing && (action == .openSettings || permission.isSettingsOnly) {
                    Text(permission.instruction).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if status != .granted {
                Button(action == .openSettings ? "Mở Cài đặt" : "Cấp quyền") {
                    Task { await overview.grant(permission) }
                }
                .disabled(overview.granting.contains(permission))
                .accessibilityLabel("\(action == .openSettings ? "Mở Cài đặt cho" : "Cấp quyền") \(permission.displayName)")
            }
        }
    }
}

private struct StatusPill: View {
    let status: PermissionStatus

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: .capsule)
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
