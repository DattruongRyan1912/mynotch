import MyNotchCore
import SwiftUI

struct DashboardModulesView: View {
    let registry: ModuleRegistry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Section Header
                DashboardSectionHeader(
                    title: "Quản lý 20 Mô-đun Hệ thống",
                    subtitle: "Bật / Tắt hoặc điều phối tài nguyên từng module"
                )

                // Modules Table
                VStack(spacing: 0) {
                    // Table Header
                    HStack {
                        Text("MÔ-ĐUN")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(DashboardTheme.textMuted)
                            .frame(width: 220, alignment: .leading)

                        Text("TRẠNG THÁI")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(DashboardTheme.textMuted)
                            .frame(width: 140, alignment: .leading)

                        Text("DUNG LƯỢNG ĐĨA")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(DashboardTheme.textMuted)
                            .frame(width: 120, alignment: .leading)

                        Spacer()

                        Text("HOẠT ĐỘNG")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(DashboardTheme.textMuted)
                            .frame(width: 80, alignment: .trailing)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(DashboardTheme.insetBackground)

                    Rectangle()
                        .fill(DashboardTheme.hairlineBorder)
                        .frame(height: 1)

                    // Module Rows
                    ForEach(registry.modules, id: \.descriptor.id) { module in
                        moduleRow(module: module)

                        if module.descriptor.id != registry.modules.last?.descriptor.id {
                            Rectangle()
                                .fill(DashboardTheme.subtleDivider)
                                .frame(height: 1)
                        }
                    }
                }
                .dashboardCard(padding: 0)
            }
            .padding(20)
        }
    }

    private func moduleRow(module: any FeatureModule) -> some View {
        let isEnabled = registry.isEnabled(module.descriptor.id)
        let isPaused = registry.isPaused && isEnabled
        let bytes = registry.storageCenter.groups.first { $0.id == module.descriptor.id }?.bytes ?? 0

        return HStack(alignment: .center) {
            // Module Info
            HStack(spacing: 10) {
                Image(systemName: module.descriptor.systemImage)
                    .font(.system(size: 14))
                    .foregroundColor(isEnabled ? DashboardTheme.textPrimary : DashboardTheme.textMuted)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(module.descriptor.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isEnabled ? DashboardTheme.textPrimary : DashboardTheme.textSecondary)

                    Text(module.descriptor.id.rawValue)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(DashboardTheme.textMuted)
                }
            }
            .frame(width: 220, alignment: .leading)

            // Status Badge
            HStack(spacing: 6) {
                if !isEnabled {
                    DashboardStatusDot(level: .normal, size: 6)
                    Text("Đã tắt")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(DashboardTheme.textMuted)
                } else if isPaused {
                    DashboardStatusDot(level: .warning, size: 6)
                    Text("Tạm dừng")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(DashboardTheme.warningText)
                } else {
                    DashboardStatusDot(level: .success, size: 6)
                    Text("Đang chạy")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(DashboardTheme.successText)
                }
            }
            .frame(width: 140, alignment: .leading)

            // Storage Size
            Text(formatBytes(bytes))
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundColor(DashboardTheme.textSecondary)
                .frame(width: 120, alignment: .leading)

            Spacer()

            // Toggle Action
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { newValue in
                    Task {
                        await registry.setEnabled(newValue, for: module.descriptor.id)
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .scaleEffect(0.8)
            .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes == 0 { return "0 B" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
