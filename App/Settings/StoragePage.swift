import AppKit
import MyNotchCore
import SwiftUI

/// What MyNotch keeps on disk, by module and kind, with a button to clean each and the rules that clean on their own.
struct StoragePage: View {
    let settings: SettingsStore
    let registry: ModuleRegistry
    /// Opens the Settings page of a module, where its own rule (how long to keep, how many) is set.
    let openModule: (ModuleID) -> Void
    @State private var confirming: Confirmation?
    @State private var lastFreed: Int64?

    private var center: StorageCenter { registry.storageCenter }

    var body: some View {
        Form {
            // 0. Full Disk Access Banner (Khi thiếu quyền đọc sâu các thư mục hệ thống/developer)
            if center.needsFullDiskAccess {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cần quyền Truy cập Đĩa Đầy đủ (Full Disk Access)")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Cấp quyền để MyNotch quét chính xác dung lượng của Xcode, SwiftPM, Caches và Thùng rác.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Mở Cài đặt…") {
                            openFullDiskAccessSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                    .padding(.vertical, 2)
                }
            }

            // 1. Apple-style Storage Bar Card (Top Card)
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("MyNotch Data")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        if center.isMeasuring {
                            ProgressView().controlSize(.small)
                        }
                        Text("Đang dùng \(Self.size(center.total))")
                            .font(.system(size: 13))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    // Multi-segment Bar
                    storageProgressBar

                    // Legend
                    storageLegend
                }
                .padding(.vertical, 4)

                if let lastFreed {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 12))
                        Text("Vừa giải phóng \(Self.size(lastFreed)).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // 2. Apple-style Recommendations Card
            Section("Khuyến nghị") {
                HStack(spacing: 12) {
                    AppleSidebarIconBadge(
                        visuals: AppleSettingsVisuals(color: .blue, systemImage: "arrow.triangle.2.circlepath"),
                        size: 32
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dọn dẹp bộ nhớ đệm")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Chỉ xoá những dữ liệu tạm MyNotch có thể tạo lại được. Cài đặt, hồ sơ EQ và file đã xuất không bao giờ bị xoá.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Dọn tất cả…") {
                        confirming = .all
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(center.cleanableBytes == 0 || center.isCleaning)
                }
                .padding(.vertical, 4)
            }

            // 3. Module Storage Breakdown (Apple List Style)
            if !visibleGroups.isEmpty {
                Section("Dung lượng theo Mô-đun") {
                    ForEach(visibleGroups) { group in
                        moduleGroupRow(group)
                    }
                }
            } else if !center.isMeasuring {
                Section {
                    Text("Chưa có dữ liệu nào trên đĩa.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            // 4. Developer Artifacts Cleaner
            let devCategories = center.categories(in: .developer)
            if !devCategories.isEmpty {
                Section("Dọn dẹp Lập trình viên") {
                    ForEach(devCategories) { category in
                        externalCategoryRow(category, groupName: "Lập trình viên", icon: "hammer.fill", iconColor: .orange)
                    }
                }
            }

            // 5. System Caches & Trash Cleaner
            let sysCategories = center.categories(in: .system)
            if !sysCategories.isEmpty {
                Section("Dọn dẹp Hệ thống") {
                    ForEach(sysCategories) { category in
                        let iconName = systemCategoryIcon(for: category.id)
                        let iconColor = systemCategoryColor(for: category.id)
                        externalCategoryRow(category, groupName: "Hệ thống", icon: iconName, iconColor: iconColor)
                    }
                }
            }

            // 6. Auto Clean Rules
            autoCleanSection
        }
        .formStyle(.grouped)
        .task { await center.refresh() }
        .confirmationDialog(
            confirming?.title ?? "",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible,
            presenting: confirming
        ) { confirmation in
            Button("Xoá", role: .destructive) { run(confirmation) }
            Button("Huỷ", role: .cancel) {}
        } message: { confirmation in
            Text(confirmation.message(center))
        }
    }

    // MARK: - Multi-Segment Bar & Legend

    private var visibleGroups: [StorageGroup] { center.groups.filter { $0.bytes > 0 } }

    private var storageProgressBar: some View {
        GeometryReader { geo in
            let total = max(1, center.total)
            HStack(spacing: 1.5) {
                if visibleGroups.isEmpty {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: geo.size.width)
                } else {
                    ForEach(visibleGroups) { group in
                        let fraction = CGFloat(group.bytes) / CGFloat(total)
                        let width = max(4, geo.size.width * fraction)
                        let color = AppleSettingsVisuals.forModule(group.id, fallbackImage: group.systemImage).color

                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(color)
                            .frame(width: width)
                    }
                }
            }
        }
        .frame(height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private var storageLegend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), alignment: .leading)], spacing: 6) {
            ForEach(visibleGroups.prefix(6)) { group in
                let color = AppleSettingsVisuals.forModule(group.id, fallbackImage: group.systemImage).color
                HStack(spacing: 5) {
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                    Text(group.name)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Module Row

    private func moduleGroupRow(_ group: StorageGroup) -> some View {
        HStack(spacing: 10) {
            AppleSidebarIconBadge(
                visuals: AppleSettingsVisuals.forModule(group.id, fallbackImage: group.systemImage),
                size: 22
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.system(size: 13))

                let categoriesSummary = group.categories.map(\.title).joined(separator: ", ")
                if !categoriesSummary.isEmpty {
                    Text(categoriesSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(Self.size(group.bytes))
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            let cleanableInGroup = group.categories.filter { $0.canClean && $0.bytes > 0 }
            if !cleanableInGroup.isEmpty {
                Button("Dọn") {
                    if let first = cleanableInGroup.first {
                        confirming = .category(first, in: group.name)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(center.isCleaning)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - External Category Row (Developer & System)

    private func externalCategoryRow(
        _ category: StorageCategory,
        groupName: String,
        icon: String,
        iconColor: Color
    ) -> some View {
        HStack(spacing: 10) {
            AppleSidebarIconBadge(
                visuals: AppleSettingsVisuals(color: iconColor, systemImage: icon),
                size: 22
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(category.title)
                        .font(.system(size: 13))

                    if category.needsFullDiskAccess {
                        Text("Thiếu quyền FDA")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.orange.opacity(0.12))
                            )
                    }
                }

                if let keeps = category.keeps {
                    Text(keeps)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if category.needsFullDiskAccess && category.bytes == 0 {
                Text("Không đọc được")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text(Self.size(category.bytes))
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            if category.canClean && category.bytes > 0 {
                Button("Dọn") {
                    confirming = .category(category, in: groupName)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(center.isCleaning)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Auto Clean Section

    private var autoCleanSection: some View {
        Section("Tự dọn định kỳ") {
            Stepper(
                "Xoá bộ nhớ tạm cũ hơn \(settings.value(StorageCenter.cacheMaxAgeDaysKey)) ngày",
                value: settings.binding(StorageCenter.cacheMaxAgeDaysKey),
                in: StorageCenter.cacheMaxAgeDaysRange
            )

            Stepper(
                "Giới hạn bộ nhớ tạm của mọi mô-đun: \(settings.value(StorageCenter.cacheMaxMBKey)) MB",
                value: settings.binding(StorageCenter.cacheMaxMBKey),
                in: StorageCenter.cacheMaxMBRange,
                step: 50
            )

            Text("Khi vượt giới hạn, file cũ nhất bị xoá trước. MyNotch dọn khi mở app và sau đó mỗi 24 giờ.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(center.groups.filter { $0.autoCleanSummary != nil }) { group in
                HStack {
                    AppleSidebarIconBadge(
                        visuals: AppleSettingsVisuals.forModule(group.id, fallbackImage: group.systemImage),
                        size: 20
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name)
                            .font(.system(size: 13))
                        Text(group.autoCleanSummary ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Mở cài đặt") {
                        openModule(group.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.vertical, 1)
            }
        }
    }

    // MARK: - Helpers

    private func run(_ confirmation: Confirmation) {
        Task {
            let freed: Int64
            switch confirmation {
            case .category(let category, _): freed = await center.clean(category.id)
            case .all: freed = await center.cleanAll()
            }
            if freed > 0 { lastFreed = freed }
        }
    }

    private static func size(_ bytes: Int64) -> String { bytes.formatted(.byteCount(style: .file)) }

    private func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private func systemCategoryIcon(for id: String) -> String {
        if id.contains("trash") { return "trash" }
        if id.contains("logs") { return "doc.plaintext" }
        return "archivebox"
    }

    private func systemCategoryColor(for id: String) -> Color {
        if id.contains("trash") { return .red }
        if id.contains("logs") { return .gray }
        return .indigo
    }

    private enum Confirmation: Identifiable {
        case category(StorageCategory, in: String)
        case all

        var id: String {
            switch self {
            case .category(let category, _): category.id
            case .all: "all"
            }
        }

        var title: String {
            switch self {
            case .category(let category, let module): "Xoá \(category.title) (\(module))?"
            case .all: "Dọn tất cả những thứ có thể dọn?"
            }
        }

        func message(_ center: StorageCenter) -> String {
            switch self {
            case .category(let category, _):
                var msg = "Giải phóng khoảng \(StoragePage.size(category.bytes))."
                if let keeps = category.keeps {
                    msg += " \(keeps)."
                }
                if let caution = category.caution {
                    msg += "\n\nLưu ý: \(caution)"
                }
                return msg
            case .all:
                return "Giải phóng khoảng \(StoragePage.size(center.cleanableBytes))."
            }
        }
    }
}
