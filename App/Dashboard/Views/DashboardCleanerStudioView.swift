import AppKit
import CleanerModule
import ClipboardModule
import MyNotchCore
import SwiftUI
import UniformTypeIdentifiers

/// Phòng điều khiển Dọn dẹp & Tối ưu hoá Hệ thống và Tài nguyên MyNotch.
struct DashboardCleanerStudioView: View {
    let telemetry: DashboardTelemetryCenter
    let registry: ModuleRegistry

    @ObservedObject private var themeStore = DashboardThemeStore.shared

    // MARK: - State Management
    @State private var selectedCategoryIDs: Set<String> = []
    @State private var appCacheScan: MyNotchAppCacheScan = MyNotchAppCacheScan()
    @State private var memoryFootprintBytes: UInt64 = 0
    @State private var lastReclaimedBytes: Int? = nil
    @State private var isScanning: Bool = false
    @State private var isCleaningBatch: Bool = false
    @State private var isRelievingMemory: Bool = false
    @State private var isPurgingClipboard: Bool = false
    @State private var isCleaningAppCaches: Bool = false
    @State private var categoryToConfirm: StorageCategory? = nil
    @State private var showBatchCautionConfirm: Bool = false
    @State private var isDropTargeted: Bool = false

    private var selectedCategoriesWithCaution: [StorageCategory] {
        let allScanned = storageCenter.categories(in: .developer) + storageCenter.categories(in: .system)
        return allScanned.filter { selectedCategoryIDs.contains($0.id) && $0.caution != nil }
    }

    private var hasCautionInSelection: Bool {
        !selectedCategoriesWithCaution.isEmpty
    }

    private var batchButtonTitle: String {
        let count = selectedCategoryIDs.count
        if hasCautionInSelection {
            return "Dọn mục đã chọn (\(count))"
        } else {
            return "Dọn dẹp an toàn (\(count))"
        }
    }

    private func displayPath(for categoryID: String) -> String {
        if let entry = CleanerCatalog.entries.first(where: { $0.id == categoryID }) {
            return entry.relativePaths.map { "~/\($0)" }.joined(separator: ", ")
        }
        return categoryID
    }

    private var storageCenter: StorageCenter {
        registry.storageCenter
    }

    private var cleanerModule: CleanerModule? {
        registry.module(for: "cleaner") as? CleanerModule
    }

    private var clipboardModule: ClipboardModule? {
        registry.module(for: "clipboard") as? ClipboardModule
    }

    private var toastCenter: DashboardToastCenter {
        DashboardToastCenter.shared
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                // Section 1: Telemetry Overview & Quick Actions
                overviewSection

                // Section 2: Tài nguyên Nội bộ MyNotch
                myNotchInternalSection

                // Section 3: Rác Lập trình & Hệ thống macOS
                systemAndDeveloperSection

                // Section 4: Gỡ bỏ Ứng dụng & Dọn tệp thừa
                appUninstallerSection
            }
            .padding(20)
        }
        .background(DashboardTheme.canvasBackground)
        .task {
            await refreshAll(silent: true)
        }
        .confirmationDialog(
            "Xác nhận Dọn dẹp",
            isPresented: Binding(
                get: { categoryToConfirm != nil },
                set: { if !$0 { categoryToConfirm = nil } }
            ),
            presenting: categoryToConfirm
        ) { cat in
            Button("Dọn dẹp \"\(cat.title)\"", role: .destructive) {
                Task {
                    await cleanSingleCategory(cat)
                }
            }
            Button("Huỷ", role: .cancel) {}
        } message: { cat in
            Text(cat.caution ?? "Bạn có chắc chắn muốn dọn dẹp mục này không?")
        }
        .confirmationDialog(
            "Xác nhận Dọn dẹp Các Mục Đã Chọn",
            isPresented: $showBatchCautionConfirm
        ) {
            Button("Dọn dẹp \(selectedCategoryIDs.count) mục đã chọn", role: .destructive) {
                Task {
                    await cleanSelectedBatch()
                }
            }
            Button("Huỷ", role: .cancel) {}
        } message: {
            let cautions = selectedCategoriesWithCaution.map { "• \($0.title): \($0.caution ?? "")" }.joined(separator: "\n")
            Text("Các mục sau có lưu ý an toàn:\n\(cautions)\n\nBạn có chắc chắn muốn dọn dẹp vĩnh viễn không?")
        }
    }

    // MARK: - Section 1: Overview & Toolbar

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                DashboardSectionHeader(
                    title: "Dọn dẹp & Tối ưu",
                    subtitle: "Giải phóng ổ đĩa macOS và tối ưu tài nguyên tiến trình MyNotch"
                )

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        Task { await refreshAll(silent: false) }
                    } label: {
                        HStack(spacing: 6) {
                            if isScanning {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            Text("Quét lại")
                                .font(.system(size: 11.5, weight: .medium))
                        }
                        .foregroundColor(DashboardTheme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(DashboardTheme.controlBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(DashboardTheme.controlBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isScanning || isCleaningBatch)

                    Button {
                        if hasCautionInSelection {
                            showBatchCautionConfirm = true
                        } else {
                            Task { await cleanSelectedBatch() }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isCleaningBatch {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "trash")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            Text(batchButtonTitle)
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .foregroundColor(Color.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(DashboardTheme.hardwareCoral)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedCategoryIDs.isEmpty || isCleaningBatch)
                }
            }

            // FDA Notice Banner if needed
            if storageCenter.needsFullDiskAccess {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 14))
                        .foregroundColor(DashboardTheme.hardwareCoral)

                    Text("Cần cấp quyền Full Disk Access (FDA) để MyNotch quét và dọn sạch các tệp rác hệ thống và nhật ký.")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(DashboardTheme.textSecondary)

                    Spacer()

                    Button("Mở Cài đặt") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.link)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(DashboardTheme.rowBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(DashboardTheme.insetBorder, lineWidth: 1)
                )
            }

            // 4 Telemetry Metrics Grid
            HStack(spacing: 12) {
                let safeBytes = calculateSafeSelectedBytes()
                DashboardMetricCard(
                    label: "Dọn dẹp an toàn",
                    value: DashboardTheme.formatBytes(safeBytes),
                    unit: "",
                    icon: "checkmark.shield",
                    level: safeBytes > 0 ? .warning : .normal,
                    subtitle: "\(selectedCategoryIDs.count) mục được chọn"
                )

                let devSystemBytes = storageCenter.categories(in: .developer).reduce(0) { $0 + $1.bytes } +
                    storageCenter.categories(in: .system).reduce(0) { $0 + $1.bytes }
                DashboardMetricCard(
                    label: "Rác Dev & Hệ thống",
                    value: DashboardTheme.formatBytes(devSystemBytes),
                    unit: "",
                    icon: "internaldrive",
                    level: .normal,
                    subtitle: "Xcode, Caches, Logs, Trash"
                )

                let myNotchBytes = storageCenter.cleanableBytes + appCacheScan.totalBytes
                DashboardMetricCard(
                    label: "Tài nguyên MyNotch",
                    value: DashboardTheme.formatBytes(myNotchBytes),
                    unit: "",
                    icon: "shippingbox",
                    level: .normal,
                    subtitle: "Caches mô-đun & clipboard"
                )

                DashboardMetricCard(
                    label: "RAM MyNotch",
                    value: DashboardTheme.formatBytes(Int64(memoryFootprintBytes)),
                    unit: "",
                    icon: "cpu",
                    level: .normal,
                    subtitle: lastReclaimedBytes.map { $0 > 0 ? "Đã hồi \(DashboardTheme.formatBytes(Int64($0)))" : "Đã hồi 0 B" } ?? "Bộ nhớ tiến trình"
                )
            }
        }
        .dashboardCard()
    }

    // MARK: - Section 2: Tài nguyên Nội bộ MyNotch

    private var myNotchInternalSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            DashboardSectionHeader(
                title: "Tài nguyên Nội bộ MyNotch",
                subtitle: "Tối ưu bộ nhớ đệm, lịch sử sao chép và thu hồi RAM tiến trình"
            )

            VStack(spacing: 10) {
                // Card 1: Clipboard Optimizer
                let clipStatus = clipboardModule?.studioStatus() ?? ClipboardStudioStatus(totalItems: 0, pinnedItems: 0, unpinnedItems: 0, boardsCount: 0)
                HStack(spacing: 14) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 20))
                        .foregroundColor(DashboardTheme.infoAccent)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Bộ nhớ tạm & Ảnh Clipboard")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(DashboardTheme.textPrimary)

                        HStack(spacing: 8) {
                            Text("Tổng \(clipStatus.totalItems) mục")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(DashboardTheme.textSecondary)
                            Text("•")
                                .foregroundColor(DashboardTheme.textMuted)
                            Text("\(clipStatus.unpinnedItems) chưa ghim")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(DashboardTheme.hardwareCoral)
                            Text("•")
                                .foregroundColor(DashboardTheme.textMuted)
                            Text("\(clipStatus.pinnedItems) đã ghim (\(clipStatus.boardsCount) bảng)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(DashboardTheme.statusNormal)
                        }
                    }

                    Spacer()

                    Button {
                        Task { await purgeClipboardHistory() }
                    } label: {
                        HStack(spacing: 6) {
                            if isPurgingClipboard {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "trash")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            Text("Dọn mục chưa ghim & ảnh thừa")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(DashboardTheme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(DashboardTheme.controlBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(DashboardTheme.controlBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(clipStatus.unpinnedItems == 0 || isPurgingClipboard)
                }
                .padding(12)
                .background(DashboardTheme.rowBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                // Card 2: App Caches & Module Storage
                let internalTotal = storageCenter.cleanableBytes + appCacheScan.totalBytes
                HStack(spacing: 14) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 20))
                        .foregroundColor(DashboardTheme.habitViolet)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Bộ nhớ đệm Mô-đun & Nhật ký MyNotch")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(DashboardTheme.textPrimary)

                        HStack(spacing: 8) {
                            Text("Cache mô-đun: \(DashboardTheme.formatBytes(storageCenter.cleanableBytes))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(DashboardTheme.textSecondary)
                            Text("•")
                                .foregroundColor(DashboardTheme.textMuted)
                            Text("Cache tạm: \(DashboardTheme.formatBytes(appCacheScan.appCacheBytes))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(DashboardTheme.textSecondary)
                            Text("•")
                                .foregroundColor(DashboardTheme.textMuted)
                            Text("Nhật ký: \(DashboardTheme.formatBytes(appCacheScan.appLogBytes))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(DashboardTheme.textSecondary)
                        }
                    }

                    Spacer()

                    Button {
                        Task { await cleanMyNotchCaches() }
                    } label: {
                        HStack(spacing: 6) {
                            if isCleaningAppCaches {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            Text("Dọn bộ nhớ đệm MyNotch")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(DashboardTheme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(DashboardTheme.controlBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(DashboardTheme.controlBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(internalTotal == 0 || isCleaningAppCaches)
                }
                .padding(12)
                .background(DashboardTheme.rowBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                // Card 3: RAM Memory Relief
                HStack(spacing: 14) {
                    Image(systemName: "memorychip")
                        .font(.system(size: 20))
                        .foregroundColor(DashboardTheme.hardwareCoral)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Giải phóng Bộ nhớ RAM Tiến trình")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(DashboardTheme.textPrimary)

                        HStack(spacing: 8) {
                            Text("Dung lượng thực (Footprint): \(DashboardTheme.formatBytes(Int64(memoryFootprintBytes)))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(DashboardTheme.textSecondary)
                            if let last = lastReclaimedBytes {
                                Text("•")
                                    .foregroundColor(DashboardTheme.textMuted)
                                Text(last > 0 ? "Đã trả \(DashboardTheme.formatBytes(Int64(last))) về OS" : "0 B trang trống (Heap đã gọn)")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(DashboardTheme.statusNormal)
                            }
                        }
                    }

                    Spacer()

                    Button {
                        Task { await relieveMemory() }
                    } label: {
                        HStack(spacing: 6) {
                            if isRelievingMemory {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            Text("Giải phóng RAM")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(DashboardTheme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(DashboardTheme.controlBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(DashboardTheme.controlBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isRelievingMemory)
                }
                .padding(12)
                .background(DashboardTheme.rowBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .dashboardCard()
    }

    // MARK: - Section 3: Rác Lập trình & Hệ thống macOS

    private var systemAndDeveloperSection: some View {
        let devCategories = storageCenter.categories(in: .developer)
        let systemCategories = storageCenter.categories(in: .system)
        let allScanned = devCategories + systemCategories

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                DashboardSectionHeader(
                    title: "Rác Lập trình & Hệ thống macOS",
                    subtitle: "Quét bộ nhớ đệm Xcode, SPM, package managers, tệp nhật ký và thùng rác"
                )

                Spacer()

                HStack(spacing: 6) {
                    Button("Chọn an toàn") {
                        selectDefaultSafeCategories(allScanned)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundColor(DashboardTheme.infoAccent)

                    Text("•").foregroundColor(DashboardTheme.textMuted)

                    Button("Bỏ chọn") {
                        selectedCategoryIDs.removeAll()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundColor(DashboardTheme.textSecondary)
                }
            }

            VStack(spacing: 8) {
                ForEach(allScanned) { category in
                    categoryRow(category)
                }
            }
        }
        .dashboardCard()
    }

    private func categoryRow(_ category: StorageCategory) -> some View {
        let isSelected = selectedCategoryIDs.contains(category.id)
        let canSelect = category.canClean && category.bytes > 0

        return HStack(spacing: 12) {
            Button {
                if canSelect {
                    if isSelected {
                        selectedCategoryIDs.remove(category.id)
                    } else {
                        selectedCategoryIDs.insert(category.id)
                    }
                }
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundColor(
                        canSelect ? (isSelected ? DashboardTheme.hardwareCoral : DashboardTheme.textMuted) : DashboardTheme.textMuted.opacity(0.4)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSelect)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(category.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(DashboardTheme.textPrimary)

                    if let caution = category.caution {
                        Text(caution)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DashboardTheme.hardwareCoral)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(DashboardTheme.hardwareCoral.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }

                    if category.needsFullDiskAccess {
                        Text("Thiếu quyền FDA")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(DashboardTheme.statusDegraded)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(DashboardTheme.statusDegraded.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                Text(displayPath(for: category.id))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(DashboardTheme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(DashboardTheme.formatBytes(category.bytes))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(category.bytes > 0 ? DashboardTheme.textPrimary : DashboardTheme.textMuted)

            Button {
                if category.caution != nil {
                    categoryToConfirm = category
                } else {
                    Task { await cleanSingleCategory(category) }
                }
            } label: {
                Text("Dọn")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DashboardTheme.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(DashboardTheme.controlBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(DashboardTheme.controlBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!category.canClean || category.bytes == 0 || isCleaningBatch)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? DashboardTheme.controlBackground.opacity(0.5) : DashboardTheme.rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - Section 4: Gỡ bỏ Ứng dụng & Dọn tệp thừa

    private var appUninstallerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            DashboardSectionHeader(
                title: "Gỡ bỏ Ứng dụng & Dọn tệp thừa",
                subtitle: "Kéo thả ứng dụng vào đây để quét sạch tệp rác thừa (Caches, Preferences, Application Support)"
            )

            if let cleaner = cleanerModule {
                uninstallerBody(cleaner.state)
            } else {
                Text("Phân hệ Cleaner hiện chưa được nạp.")
                    .font(.system(size: 12))
                    .foregroundColor(DashboardTheme.textMuted)
            }
        }
        .dashboardCard()
        .onDrop(of: [.fileURL, .applicationBundle, .application], isTargeted: $isDropTargeted) { providers in
            guard let cleaner = cleanerModule else { return false }
            switch cleaner.state.phase {
            case .analyzing, .deleting:
                return false
            default:
                return handleAppDrop(providers, state: cleaner.state)
            }
        }
    }

    @ViewBuilder
    private func uninstallerBody(_ state: CleanerState) -> some View {
        switch state.phase {
        case .idle:
            uninstallerDropZone(state)

        case .analyzing(let url):
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Đang phân tích tệp rác của \(url.deletingPathExtension().lastPathComponent)…")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(DashboardTheme.textSecondary)
                Spacer()
                Button("Huỷ") { state.reset() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
            }
            .padding(16)
            .background(DashboardTheme.insetBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))

        case .preview(let info, let residuals, let plan, let isRunning, let selectedIDs):
            uninstallerPreviewView(info: info, residuals: residuals, plan: plan, isRunning: isRunning, selectedIDs: selectedIDs, state: state)

        case .confirming(let info, let plan, let isRunning):
            uninstallerConfirmView(info: info, plan: plan, isRunning: isRunning, state: state)

        case .deleting(let appName):
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Đang gỡ bỏ và chuyển tệp rác của \(appName) vào Thùng rác…")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(DashboardTheme.textSecondary)
            }
            .padding(16)
            .background(DashboardTheme.insetBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))

        case .success(let appName, let freedBytes):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(DashboardTheme.statusNormal)
                        .font(.system(size: 16))
                    Text("Đã gỡ bỏ thành công \(appName)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DashboardTheme.textPrimary)
                    Spacer()
                    Text("Đã giải phóng \(DashboardTheme.formatBytes(freedBytes))")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(DashboardTheme.hardwareCoral)
                }

                HStack(spacing: 10) {
                    Button("Mở Thùng rác") {
                        if let trashURL = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first {
                            NSWorkspace.shared.open(trashURL)
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundColor(DashboardTheme.infoAccent)

                    Button("Gỡ ứng dụng khác") {
                        state.reset()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundColor(DashboardTheme.textSecondary)
                }
            }
            .padding(14)
            .background(DashboardTheme.insetBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))

        case .error(let message):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DashboardTheme.statusDegraded)
                    Text("Gỡ bỏ thất bại")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button("Thử lại") { state.reset() }
                        .font(.system(size: 11))
                        .buttonStyle(.plain)
                }
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundColor(DashboardTheme.textSecondary)
            }
            .padding(14)
            .background(DashboardTheme.insetBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func uninstallerDropZone(_ state: CleanerState) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 26))
                .foregroundColor(isDropTargeted ? DashboardTheme.hardwareCoral : DashboardTheme.textMuted)

            Text("Kéo và thả tệp .app vào đây để gỡ bỏ hoàn toàn")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(DashboardTheme.textSecondary)

            Button {
                chooseAppFromDisk(state)
            } label: {
                Text("Chọn ứng dụng (.app)…")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(DashboardTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(DashboardTheme.controlBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(DashboardTheme.controlBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? DashboardTheme.hardwareCoral : DashboardTheme.insetBorder,
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DashboardTheme.insetBackground)
                )
        )
    }

    private func uninstallerPreviewView(
        info: AppBundleInfo,
        residuals: [Residual],
        plan: DeletionPlan,
        isRunning: Bool,
        selectedIDs: Set<String>,
        state: CleanerState
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // App Header
            HStack(spacing: 12) {
                let icon = NSWorkspace.shared.icon(forFile: info.url.path)
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(info.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DashboardTheme.textPrimary)
                        Text(info.version)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(DashboardTheme.textMuted)
                    }
                    Text(info.bundleID)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(DashboardTheme.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(DashboardTheme.formatBytes(plan.totalBytes))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(DashboardTheme.hardwareCoral)
                    Text("Tổng tệp thừa")
                        .font(.system(size: 10))
                        .foregroundColor(DashboardTheme.textMuted)
                }
            }

            if isRunning {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(DashboardTheme.hardwareCoral)
                    Text("Ứng dụng đang chạy. Vui lòng đóng ứng dụng hoàn toàn trước khi gỡ bỏ.")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(DashboardTheme.hardwareCoral)
                }
                .padding(8)
                .background(DashboardTheme.hardwareCoral.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }

            // Residual Items List
            VStack(spacing: 6) {
                ForEach(residuals) { res in
                    let isChecked = selectedIDs.contains(res.id)
                    let isSelectable = !res.locked && !res.deniedFDA

                    HStack(spacing: 10) {
                        Button {
                            if isSelectable { state.toggleResidual(id: res.id) }
                        } label: {
                            Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                                .font(.system(size: 13))
                                .foregroundColor(isSelectable ? (isChecked ? DashboardTheme.hardwareCoral : DashboardTheme.textMuted) : DashboardTheme.textMuted.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                        .disabled(!isSelectable)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(res.url.lastPathComponent)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(DashboardTheme.textPrimary)
                            Text(res.note ?? res.url.deletingLastPathComponent().path)
                                .font(.system(size: 9.5))
                                .foregroundColor(DashboardTheme.textSecondary)
                        }

                        Spacer()

                        Text(DashboardTheme.formatBytes(res.bytes))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(DashboardTheme.textSecondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(DashboardTheme.rowBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            // Bottom Actions
            HStack {
                Button("Huỷ") { state.reset() }
                    .font(.system(size: 11.5))
                    .buttonStyle(.plain)
                    .foregroundColor(DashboardTheme.textSecondary)

                Spacer()

                Button {
                    state.proceedToConfirmation()
                } label: {
                    Text("Tiếp tục gỡ bỏ…")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(Color.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(DashboardTheme.hardwareCoral)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .disabled(isRunning || plan.items.isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(DashboardTheme.insetBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func uninstallerConfirmView(
        info: AppBundleInfo,
        plan: DeletionPlan,
        isRunning: Bool,
        state: CleanerState
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(DashboardTheme.hardwareCoral)
                    .font(.system(size: 16))
                Text("Xác nhận gỡ bỏ \(info.displayName)?")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(DashboardTheme.textPrimary)
            }

            Text("Hành động này sẽ chuyển \(plan.items.count) mục (\(DashboardTheme.formatBytes(plan.totalBytes))) bao gồm ứng dụng và toàn bộ dữ liệu tạm thời vào Thùng rác.")
                .font(.system(size: 12))
                .foregroundColor(DashboardTheme.textSecondary)

            HStack {
                Button("Quay lại") {
                    state.backToPreview()
                }
                .font(.system(size: 11.5))
                .buttonStyle(.plain)

                Spacer()

                Button {
                    state.executeUninstall()
                } label: {
                    Text("Chuyển vào Thùng rác")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(Color.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(DashboardTheme.hardwareCoral)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .disabled(isRunning)
            }
        }
        .padding(14)
        .background(DashboardTheme.insetBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Actions & Helpers

    private func refreshAll(silent: Bool) async {
        isScanning = true
        defer { isScanning = false }

        await storageCenter.refresh()
        appCacheScan = await MyNotchResourceCleaner.scanAppCachesAndLogs()
        memoryFootprintBytes = MyNotchResourceCleaner.defaultMemoryFootprint()

        let allScanned = storageCenter.categories(in: .developer) + storageCenter.categories(in: .system)
        if selectedCategoryIDs.isEmpty {
            selectDefaultSafeCategories(allScanned)
        }

        if !silent {
            toastCenter.show(message: "Đã hoàn tất quét bộ nhớ hệ thống", systemImage: "checkmark.circle.fill")
        }
    }

    private func selectDefaultSafeCategories(_ categories: [StorageCategory]) {
        let safeIDs = MyNotchResourceCleaner.defaultSafeSelectedIDs(categories: categories)
        selectedCategoryIDs = safeIDs
    }

    private func calculateSafeSelectedBytes() -> Int64 {
        let allScanned = storageCenter.categories(in: .developer) + storageCenter.categories(in: .system)
        return allScanned.filter { selectedCategoryIDs.contains($0.id) }.reduce(0) { $0 + $1.bytes }
    }

    private func cleanSelectedBatch() async {
        isCleaningBatch = true
        defer { isCleaningBatch = false }

        let freed = await storageCenter.cleanCategories(selectedCategoryIDs)
        selectedCategoryIDs.removeAll()
        await refreshAll(silent: true)

        toastCenter.show(
            message: "Đã dọn dẹp an toàn: giải phóng \(DashboardTheme.formatBytes(freed))",
            systemImage: "trash.fill"
        )
    }

    private func cleanSingleCategory(_ category: StorageCategory) async {
        isCleaningBatch = true
        defer { isCleaningBatch = false }

        let freed = await storageCenter.clean(category.id)
        selectedCategoryIDs.remove(category.id)
        await refreshAll(silent: true)

        toastCenter.show(
            message: "Đã dọn \"\(category.title)\": giải phóng \(DashboardTheme.formatBytes(freed))",
            systemImage: "trash"
        )
    }

    private func purgeClipboardHistory() async {
        guard let clipboard = clipboardModule else { return }
        isPurgingClipboard = true
        defer { isPurgingClipboard = false }

        let storage = registry.storage(for: "clipboard")
        let report = await clipboard.purgeUnpinnedAndOrphans(storage: storage)
        await refreshAll(silent: true)

        toastCenter.show(
            message: "Clipboard: đã dọn \(report.removedItems) mục, giải phóng \(DashboardTheme.formatBytes(report.freedBytes))",
            systemImage: "doc.on.clipboard"
        )
    }

    private func cleanMyNotchCaches() async {
        isCleaningAppCaches = true
        defer { isCleaningAppCaches = false }

        let moduleFreed = await storageCenter.cleanAll()
        let appFreed = await MyNotchResourceCleaner.cleanAppCachesAndLogs()
        let total = moduleFreed + appFreed

        await refreshAll(silent: true)

        toastCenter.show(
            message: "Đã dọn bộ nhớ đệm MyNotch: giải phóng \(DashboardTheme.formatBytes(total))",
            systemImage: "shippingbox"
        )
    }

    private func relieveMemory() async {
        isRelievingMemory = true
        defer { isRelievingMemory = false }

        let report = await MyNotchResourceCleaner.relieveProcessMemory()
        lastReclaimedBytes = report.reclaimedZoneBytes
        memoryFootprintBytes = report.footprintAfterBytes

        if report.reclaimedZoneBytes > 0 {
            toastCenter.show(
                message: "Đã giải phóng \(DashboardTheme.formatBytes(Int64(report.reclaimedZoneBytes))) RAM về hệ điều hành",
                systemImage: "memorychip"
            )
        } else {
            toastCenter.show(
                message: "Heap tiến trình đã tối ưu gọn gàng (0 B trang thừa)",
                systemImage: "checkmark.circle"
            )
        }
    }

    private func chooseAppFromDisk(_ state: CleanerState) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle, .application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            state.analyze(appURL: url.standardized)
        }
    }

    private func handleAppDrop(_ providers: [NSItemProvider], state: CleanerState) -> Bool {
        if let urls = NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let appURL = urls.first(where: { DropRouting.isApplicationURL($0) }) {
            state.analyze(appURL: appURL.standardized)
            return true
        }

        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let rawURL = url else { return }
            let appURL = rawURL.standardized
            guard DropRouting.isApplicationURL(appURL) else { return }
            Task { @MainActor in
                state.analyze(appURL: appURL)
            }
        }
        return true
    }
}
