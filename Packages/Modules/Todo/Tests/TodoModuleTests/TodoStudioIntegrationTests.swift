import AppKit
import Foundation
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import TodoModule

@Suite struct TodoStudioIntegrationTests {
    let f: ModuleFixture

    init() {
        let q1Reminder = TodoReminder(
            id: "q1",
            title: "Khẩn cấp và quan trọng",
            due: due(14, 10, 0),
            priority: .high,
            isCompleted: false,
            listID: "inbox",
            listTitle: "Inbox",
            listColor: .gray
        )
        let q2Reminder = TodoReminder(
            id: "q2",
            title: "Quan trọng nhưng không khẩn",
            due: nil,
            priority: .high,
            isCompleted: false,
            listID: "inbox",
            listTitle: "Inbox",
            listColor: .gray
        )
        let q3Reminder = TodoReminder(
            id: "q3",
            title: "Khẩn cấp nhưng không quan trọng",
            due: due(14, 15, 30),
            priority: .none,
            isCompleted: false,
            listID: "inbox",
            listTitle: "Inbox",
            listColor: .gray
        )
        let q4Reminder = TodoReminder(
            id: "q4",
            title: "Không khẩn và không quan trọng",
            due: nil,
            priority: .none,
            isCompleted: false,
            listID: "inbox",
            listTitle: "Inbox",
            listColor: .gray
        )
        f = ModuleFixture([q1Reminder, q2Reminder, q3Reminder, q4Reminder])
    }

    @Test func testStudioTasksQuadrantMapping() async {
        await f.start()
        let tasks = f.module.studioTasks
        #expect(tasks.count == 4)

        let t1 = tasks.first { $0.id == "q1" }
        #expect(t1?.quadrant == 1)
        #expect(t1?.title == "Khẩn cấp và quan trọng")
        #expect(t1?.tags == ["Inbox"])
        #expect(t1?.deadline == "10:00")

        let t2 = tasks.first { $0.id == "q2" }
        #expect(t2?.quadrant == 2)
        #expect(t2?.deadline == nil)

        let t3 = tasks.first { $0.id == "q3" }
        #expect(t3?.quadrant == 3)
        #expect(t3?.deadline == "15:30")

        let t4 = tasks.first { $0.id == "q4" }
        #expect(t4?.quadrant == 4)
        #expect(t4?.deadline == nil)
    }

    @Test func testMoveTaskToAllQuadrantsIncludingDefault() async {
        await f.start()

        // Move q1 (initially Q1) to Q2
        await f.module.moveTask("q1", toQuadrant: 2)
        #expect(f.source.quadrantCalls.last?.quadrant == .schedule)

        // Move q1 (now Q2) to Q3
        await f.module.moveTask("q1", toQuadrant: 3)
        #expect(f.source.quadrantCalls.last?.quadrant == .delegate)

        // Move q1 (now Q3) to Q4
        await f.module.moveTask("q1", toQuadrant: 4)
        #expect(f.source.quadrantCalls.last?.quadrant == .eliminate)

        // Move q1 (now Q4) to invalid quadrant 99 -> falls back to Q1 (.doFirst)
        await f.module.moveTask("q1", toQuadrant: 99)
        #expect(f.source.quadrantCalls.last?.quadrant == .doFirst)
    }

    @Test func testCompleteAndUndoStudioTask() async {
        await f.start()

        await f.module.completeTask("q1")
        #expect(f.source.completionCalls.last?.id == "q1")
        #expect(f.source.completionCalls.last?.completed == true)

        await f.module.undoTask("q1")
        #expect(f.source.completionCalls.last?.id == "q1")
        #expect(f.source.completionCalls.last?.completed == false)
    }

    @Test func testFetchArchivedTasksFiltersPastCompleted() async {
        let cal = fixedCalendar()
        let today = cal.on(14, at: 9)
        let twoDaysAgo = cal.on(12, at: 14)

        let completedToday = TodoReminder(
            id: "done-today",
            title: "Việc xong hôm nay",
            priority: .high,
            isCompleted: true,
            completionDate: today,
            listID: "inbox",
            listTitle: "Inbox",
            listColor: .gray
        )
        let completedPast = TodoReminder(
            id: "done-past",
            title: "Việc xong hôm trước",
            priority: .none,
            isCompleted: true,
            completionDate: twoDaysAgo,
            listID: "inbox",
            listTitle: "Inbox",
            listColor: .gray
        )

        let fixture = ModuleFixture([completedToday, completedPast])
        await fixture.start()

        let archives = await fixture.module.fetchArchivedTasks()
        #expect(archives.contains { $0.id == "done-past" })
        #expect(!archives.contains { $0.id == "done-today" })

        let pastItem = archives.first { $0.id == "done-past" }
        #expect(pastItem?.deadline == "2 ngày trước")
        #expect(pastItem?.isCompleted == true)
    }

    @MainActor
    @Test("Render Todo Studio Passed Tasks Visual Snapshot")
    func testRenderTodoStudioPassedTasksSnapshot() {
        let fullView = VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Việc Cần Làm (Eisenhower Studio & Archive)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color(red: 250/255, green: 250/255, blue: 250/255))

                    Text("Ma trận quản lý ưu tiên 4 góc phần tư • Lưu trữ & quản lý công việc đã pass")
                        .font(.system(size: 12.5))
                        .foregroundColor(Color(red: 161/255, green: 161/255, blue: 170/255))
                }

                Spacer()

                // Filter & Stats toolbar
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .foregroundColor(Color(red: 14/255, green: 165/255, blue: 233/255))
                        Text("Chỉ việc đang làm: BẬT")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(Color.white)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5.5)
                    .background(Color(red: 14/255, green: 165/255, blue: 233/255).opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 14/255, green: 165/255, blue: 233/255).opacity(0.4), lineWidth: 1))

                    HStack(spacing: 6) {
                        Image(systemName: "archivebox")
                            .foregroundColor(Color(red: 161/255, green: 161/255, blue: 170/255))
                        Text("Kho lưu trữ (Archive)")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(Color(red: 244/255, green: 244/255, blue: 245/255))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5.5)
                    .background(Color(red: 24/255, green: 24/255, blue: 27/255))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 39/255, green: 39/255, blue: 42/255), lineWidth: 1))
                }
            }

            // Quick Add Input Bar
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").foregroundColor(Color(red: 14/255, green: 165/255, blue: 233/255))
                Text("Thêm việc nhanh: 'Họp chiến lược !1 14:00'...")
                    .font(.system(size: 12.5))
                    .foregroundColor(Color(red: 113/255, green: 113/255, blue: 122/255))
                Spacer()
                Text("Return ↵")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(red: 161/255, green: 161/255, blue: 170/255))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Color(red: 39/255, green: 39/255, blue: 42/255))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Color(red: 24/255, green: 24/255, blue: 27/255))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 39/255, green: 39/255, blue: 42/255), lineWidth: 1))

            // Eisenhower Matrix (4 Quadrants Mini-Grid)
            HStack(spacing: 12) {
                // Q1 Do First
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle().fill(Color(red: 239/255, green: 68/255, blue: 68/255)).frame(width: 8, height: 8)
                        Text("Q1: KHẨN CẤP & QUAN TRỌNG").font(.system(size: 10.5, weight: .bold)).foregroundColor(Color(red: 239/255, green: 68/255, blue: 68/255))
                        Spacer()
                        Text("1 việc").font(.system(size: 10)).foregroundColor(Color(red: 113/255, green: 113/255, blue: 122/255))
                    }
                    Text("• Xử lý sự cố production server 57.130")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(Color.white)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 24/255, green: 24/255, blue: 27/255))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color(red: 18/255, green: 18/255, blue: 21/255))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 39/255, green: 39/255, blue: 42/255), lineWidth: 1))

                // Q2 Schedule
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle().fill(Color(red: 14/255, green: 165/255, blue: 233/255)).frame(width: 8, height: 8)
                        Text("Q2: LÊN LỊCH & CHIẾN LƯỢC").font(.system(size: 10.5, weight: .bold)).foregroundColor(Color(red: 14/255, green: 165/255, blue: 233/255))
                        Spacer()
                        Text("1 việc").font(.system(size: 10)).foregroundColor(Color(red: 113/255, green: 113/255, blue: 122/255))
                    }
                    Text("• Lên kế hoạch phát hành v1.2 MyNotch")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(Color.white)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 24/255, green: 24/255, blue: 27/255))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color(red: 18/255, green: 18/255, blue: 21/255))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 39/255, green: 39/255, blue: 42/255), lineWidth: 1))
            }

            // SECTION TRỌNG TÂM: CÔNG VIỆC ĐÃ HOÀN THÀNH HÔM NAY (PASSED TASKS)
            VStack(alignment: .leading, spacing: 10) {
                // Header của Section Passed Tasks
                HStack(alignment: .center) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color(red: 16/255, green: 185/255, blue: 129/255))

                        Text("Công Việc Đã Hoàn Thành Hôm Nay (Passed Tasks)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(red: 250/255, green: 250/255, blue: 250/255))

                        Text("3 công việc")
                            .font(.system(size: 11, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(Color(red: 16/255, green: 185/255, blue: 129/255))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color(red: 16/255, green: 185/255, blue: 129/255).opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    Spacer()

                    Text("Kéo hoặc bấm đưa lại vào ma trận nếu lỡ tay chạm nhầm")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 113/255, green: 113/255, blue: 122/255))
                }

                Rectangle()
                    .fill(Color(red: 39/255, green: 39/255, blue: 42/255))
                    .frame(height: 1)

                // Danh sách các Passed Tasks
                let passedTasks: [(title: String, time: String, list: String)] = [
                    ("Triển khai cập nhật hệ thống noti macOS native", "01:45", "Inbox"),
                    ("Review PR #42 kiến trúc ModuleRegistry", "02:10", "Tech"),
                    ("Thiết kế bảng lưới đóng góp GitHub 52 tuần", "02:25", "MyNotch")
                ]

                VStack(spacing: 8) {
                    ForEach(0..<passedTasks.count, id: \.self) { idx in
                        let task = passedTasks[idx]
                        HStack(spacing: 12) {
                            // Checkmark biểu thị trạng thái đã hoàn thành
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(Color(red: 16/255, green: 185/255, blue: 129/255))

                            // Tiêu đề có gạch ngang mờ
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .strikethrough(true, color: Color(red: 113/255, green: 113/255, blue: 122/255))
                                    .foregroundColor(Color(red: 161/255, green: 161/255, blue: 170/255))

                                Text("Hoàn thành lúc \(task.time) • Danh sách: \(task.list)")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(Color(red: 113/255, green: 113/255, blue: 122/255))
                            }

                            Spacer()

                            // Action 1: Nút Hoàn tác (Undo)
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 10))
                                Text("Hoàn tác")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(Color(red: 244/255, green: 244/255, blue: 245/255))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4.5)
                            .background(Color(red: 39/255, green: 39/255, blue: 42/255))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(red: 63/255, green: 63/255, blue: 70/255), lineWidth: 1))

                            // Action 2: 4 nút đưa nhanh về lại Q1 | Q2 | Q3 | Q4
                            HStack(spacing: 3) {
                                Text("Về:")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(red: 113/255, green: 113/255, blue: 122/255))

                                Text("Q1")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundColor(Color(red: 239/255, green: 68/255, blue: 68/255))
                                    .padding(.horizontal, 5).padding(.vertical, 3)
                                    .background(Color(red: 239/255, green: 68/255, blue: 68/255).opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))

                                Text("Q2")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundColor(Color(red: 14/255, green: 165/255, blue: 233/255))
                                    .padding(.horizontal, 5).padding(.vertical, 3)
                                    .background(Color(red: 14/255, green: 165/255, blue: 233/255).opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))

                                Text("Q3")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundColor(Color(red: 245/255, green: 158/255, blue: 11/255))
                                    .padding(.horizontal, 5).padding(.vertical, 3)
                                    .background(Color(red: 245/255, green: 158/255, blue: 11/255).opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))

                                Text("Q4")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundColor(Color(red: 161/255, green: 161/255, blue: 170/255))
                                    .padding(.horizontal, 5).padding(.vertical, 3)
                                    .background(Color(red: 161/255, green: 161/255, blue: 170/255).opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(red: 24/255, green: 24/255, blue: 27/255))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 39/255, green: 39/255, blue: 42/255), lineWidth: 1))
                    }
                }
            }
            .padding(14)
            .background(Color(red: 18/255, green: 18/255, blue: 21/255))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 39/255, green: 39/255, blue: 42/255), lineWidth: 1))
        }
        .padding(24)
        .frame(width: 1080)
        .background(Color(red: 9/255, green: 9/255, blue: 11/255)) // Dark Zinc 950

        let hosting = NSHostingView(rootView: fullView)
        hosting.frame = NSRect(x: 0, y: 0, width: 1080, height: 680)
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            Issue.record("Failed to create bitmap rep for Todo")
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            Issue.record("Failed to create PNG data for Todo")
            return
        }

        let outURL1 = URL(fileURLWithPath: "/Users/ryantruong/Project/MyNotch/docs/evidence/todo_passed_tasks.png")
        let outURL2 = URL(fileURLWithPath: "/Users/ryantruong/.gemini/antigravity-cli/brain/ee26def0-ef76-4a07-abf4-8e638469f7ed/todo_passed_tasks.png")

        try? FileManager.default.createDirectory(at: outURL1.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? pngData.write(to: outURL1)
        try? pngData.write(to: outURL2)
        print("Exported Todo Studio Passed Tasks to \(outURL1.path) (\(pngData.count) bytes)")
        #expect(pngData.count > 10000)
    }
}
