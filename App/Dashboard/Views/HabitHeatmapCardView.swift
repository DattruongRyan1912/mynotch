import HabitModule
import MyNotchCore
import SwiftUI

/// Card hiển thị một Thói Quen kèm lưới đóng góp HabitHeatmap dựng bằng Canvas hiệu năng cao (120Hz).
struct HabitHeatmapCardView: View, Equatable {
    let habit: Habit
    let snapshot: HabitHeatmapSnapshot
    let palette: HabitColorPalette
    let onToggleToday: () -> Void
    let onToggleDay: (DayKey) -> Void
    let onDelete: () -> Void

    static func == (lhs: HabitHeatmapCardView, rhs: HabitHeatmapCardView) -> Bool {
        lhs.habit.id == rhs.habit.id &&
        lhs.habit.title == rhs.habit.title &&
        lhs.snapshot == rhs.snapshot &&
        lhs.palette == rhs.palette
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // MARK: - Header
            HStack(alignment: .center, spacing: 10) {
                // Color Badge Dot
                Circle()
                    .fill(palette.color)
                    .frame(width: 10, height: 10)

                // Title
                Text(habit.title)
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundColor(DashboardTheme.textPrimary)

                // Streak Badge
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10))
                    Text("\(snapshot.currentStreak) ngày streak")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                }
                .foregroundColor(snapshot.currentStreak > 0 ? palette.color : DashboardTheme.textMuted)
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(palette.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 4))

                // Total Completions
                Text("\(snapshot.totalCompletions) lần hoàn thành")
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(DashboardTheme.textSecondary)

                Spacer()

                // Quick Toggle Today Button
                Button(action: onToggleToday) {
                    HStack(spacing: 5) {
                        Image(systemName: snapshot.isDoneToday ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12))
                        Text(snapshot.isDoneToday ? "Đã xong hôm nay" : "Đánh dấu hôm nay")
                            .font(.system(size: 11.5, weight: snapshot.isDoneToday ? .semibold : .medium))
                    }
                    .foregroundColor(snapshot.isDoneToday ? Color.white : DashboardTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4.5)
                    .background(snapshot.isDoneToday ? palette.color : DashboardTheme.controlBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(snapshot.isDoneToday ? palette.color : DashboardTheme.controlBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                // Delete Button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(DashboardTheme.textMuted)
                        .padding(5)
                }
                .buttonStyle(.plain)
                .help("Xóa thói quen '\(habit.title)'")
            }

            Rectangle()
                .fill(DashboardTheme.separator)
                .frame(height: 1)

            // MARK: - Canvas Heatmap
            VStack(alignment: .leading, spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HabitHeatmapCanvas(
                        weeks: snapshot.weeks,
                        palette: HabitCanvasPalette.from(palette: palette),
                        onSelectDay: onToggleDay
                    )
                    .padding(.vertical, 4)
                }

                // MARK: - Footer (Stats & Legend)
                HStack {
                    Text("Tỷ lệ kỷ luật trong năm: \(snapshot.completionRate)%")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DashboardTheme.textMuted)

                    Spacer()

                    HStack(spacing: 4) {
                        Text("Ít")
                            .font(.system(size: 9.5))
                            .foregroundColor(DashboardTheme.textMuted)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(red: 235/255, green: 238/255, blue: 242/255))
                            .frame(width: 10, height: 10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Color(red: 226/255, green: 232/255, blue: 240/255), lineWidth: 0.75)
                            )

                        RoundedRectangle(cornerRadius: 2)
                            .fill(palette.color.opacity(0.35))
                            .frame(width: 10, height: 10)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(palette.color.opacity(0.65))
                            .frame(width: 10, height: 10)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(palette.color)
                            .frame(width: 10, height: 10)

                        Text("Nhiều")
                            .font(.system(size: 9.5))
                            .foregroundColor(DashboardTheme.textMuted)
                    }
                }
                .padding(.top, 4)
            }
        }
        .dashboardCard()
    }
}
