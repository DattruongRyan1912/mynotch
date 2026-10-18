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
            Section {
                LabeledContent("MyNotch đang dùng") {
                    HStack(spacing: 8) {
                        if center.isMeasuring { ProgressView().controlSize(.small) }
                        Text(Self.size(center.total)).monospacedDigit()
                    }
                }
                if let lastFreed {
                    Text("Vừa giải phóng \(Self.size(lastFreed)).").font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(visibleGroups) { group in
                Section {
                    ForEach(group.categories) { category in row(category, of: group) }
                } header: {
                    Label(group.name, systemImage: group.systemImage)
                }
            }
            if visibleGroups.isEmpty && !center.isMeasuring {
                Section { Text("Chưa có gì để dọn.").foregroundStyle(.secondary) }
            }
            Section {
                Button("Dọn tất cả những thứ có thể dọn") { confirming = .all }
                    .disabled(center.cleanableBytes == 0 || center.isCleaning)
            } footer: {
                Text("Chỉ xoá những thứ MyNotch tạo lại hoặc có thể mất được. Cài đặt, hồ sơ EQ và file bạn đã xuất ra ngoài thư mục của MyNotch không bao giờ bị xoá.")
            }
            autoCleanSection
        }
        .formStyle(.grouped)
        .navigationTitle("Dung lượng")
        .task { await center.refresh() }
        .confirmationDialog(
            confirming?.title ?? "", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible, presenting: confirming
        ) { confirmation in
            Button("Xoá", role: .destructive) { run(confirmation) }
            Button("Huỷ", role: .cancel) {}
        } message: { confirmation in
            Text(confirmation.message(center))
        }
    }

    /// A module with nothing on disk would only add a row of zeros, so it is left out until it has something.
    private var visibleGroups: [StorageGroup] { center.groups.filter { $0.bytes > 0 } }

    private func row(_ category: StorageCategory, of group: StorageGroup) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                if let keeps = category.keeps { Text(keeps).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(Self.size(category.bytes)).monospacedDigit().foregroundStyle(.secondary)
            if category.canClean {
                Button("Dọn") { confirming = .category(category, in: group.name) }
                    .disabled(category.bytes == 0 || center.isCleaning)
                    .accessibilityLabel("Dọn \(category.title) của \(group.name)")
            }
        }
    }

    private var autoCleanSection: some View {
        Section("Tự dọn") {
            Stepper(
                "Xoá bộ nhớ tạm cũ hơn \(settings.value(StorageCenter.cacheMaxAgeDaysKey)) ngày",
                value: settings.binding(StorageCenter.cacheMaxAgeDaysKey), in: StorageCenter.cacheMaxAgeDaysRange
            )
            Stepper(
                "Giới hạn bộ nhớ tạm của mọi module: \(settings.value(StorageCenter.cacheMaxMBKey)) MB",
                value: settings.binding(StorageCenter.cacheMaxMBKey), in: StorageCenter.cacheMaxMBRange, step: 50
            )
            Text("Khi vượt giới hạn, file cũ nhất bị xoá trước. MyNotch dọn khi mở app và sau đó mỗi 24 giờ.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(center.groups.filter { $0.autoCleanSummary != nil }) { group in
                LabeledContent {
                    Button("Mở cài đặt") { openModule(group.id) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(group.name, systemImage: group.systemImage)
                        Text(group.autoCleanSummary ?? "").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

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
                "Giải phóng khoảng \(StoragePage.size(category.bytes))." + (category.keeps.map { " \($0)." } ?? "")
            case .all:
                "Giải phóng khoảng \(StoragePage.size(center.cleanableBytes))."
            }
        }
    }
}
