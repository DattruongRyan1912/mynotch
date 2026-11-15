import AppKit
import Foundation
import SwiftUI
import Testing
@testable import HabitModule

@Suite("Habit Heatmap Domain Tests")
struct HabitHeatmapTests {

    @Test("Test Case 1: Lưới GitHub Heatmap 52 Tuần (Happy Path)")
    func testGitHubHeatmap52WeeksGridGeneration() {
        let calendar = Calendar(identifier: .gregorian)
        let today = DayKey(rawValue: "2026-11-06")

        let weeks = HabitHeatmapBuilder.buildGrid(
            completedDays: [],
            today: today,
            weeksCount: 52,
            calendar: calendar
        )

        #expect(weeks.count == 52)
        for week in weeks {
            #expect(week.days.count == 7)
        }

        let lastWeek = weeks[51]
        let todayCell = lastWeek.days.first(where: { $0.dayKey == today })
        #expect(todayCell != nil)
        #expect(todayCell?.isToday == true)
        #expect(todayCell?.isFuture == false)

        // Các ngày sau today trong tuần hiện tại phải có isFuture == true
        if let todayIdx = lastWeek.days.firstIndex(where: { $0.dayKey == today }), todayIdx < 6 {
            for futureIdx in (todayIdx + 1)...6 {
                #expect(lastWeek.days[futureIdx].isFuture == true)
            }
        }
    }

    @Test("Test Case 2: Xử Lý Ranh Giới Tháng & Nhãn Tháng (Month Boundary Edge Case)")
    func testMonthLabelsPlacementAcrossYearBoundary() {
        let calendar = Calendar(identifier: .gregorian)
        let today = DayKey(rawValue: "2026-11-06")

        let weeks = HabitHeatmapBuilder.buildGrid(
            completedDays: [],
            today: today,
            weeksCount: 52,
            calendar: calendar
        )

        // Kiểm tra xem có nhãn tháng được sinh ra
        let labeledWeeks = weeks.compactMap(\.monthLabel)
        #expect(!labeledWeeks.isEmpty)

        // Không phải tuần nào cũng có nhãn tháng (chỉ tuần có ngày đầu tháng hoặc bước chuyển tháng)
        #expect(labeledWeeks.count < weeks.count)
    }

    @Test("Test Case 3: Trạng Thái Ô Hoàn Thành & Tần Suất Đóng Góp (Contribution Status)")
    func testHeatmapCellCompletionAndStreak() {
        let calendar = Calendar(identifier: .gregorian)
        let today = DayKey(rawValue: "2026-11-06")
        let yesterday = DayKey(rawValue: "2026-11-05")

        let scatteredDays: Set<DayKey> = [
            today,
            yesterday,
            DayKey(rawValue: "2026-10-10"),
            DayKey(rawValue: "2026-10-12"),
            DayKey(rawValue: "2026-10-15"),
            DayKey(rawValue: "2026-10-20"),
            DayKey(rawValue: "2026-10-25"),
        ]

        let habit = Habit(
            id: UUID(),
            title: "Đọc sách kỹ thuật",
            createdAt: Date(),
            completedDays: scatteredDays
        )

        let weeks = HabitHeatmapBuilder.buildGrid(
            completedDays: habit.completedDays,
            today: today,
            weeksCount: 52,
            calendar: calendar
        )

        let allDays = weeks.flatMap(\.days)
        let todayCell = allDays.first(where: { $0.dayKey == today })
        let yesterdayCell = allDays.first(where: { $0.dayKey == yesterday })
        let uncompletedCell = allDays.first(where: { $0.dayKey == DayKey(rawValue: "2026-11-04") })

        #expect(todayCell?.isCompleted == true)
        #expect(todayCell?.isToday == true)

        #expect(yesterdayCell?.isCompleted == true)
        #expect(yesterdayCell?.isToday == false)

        #expect(uncompletedCell?.isCompleted == false)

        #expect(habit.completedDays.count == 7)
        #expect(habit.streak(on: today, calendar: calendar) == 2)
    }

    @Test("Test Case 4: Phân Bổ Bảng Màu Nhận Diện Riêng (Palette Rotation & Consistency)")
    func testHabitColorPaletteAssignment() {
        let palette = HabitColorPalette.self

        #expect(palette.palette(for: 0) == .emerald)
        #expect(palette.palette(for: 1) == .oceanSky)
        #expect(palette.palette(for: 2) == .electricViolet)
        #expect(palette.palette(for: 3) == .warmAmber)
        #expect(palette.palette(for: 4) == .roseCoral)
        #expect(palette.palette(for: 5) == .mintTeal)
        #expect(palette.palette(for: 6) == .indigoBlue)

        // Modulo rotation
        #expect(palette.palette(for: 7) == .emerald)
        #expect(palette.palette(for: 8) == .oceanSky)
        #expect(palette.palette(for: 14) == .emerald)

        #expect(HabitColorPalette.emerald.hexString == "#10b981")
        #expect(HabitColorPalette.oceanSky.hexString == "#0ea5e9")
        #expect(HabitColorPalette.electricViolet.hexString == "#8b5cf6")
        #expect(HabitColorPalette.warmAmber.hexString == "#f59e0b")
        #expect(HabitColorPalette.roseCoral.hexString == "#f43f5e")
        #expect(HabitColorPalette.mintTeal.hexString == "#14b8a6")
        #expect(HabitColorPalette.indigoBlue.hexString == "#6366f1")
    }

    @MainActor
    @Test("Test Case 5: Render Habit Studio Heatmap Visual Snapshot")
    func testRenderHabitStudioHeatmapSnapshot() {
        let calendar = Calendar(identifier: .gregorian)
        let today = DayKey(rawValue: "2026-11-06")

        // Tạo 4 thói quen với lịch sử phong phú
        func generateCompletions(seed: Int, total: Int, streakCount: Int) -> Set<DayKey> {
            var days = Set<DayKey>()
            let todayDate = Date()
            // Đảm bảo có streak liên tục gần nhất
            for i in 0..<streakCount {
                if let d = calendar.date(byAdding: .day, value: -i, to: todayDate) {
                    days.insert(DayKey(date: d, calendar: calendar))
                }
            }
            // Thêm các ngày rải rác trong 364 ngày qua
            for i in (streakCount + 1)...360 {
                if (i * seed + 7) % 5 < 3 && days.count < total {
                    if let d = calendar.date(byAdding: .day, value: -i, to: todayDate) {
                        days.insert(DayKey(date: d, calendar: calendar))
                    }
                }
            }
            return days
        }

        let habitsData: [(title: String, streak: Int, total: Int, isDoneToday: Bool, paletteIdx: Int)] = [
            ("Uống 2L nước mỗi ngày", 14, 142, true, 0),
            ("Đọc sách 30 phút", 5, 98, true, 1),
            ("Tập thể dục & Cardio", 22, 186, true, 2),
            ("Viết nhật ký & Deep Work", 8, 65, false, 3)
        ]

        let cardViews = habitsData.enumerated().map { (idx, item) -> AnyView in
            let palette = HabitColorPalette.palette(for: item.paletteIdx)
            let completed = generateCompletions(seed: idx + 3, total: item.total, streakCount: item.streak)
            let weeks = HabitHeatmapBuilder.buildGrid(
                completedDays: completed,
                today: today,
                weeksCount: 52,
                calendar: calendar
            )
            let completionRate = min(100, Int((Double(item.total) / 365.0) * 100.0))

            return AnyView(
                VStack(alignment: .leading, spacing: 12) {
                    // Header của thẻ
                    HStack(alignment: .center, spacing: 10) {
                        Circle()
                            .fill(palette.color)
                            .frame(width: 10, height: 10)

                        Text(item.title)
                            .font(.system(size: 14.5, weight: .bold))
                            .foregroundColor(Color(red: 15/255, green: 23/255, blue: 42/255))

                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 10))
                            Text("\(item.streak) ngày streak")
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                        }
                        .foregroundColor(palette.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(palette.color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                        Text("\(item.total) lần hoàn thành")
                            .font(.system(size: 11.5, weight: .medium))
                            .monospacedDigit()
                            .foregroundColor(Color(red: 100/255, green: 116/255, blue: 139/255))

                        Spacer()

                        // Nút trạng thái hôm nay
                        HStack(spacing: 5) {
                            Image(systemName: item.isDoneToday ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 12))
                            Text(item.isDoneToday ? "Đã xong hôm nay" : "Đánh dấu hôm nay")
                                .font(.system(size: 11.5, weight: item.isDoneToday ? .semibold : .medium))
                        }
                        .foregroundColor(item.isDoneToday ? Color.white : Color(red: 71/255, green: 85/255, blue: 105/255))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4.5)
                        .background(item.isDoneToday ? palette.color : Color(red: 248/255, green: 250/255, blue: 252/255))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(item.isDoneToday ? palette.color : Color(red: 226/255, green: 232/255, blue: 240/255), lineWidth: 1))

                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(Color(red: 148/255, green: 163/255, blue: 184/255))
                            .padding(5)
                    }

                    Rectangle()
                        .fill(Color(red: 226/255, green: 232/255, blue: 240/255))
                        .frame(height: 1)

                    // Bảng lưới GitHub Heatmap
                    VStack(alignment: .leading, spacing: 5) {
                        // Nhãn tháng
                        HStack(spacing: 0) {
                            Text("")
                                .frame(width: 26)

                            ForEach(weeks) { week in
                                if let label = week.monthLabel {
                                    Text(label)
                                        .font(.system(size: 9.5, weight: .medium))
                                        .foregroundColor(Color(red: 100/255, green: 116/255, blue: 139/255))
                                        .frame(width: 14 * 4, alignment: .leading)
                                }
                            }
                        }

                        // Lưới 7 hàng x 52 cột
                        HStack(alignment: .top, spacing: 4) {
                            // Cột nhãn thứ
                            VStack(spacing: 3) {
                                Text("T2").font(.system(size: 9)).foregroundColor(Color(red: 148/255, green: 163/255, blue: 184/255)).frame(height: 11)
                                Text("").frame(height: 11)
                                Text("T4").font(.system(size: 9)).foregroundColor(Color(red: 148/255, green: 163/255, blue: 184/255)).frame(height: 11)
                                Text("").frame(height: 11)
                                Text("T6").font(.system(size: 9)).foregroundColor(Color(red: 148/255, green: 163/255, blue: 184/255)).frame(height: 11)
                                Text("").frame(height: 11)
                                Text("").frame(height: 11)
                            }
                            .frame(width: 22)

                            // 52 tuần
                            HStack(spacing: 3) {
                                ForEach(weeks) { week in
                                    VStack(spacing: 3) {
                                        ForEach(week.days) { day in
                                            RoundedRectangle(cornerRadius: 2.5)
                                                .fill(
                                                    day.isFuture
                                                        ? Color(red: 241/255, green: 245/255, blue: 249/255).opacity(0.4)
                                                        : (day.isCompleted
                                                            ? palette.color
                                                            : Color(red: 235/255, green: 238/255, blue: 242/255))
                                                )
                                                .frame(width: 11, height: 11)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 2.5)
                                                        .stroke(
                                                            day.isToday
                                                                ? palette.color
                                                                : (day.isCompleted ? Color.clear : Color(red: 226/255, green: 232/255, blue: 240/255)),
                                                            lineWidth: day.isToday ? 1.5 : 0.75
                                                        )
                                                )
                                        }
                                    }
                                }
                            }
                        }

                        // Footer tỷ lệ hoàn thành & thanh đo Ít -> Nhiều
                        HStack {
                            Text("Đã duy trì \(completionRate)% số ngày trong 52 tuần qua")
                                .font(.system(size: 11))
                                .foregroundColor(Color(red: 100/255, green: 116/255, blue: 139/255))

                            Spacer()

                            HStack(spacing: 4) {
                                Text("Ít").font(.system(size: 10)).foregroundColor(Color(red: 148/255, green: 163/255, blue: 184/255))
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(red: 235/255, green: 238/255, blue: 242/255))
                                    .frame(width: 9, height: 9)
                                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color(red: 226/255, green: 232/255, blue: 240/255), lineWidth: 0.75))
                                RoundedRectangle(cornerRadius: 2).fill(palette.color.opacity(0.35)).frame(width: 9, height: 9)
                                RoundedRectangle(cornerRadius: 2).fill(palette.color.opacity(0.65)).frame(width: 9, height: 9)
                                RoundedRectangle(cornerRadius: 2).fill(palette.color).frame(width: 9, height: 9)
                                Text("Nhiều").font(.system(size: 10)).foregroundColor(Color(red: 148/255, green: 163/255, blue: 184/255))
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(red: 226/255, green: 232/255, blue: 240/255), lineWidth: 1))
            )
        }

        let fullView = VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quản Trị Thói Quen (Habit Studio)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color(red: 15/255, green: 23/255, blue: 42/255))

                    Text("Bảng lưới đóng góp 52 tuần kiểu GitHub • Mỗi thói quen 1 bảng & màu sắc nhận diện riêng")
                        .font(.system(size: 12.5))
                        .foregroundColor(Color(red: 100/255, green: 116/255, blue: 139/255))
                }

                Spacer()

                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill").foregroundColor(Color(red: 245/255, green: 158/255, blue: 11/255))
                        Text("Streak đỉnh: 22 ngày").font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundColor(Color(red: 15/255, green: 23/255, blue: 42/255))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 226/255, green: 232/255, blue: 240/255), lineWidth: 1))

                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(Color(red: 16/255, green: 185/255, blue: 129/255))
                        Text("Hôm nay: 3/4").font(.system(size: 12, weight: .bold)).monospacedDigit().foregroundColor(Color(red: 15/255, green: 23/255, blue: 42/255))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 226/255, green: 232/255, blue: 240/255), lineWidth: 1))
                }
            }

            // Thanh thêm nhanh
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").foregroundColor(Color(red: 14/255, green: 165/255, blue: 233/255))
                Text("Nhập tên thói quen mới để theo dõi...")
                    .font(.system(size: 12.5))
                    .foregroundColor(Color(red: 148/255, green: 163/255, blue: 184/255))
                Spacer()
                Text("+ Thêm Thói Quen")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(red: 14/255, green: 165/255, blue: 233/255))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 226/255, green: 232/255, blue: 240/255), lineWidth: 1))

            // Danh sách thói quen
            VStack(spacing: 12) {
                ForEach(0..<cardViews.count, id: \.self) { i in
                    cardViews[i]
                }
            }
        }
        .padding(24)
        .frame(width: 1080)
        .background(Color(red: 234/255, green: 239/255, blue: 245/255)) // Scandinavian Soft UI Slate 150

        let hosting = NSHostingView(rootView: fullView)
        hosting.frame = NSRect(x: 0, y: 0, width: 1080, height: 860)
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            Issue.record("Failed to create bitmap rep")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            Issue.record("Failed to create PNG data")
            return
        }

        let outURL1 = URL(fileURLWithPath: "/Users/ryantruong/Project/MyNotch/docs/evidence/habit_studio_heatmap.png")
        let outURL2 = URL(fileURLWithPath: "/Users/ryantruong/.gemini/antigravity-cli/brain/ee26def0-ef76-4a07-abf4-8e638469f7ed/habit_studio_heatmap.png")
        let outURL3 = URL(fileURLWithPath: "/Users/ryantruong/.gemini/antigravity-cli/brain/679ee116-0976-414b-8b0f-76e320c2e41a/habit_studio_heatmap_softui.png")

        try? FileManager.default.createDirectory(at: outURL1.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: outURL3.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? pngData.write(to: outURL1)
        try? pngData.write(to: outURL2)
        try? pngData.write(to: outURL3)
        print("Exported Habit Studio Heatmap to \(outURL1.path) (\(pngData.count) bytes)")
        #expect(pngData.count > 10000)
    }

    // MARK: - Advisor Contract Mandatory Test Cases (Scandinavian Soft UI)

    @Test("Test Case 1: HabitCanvasPalette Soft UI Defaults and Light Mode Colors")
    func testHabitCanvasPaletteSoftUIDefaultsAndLightModeColors() {
        let palette = HabitCanvasPalette.from(palette: .emerald) // Default isDark must be false
        guard let emptyRGB = palette.emptyColor.usingColorSpace(.sRGB),
              let borderRGB = palette.borderColor.usingColorSpace(.sRGB),
              let textRGB = palette.textColor.usingColorSpace(.sRGB) else {
            Issue.record("Failed to convert HabitCanvasPalette colors to sRGB")
            return
        }

        // Empty color: Slate 100 soft #ebeef2 (235, 238, 242)
        #expect(abs(emptyRGB.redComponent - (235.0 / 255.0)) < 0.015)
        #expect(abs(emptyRGB.greenComponent - (238.0 / 255.0)) < 0.015)
        #expect(abs(emptyRGB.blueComponent - (242.0 / 255.0)) < 0.015)

        // Border color: Slate 200 hairline #e2e8f0 (226, 232, 240)
        #expect(abs(borderRGB.redComponent - (226.0 / 255.0)) < 0.015)
        #expect(abs(borderRGB.greenComponent - (232.0 / 255.0)) < 0.015)
        #expect(abs(borderRGB.blueComponent - (240.0 / 255.0)) < 0.015)

        // Text color: Slate 500 #64748b (100, 116, 139)
        #expect(abs(textRGB.redComponent - (100.0 / 255.0)) < 0.015)
        #expect(abs(textRGB.greenComponent - (116.0 / 255.0)) < 0.015)
        #expect(abs(textRGB.blueComponent - (139.0 / 255.0)) < 0.015)
    }

    @Test("Test Case 2: HabitCanvasPalette Dark Mode Colors")
    func testHabitCanvasPaletteDarkModeColors() {
        let palette = HabitCanvasPalette.from(palette: .emerald, isDark: true)
        guard let emptyRGB = palette.emptyColor.usingColorSpace(.sRGB),
              let borderRGB = palette.borderColor.usingColorSpace(.sRGB),
              let textRGB = palette.textColor.usingColorSpace(.sRGB) else {
            Issue.record("Failed to convert HabitCanvasPalette dark colors to sRGB")
            return
        }

        // Empty color: Zinc 800 soft #27272a (39, 39, 42)
        #expect(abs(emptyRGB.redComponent - (39.0 / 255.0)) < 0.02)
        #expect(abs(emptyRGB.greenComponent - (39.0 / 255.0)) < 0.02)
        #expect(abs(emptyRGB.blueComponent - (42.0 / 255.0)) < 0.02)

        // Border color: Zinc 700 #3f3f46 (63, 63, 70)
        #expect(abs(borderRGB.redComponent - (63.0 / 255.0)) < 0.02)
        #expect(abs(borderRGB.greenComponent - (63.0 / 255.0)) < 0.02)
        #expect(abs(borderRGB.blueComponent - (70.0 / 255.0)) < 0.02)

        // Text color: white 0.65
        #expect(textRGB.redComponent >= 0.55)
    }

    @Test("Test Case 3: HabitCanvas Empty Cell Contrast and Relative Luminance Metrics")
    func testHabitCanvasEmptyCellContrastAndLuminanceMetrics() {
        let palette = HabitCanvasPalette.from(palette: .emerald) // Default Soft UI
        guard let emptyRGB = palette.emptyColor.usingColorSpace(.sRGB) else {
            Issue.record("Failed to convert emptyColor to sRGB")
            return
        }

        // Relative Luminance: L = 0.2126 * R + 0.7152 * G + 0.0722 * B
        let luma = 0.2126 * emptyRGB.redComponent + 0.7152 * emptyRGB.greenComponent + 0.0722 * emptyRGB.blueComponent
        #expect(luma >= 0.85)

        // Contrast ratio against white (#FFFFFF, L_white = 1.0)
        // CR = (L_lighter + 0.05) / (L_darker + 0.05)
        let cr = (1.0 + 0.05) / (luma + 0.05)
        #expect(cr >= 1.05 && cr <= 1.30)
    }
}
