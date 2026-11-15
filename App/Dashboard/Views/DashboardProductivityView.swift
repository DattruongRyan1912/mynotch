import HabitModule
import MyNotchCore
import SwiftUI

struct DashboardProductivityView: View {
    let telemetry: DashboardTelemetryCenter
    let registry: ModuleRegistry

    @ObservedObject private var themeStore = DashboardThemeStore.shared
    @State private var newHabitTitle: String = ""
    @State private var snapshotCache = HabitHeatmapSnapshotCache()

    private var habitModule: HabitModule? {
        registry.module(for: "habit") as? HabitModule
    }

    private var habits: [Habit] {
        habitModule?.state.habits ?? []
    }

    private var today: DayKey {
        habitModule?.state.today ?? DayKey(date: .now)
    }

    private var calendar: Calendar {
        habitModule?.state.calendar ?? .autoupdatingCurrent
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                // Section 1: Quick Add Habit Bar (Elevated to top)
                quickAddHabitSection

                // Section 2: Habits List with Individual GitHub Heatmap Grids
                if habits.isEmpty {
                    emptyHabitState
                } else {
                    habitsListSection
                }

                // Section 3: Calendar & Agenda (EventKit macOS)
                calendarDetailedSection
            }
            .padding(20)
        }
        .background(DashboardTheme.canvasBackground)
    }

    // MARK: - Quick Add Section

    private var quickAddHabitSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .foregroundColor(DashboardTheme.infoAccent)

            TextField(
                "",
                text: $newHabitTitle,
                prompt: Text("Thêm thói quen mới: Đọc sách 30 phút, Chạy bộ 5km, Uống 2L nước, Học tiếng Anh...")
                    .foregroundColor(DashboardTheme.textMuted)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .onSubmit {
                submitNewHabit()
            }

            if !newHabitTitle.isEmpty {
                Button("Thêm") {
                    submitNewHabit()
                }
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(DashboardTheme.infoAccent)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(DashboardTheme.controlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(DashboardTheme.controlBorder, lineWidth: 1))
    }

    private func submitNewHabit() {
        let trimmed = newHabitTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        newHabitTitle = ""
        if let module = habitModule {
            _ = module.state.addHabit(title: trimmed)
            module.save()
            DashboardToastCenter.shared.show(message: "Đã thêm thói quen: '\(trimmed)'")
        }
    }

    // MARK: - Habits List & Heatmaps

    private var emptyHabitState: some View {
        VStack(spacing: 8) {
            Image(systemName: "flame")
                .font(.system(size: 30))
                .foregroundColor(DashboardTheme.textMuted.opacity(0.6))
            Text("Chưa có thói quen nào")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DashboardTheme.textPrimary)
            Text("Hãy nhập mục tiêu thói quen vào ô phía trên để bắt đầu theo dõi bảng đóng góp hằng ngày.")
                .font(.system(size: 12))
                .foregroundColor(DashboardTheme.textMuted)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .dashboardCard()
    }

    private var habitsListSection: some View {
        LazyVStack(spacing: 16) {
            ForEach(Array(habits.enumerated()), id: \.element.id) { index, habit in
                let palette = HabitColorPalette.palette(for: index)
                let snapshot = snapshotCache.snapshot(
                    habit: habit,
                    today: today,
                    calendar: calendar,
                    paletteIndex: index
                )
                HabitHeatmapCardView(
                    habit: habit,
                    snapshot: snapshot,
                    palette: palette,
                    onToggleToday: {
                        toggleHabitToday(habit)
                    },
                    onToggleDay: { dayKey in
                        toggleHabitDay(habit, dayKey: dayKey)
                    },
                    onDelete: {
                        deleteHabit(habit)
                    }
                )
            }
        }
        .onAppear {
            snapshotCache.prune(keeping: Set(habits.map(\.id)))
        }
    }

    // MARK: - Operations

    private func toggleHabitToday(_ habit: Habit) {
        if let module = habitModule {
            module.state.toggleToday(id: habit.id)
            module.save()
            let isNowDone = module.state.habits.first(where: { $0.id == habit.id })?.isCompleted(on: today) == true
            DashboardToastCenter.shared.show(
                message: isNowDone ? "Đã hoàn thành '\(habit.title)' hôm nay!" : "Đã hủy hoàn thành '\(habit.title)' hôm nay."
            )
        }
    }

    private func toggleHabitDay(_ habit: Habit, dayKey: DayKey) {
        if let module = habitModule {
            module.state.toggle(id: habit.id, on: dayKey)
            module.save()
            let isNowDone = module.state.habits.first(where: { $0.id == habit.id })?.isCompleted(on: dayKey) == true
            DashboardToastCenter.shared.show(
                message: "\(isNowDone ? "Đã đánh dấu xong" : "Đã hủy đánh dấu") ngày \(dayKey.rawValue) cho '\(habit.title)'"
            )
        }
    }

    private func deleteHabit(_ habit: Habit) {
        if let module = habitModule {
            module.state.deleteHabit(id: habit.id)
            module.save()
            DashboardToastCenter.shared.show(message: "Đã xóa thói quen '\(habit.title)'.")
        }
    }

    // MARK: - Calendar Section

    private var calendarDetailedSection: some View {
        let snap = telemetry.calendarSnapshot
        let todayCount = snap?.metric(named: "Sự kiện")?.value.displayString ?? "0"
        let nextTitle = snap?.metric(named: "Sắp tới")?.value.displayString ?? "Không có"

        return VStack(alignment: .leading, spacing: 14) {
            DashboardSectionHeader(
                title: "Lịch Trình & Lịch Hẹn Sự Kiện",
                subtitle: "Đồng bộ hóa trực tiếp từ Apple EventKit macOS"
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SỰ KIỆN TRONG NGÀY")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(DashboardTheme.textMuted)
                        Text("\(todayCount) sự kiện")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(DashboardTheme.textPrimary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("SẮP DIỄN RA")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(DashboardTheme.textMuted)
                        Text(nextTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(DashboardTheme.textPrimary)
                    }
                }
            }
        }
        .dashboardCard()
    }
}
