import MyNotchCore
import SwiftUI
import TodoModule

/// Dedicated full-screen workspace for Todo Management, Eisenhower Matrix & Rollover Archive.
/// Directly wired to TodoModule and EventKit backend reminders.
struct DashboardTodoStudioView: View {
    let telemetry: DashboardTelemetryCenter
    let registry: ModuleRegistry
    @ObservedObject private var themeStore = DashboardThemeStore.shared

    @State private var viewMode: Int = 0 // 0: Matrix 4x4, 1: Flat List
    @State private var searchQuery: String = ""
    @State private var selectedTag: String = "Tất cả"
    @State private var showArchiveDrawer: Bool = false
    @State private var showPassedTasksSection: Bool = true
    @State private var onlyActiveTasks: Bool = false
    @State private var quickAddDrafts = TodoStudioQuickAddDrafts()

    private var todoModule: TodoModule? {
        registry.module(for: "todo") as? TodoModule
    }

    // Archived tasks from previous days (Rolled over at midnight from EventKit)
    @State private var archivedTasks: [TodoStudioItem] = []

    private var currentTasks: [TodoStudioItem] {
        todoModule?.studioTasks ?? []
    }

    private var passedTodayTasks: [TodoStudioItem] {
        currentTasks.filter { $0.isCompleted }
    }

    private var availableTags: [String] {
        var tags = Set<String>(["Tất cả"])
        for task in currentTasks {
            for tag in task.tags {
                tags.insert(tag)
            }
        }
        return Array(tags).sorted()
    }

    private var filteredTasks: [TodoStudioItem] {
        currentTasks.filter { task in
            let matchesSearch = searchQuery.isEmpty || task.title.localizedCaseInsensitiveContains(searchQuery)
            let matchesTag = selectedTag == "Tất cả" || task.tags.contains(selectedTag)
            let matchesActive = !onlyActiveTasks || !task.isCompleted
            return matchesSearch && matchesTag && matchesActive
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                // Permission Warning Banner
                if let module = todoModule, !module.hasRemindersAccess {
                    permissionBanner
                }

                // Filter & Search Toolbar
                toolbarSection

                // Quick Add Input Bar
                quickAddSection

                // Main Content View (Matrix vs List)
                if viewMode == 0 {
                    matrixQuadrantsGrid
                } else {
                    flatListView
                }

                // Passed Tasks Section (Tasks completed today with quick quadrant restore)
                passedTasksSection

                // Archive Section (Rollover from previous days)
                archiveHistorySection

            }
            .padding(24)
        }
        .background(DashboardTheme.canvasBackground)
        .task {
            if let module = todoModule {
                if !module.hasRemindersAccess {
                    await module.requestAccess()
                }
                let list = await module.fetchArchivedTasks()
                await MainActor.run {
                    self.archivedTasks = list
                }
            }
        }
    }

    private var permissionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(DashboardTheme.statusDegraded)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 2) {
                Text("Chưa cấp quyền Apple Reminders")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(DashboardTheme.textPrimary)
                Text("Vui lòng cấp quyền Lời nhắc để MyNotch đồng bộ công việc thực tế của bạn.")
                    .font(.system(size: 11.5))
                    .foregroundColor(DashboardTheme.textSecondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button("Cấp Quyền") {
                    Task {
                        await todoModule?.requestAccess()
                    }
                }
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(DashboardTheme.infoAccent)

                Button("Cài Đặt") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.system(size: 11.5, weight: .regular))
                .foregroundColor(DashboardTheme.textSecondary)
            }
        }
        .padding(14)
        .dashboardCard()
    }

    // MARK: - Toolbar Section

    private var toolbarSection: some View {
        HStack(spacing: 12) {
            // Search Input
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(DashboardTheme.textMuted)
                TextField(
                    "",
                    text: $searchQuery,
                    prompt: Text("Tìm kiếm công việc...").foregroundColor(DashboardTheme.textMuted)
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(DashboardTheme.controlBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(DashboardTheme.controlBorder, lineWidth: 1))
            .frame(width: 240)

            // Tag Filter Chips
            HStack(spacing: 6) {
                ForEach(availableTags, id: \.self) { tag in
                    Button(action: { selectedTag = tag }) {
                        Text(tag)
                            .font(.system(size: 11.5, weight: selectedTag == tag ? .semibold : .medium))
                            .foregroundColor(selectedTag == tag ? Color.white : DashboardTheme.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(selectedTag == tag ? DashboardTheme.infoAccent : DashboardTheme.controlBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(selectedTag == tag ? DashboardTheme.infoAccent : DashboardTheme.controlBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Active Only Filter Toggle
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    onlyActiveTasks.toggle()
                }
            }) {
                HStack(spacing: 5) {
                    Image(systemName: onlyActiveTasks ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    Text(onlyActiveTasks ? "Chỉ việc đang làm" : "Hiện tất cả việc")
                }
                .font(.system(size: 11.5, weight: onlyActiveTasks ? .semibold : .medium))
                .foregroundColor(onlyActiveTasks ? DashboardTheme.infoAccent : DashboardTheme.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(onlyActiveTasks ? DashboardTheme.infoAccent.opacity(0.12) : DashboardTheme.controlBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(onlyActiveTasks ? DashboardTheme.infoAccent.opacity(0.4) : DashboardTheme.controlBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("Ẩn hoặc hiện các việc đã gạch ngang trong bảng ma trận")

            // View Mode Buttons (Matrix vs List)
            HStack(spacing: 2) {
                Button(action: { viewMode = 0 }) {
                    HStack(spacing: 5) {
                        Image(systemName: "square.grid.2x2")
                        Text("Ma Trận Q1-Q4")
                    }
                    .font(.system(size: 11.5, weight: viewMode == 0 ? .semibold : .medium))
                    .foregroundColor(viewMode == 0 ? DashboardTheme.textPrimary : DashboardTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(viewMode == 0 ? DashboardTheme.controlBackground : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)

                Button(action: { viewMode = 1 }) {
                    HStack(spacing: 5) {
                        Image(systemName: "list.bullet")
                        Text("Danh Sách")
                    }
                    .font(.system(size: 11.5, weight: viewMode == 1 ? .semibold : .medium))
                    .foregroundColor(viewMode == 1 ? DashboardTheme.textPrimary : DashboardTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(viewMode == 1 ? DashboardTheme.controlBackground : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
            .padding(2)
            .background(DashboardTheme.segmentTrackBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Matrix Theme Bridge

    private var studioMatrixTheme: TodoStudioMatrixTheme {
        TodoStudioMatrixTheme(
            cardBackground: DashboardTheme.cardBackground,
            cardBorder: DashboardTheme.hairlineBorder,
            insetBackground: DashboardTheme.insetBackground,
            insetBorder: DashboardTheme.insetBorder,
            separator: DashboardTheme.separator,
            textPrimary: DashboardTheme.textPrimary,
            textSecondary: DashboardTheme.textSecondary,
            textMuted: DashboardTheme.textMuted,
            infoAccent: DashboardTheme.infoAccent,
            statusCritical: DashboardTheme.statusCritical,
            statusNeutral: DashboardTheme.statusNeutral,
            hardwareCoral: DashboardTheme.hardwareCoral,
            controlBorder: DashboardTheme.controlBorder,
            cornerRadius: DashboardTheme.cardCornerRadius
        )
    }

    // MARK: - Quick Add Section

    private var quickAddSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .foregroundColor(DashboardTheme.infoAccent)

            TextField(
                "",
                text: $quickAddDrafts.toolbarDraft,
                prompt: Text("Thêm việc nhanh: [Nội dung] [!1..4 độ ưu tiên] [HH:mm giờ] (VD: Kiểm tra phát hành MyNotch !1 10:00)...")
                    .foregroundColor(DashboardTheme.textMuted)
            )
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .onSubmit {
                    submitQuickTask()
                }

            if !quickAddDrafts.toolbarDraft.isEmpty {
                Button("Thêm") {
                    submitQuickTask()
                }
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(DashboardTheme.infoAccent)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DashboardTheme.controlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(DashboardTheme.controlBorder, lineWidth: 1))
    }

    private func submitQuickTask() {
        guard let submission = quickAddDrafts.consumeToolbarSubmission() else { return }
        Task {
            if let module = todoModule {
                let added = await module.addTask(submission.formattedCommand)
                if added {
                    await module.refreshTasks()
                    triggerNotice("Đã lưu vào Reminders: \(submission.rawDraft)", systemImage: "tray.and.arrow.down.fill")
                } else {
                    await MainActor.run {
                        quickAddDrafts.restoreToolbarDraftIfEmpty(submission.rawDraft)
                        triggerNotice("Không thể lưu công việc (kiểm tra quyền Reminders).", systemImage: "exclamationmark.triangle")
                    }
                }
            } else {
                await MainActor.run {
                    quickAddDrafts.restoreToolbarDraftIfEmpty(submission.rawDraft)
                    triggerNotice("Chưa tải được TodoModule.", systemImage: "exclamationmark.triangle")
                }
            }
        }
    }

    // MARK: - Eisenhower Matrix 4 Quadrants Grid

    private var matrixQuadrantsGrid: some View {
        TodoStudioMatrixGrid(
            tasks: filteredTasks,
            theme: studioMatrixTheme,
            drafts: $quickAddDrafts,
            onTaskToggle: { handleToggleTask($0) },
            onTaskMove: { handleMoveTask($0, toQuadrant: $1) },
            onSubmitQuadrantDraft: { handleAddQuadrantDraft($0) }
        )
    }

    // MARK: - Flat List View

    private var flatListView: some View {
        VStack(spacing: 8) {
            ForEach(filteredTasks) { task in
                TodoStudioTaskRowView(
                    task: task,
                    theme: studioMatrixTheme,
                    showsQuadrantBadge: true,
                    onToggle: { handleToggleTask(task) },
                    onMove: { handleMoveTask(task.id, toQuadrant: $0) }
                )
            }
        }
        .dashboardCard()
    }

    // MARK: - Passed Tasks Section (Tasks completed today, with quick quadrant restore)

    private var passedTasksSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            DashboardSectionHeader(
                title: "Công Việc Đã Hoàn Thành Hôm Nay (Passed Tasks)",
                subtitle: "Xem lại và hoàn tác hoặc khôi phục trực tiếp vào các góc Q1–Q4 nếu lỡ chạm nhầm",
                actionTitle: showPassedTasksSection ? "Thu gọn (\(passedTodayTasks.count))" : "Mở rộng (\(passedTodayTasks.count))",
                action: {
                    withAnimation { showPassedTasksSection.toggle() }
                }
            )

            if showPassedTasksSection {
                if passedTodayTasks.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 22))
                            .foregroundColor(DashboardTheme.textMuted.opacity(0.6))
                        Text("Chưa có công việc nào hoàn thành hôm nay")
                            .font(.system(size: 12))
                            .foregroundColor(DashboardTheme.textMuted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 70)
                    .dashboardCard()
                } else {
                    VStack(spacing: 8) {
                        ForEach(passedTodayTasks) { task in
                            passedTaskRow(task: task)
                        }
                    }
                    .dashboardCard()
                }
            }
        }
    }

    private func passedTaskRow(task: TodoStudioItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(DashboardTheme.statusNormal)
                .font(.system(size: 15))

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .strikethrough(true, color: DashboardTheme.textMuted)
                    .foregroundColor(DashboardTheme.textSecondary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text("Gốc: Q\(task.quadrant)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(DashboardTheme.infoAccent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(DashboardTheme.infoAccent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    ForEach(task.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 10))
                            .foregroundColor(DashboardTheme.textMuted)
                    }

                    if let deadline = task.deadline {
                        Text("• \(deadline)")
                            .font(.system(size: 10))
                            .foregroundColor(DashboardTheme.hardwareCoral)
                    }
                }
            }

            Spacer()

            // Undo / Restore Controls
            HStack(spacing: 6) {
                Button(action: {
                    handleUndoTask(task)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Hoàn tác")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(DashboardTheme.infoAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DashboardTheme.infoAccent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Hủy đánh dấu hoàn thành, đưa công việc trở lại góc Q\(task.quadrant)")

                // Quick restore to specific quadrant
                HStack(spacing: 3) {
                    ForEach(1...4, id: \.self) { targetQ in
                        Button("Về Q\(targetQ)") {
                            handleRestoreToQuadrant(task, quadrant: targetQ)
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(targetQ == task.quadrant ? DashboardTheme.textPrimary : DashboardTheme.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(DashboardTheme.chipBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .buttonStyle(.plain)
                        .help("Khôi phục và đưa thẳng vào góc Q\(targetQ)")
                    }
                }
            }
        }
        .padding(9)
        .background(DashboardTheme.rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(DashboardTheme.hairlineBorder, lineWidth: 1))
    }

    // MARK: - Archive & Rollover History Section

    private var archiveHistorySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            DashboardSectionHeader(
                title: "Kho Lưu Trữ Công Việc (Daily Rollover Archive)",
                subtitle: "Tự động lưu trữ các việc đã hoàn thành của những ngày trước đó lúc 00:00",
                actionTitle: showArchiveDrawer ? "Thu gọn kho" : "Mở xem lịch sử (\(archivedTasks.count))",
                action: {
                    withAnimation { showArchiveDrawer.toggle() }
                }
            )

            if showArchiveDrawer {
                if archivedTasks.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "archivebox")
                            .font(.system(size: 26))
                            .foregroundColor(DashboardTheme.textMuted.opacity(0.6))
                        Text("Kho lưu trữ trống")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(DashboardTheme.textPrimary)
                        Text("Các công việc hoàn thành trước hôm nay sẽ tự động được chuyển vào đây khi bước sang ngày mới.")
                            .font(.system(size: 11.5))
                            .foregroundColor(DashboardTheme.textMuted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .dashboardCard()
                } else {
                    VStack(spacing: 8) {
                        ForEach(archivedTasks) { task in
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(DashboardTheme.statusNormal)
                                    .font(.system(size: 14))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                        .font(.system(size: 12.5, weight: .medium))
                                        .strikethrough(true, color: DashboardTheme.textMuted)
                                        .foregroundColor(DashboardTheme.textSecondary)

                                    HStack(spacing: 6) {
                                        Text("Góc: Q\(task.quadrant)")
                                            .font(.system(size: 10.5, weight: .semibold))
                                            .foregroundColor(DashboardTheme.infoAccent)
                                        if let deadline = task.deadline {
                                            Text("•  Hoàn thành: \(deadline)")
                                                .font(.system(size: 10.5))
                                                .foregroundColor(DashboardTheme.textMuted)
                                        }
                                    }
                                }

                                Spacer()

                                Button("Khôi phục lại") {
                                    restoreArchivedTask(task.id)
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(DashboardTheme.infoAccent)
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(DashboardTheme.rowBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(DashboardTheme.hairlineBorder, lineWidth: 1))
                        }
                    }
                    .dashboardCard()
                }
            }
        }
    }

    // MARK: - Real Module Operations

    private func handleToggleTask(_ task: TodoStudioItem) {
        if let module = todoModule {
            Task {
                if task.isCompleted {
                    await module.undoTask(task.id)
                    triggerNotice("Đã hoàn tác: '\(task.title)'.")
                } else {
                    await module.completeTask(task.id)
                    triggerNotice("Đã hoàn thành: '\(task.title)' (giữ hiển thị đến hết ngày).")
                }
                await module.refreshTasks()
            }
        }
    }

    private func handleUndoTask(_ task: TodoStudioItem) {
        if let module = todoModule {
            Task {
                await module.undoTask(task.id)
                await module.refreshTasks()
                triggerNotice("Đã khôi phục '\(task.title)' về góc Q\(task.quadrant).")
            }
        }
    }

    private func handleRestoreToQuadrant(_ task: TodoStudioItem, quadrant: Int) {
        if let module = todoModule {
            Task {
                await module.undoTask(task.id)
                if task.quadrant != quadrant {
                    await module.moveTask(task.id, toQuadrant: quadrant)
                }
                await module.refreshTasks()
                triggerNotice("Đã hoàn tác và đưa '\(task.title)' về góc Q\(quadrant).")
            }
        }
    }

    private func handleMoveTask(_ id: String, toQuadrant newQ: Int) {
        if let module = todoModule {
            Task {
                await module.moveTask(id, toQuadrant: newQ)
                await module.refreshTasks()
                triggerNotice("Đã chuyển công việc sang Q\(newQ).")
            }
        }
    }

    private func handleAddQuadrantDraft(_ quadrant: Int) {
        guard let submission = quickAddDrafts.consumeSubmission(forQuadrant: quadrant) else { return }

        if let module = todoModule {
            Task {
                let added = await module.addTask(submission.formattedCommand)
                if added {
                    await module.refreshTasks()
                    await MainActor.run {
                        triggerNotice("Đã lưu công việc vào EventKit Q\(quadrant).")
                    }
                } else {
                    await MainActor.run {
                        quickAddDrafts.restoreDraftIfEmpty(submission.rawDraft, forQuadrant: quadrant)
                        triggerNotice("Không thể lưu công việc (kiểm tra quyền Reminders).", systemImage: "exclamationmark.triangle")
                    }
                }
            }
        } else {
            quickAddDrafts.restoreDraftIfEmpty(submission.rawDraft, forQuadrant: quadrant)
            triggerNotice("Chưa tải được TodoModule.", systemImage: "exclamationmark.triangle")
        }
    }

    private func restoreArchivedTask(_ id: String) {
        guard let index = archivedTasks.firstIndex(where: { $0.id == id }) else { return }
        let task = archivedTasks[index]
        if let module = todoModule {
            Task {
                await module.undoTask(task.id)
                await module.refreshTasks()
                let reloaded = await module.fetchArchivedTasks()
                await MainActor.run {
                    self.archivedTasks = reloaded
                    triggerNotice("Đã khôi phục '\(task.title)' về bảng việc hôm nay.")
                }
            }
        }
    }

    private func triggerNotice(_ text: String, systemImage: String = "checkmark.circle.fill") {
        DashboardToastCenter.shared.show(message: text, systemImage: systemImage)
    }
}
