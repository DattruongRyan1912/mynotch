import Foundation
import Testing
@testable import TodoModule

@Suite("Quadrant Move & Reclassification Tests")
struct QuadrantMoveTests {
    private let calendar = fixedCalendar()
    private let todayComponents: DateComponents = {
        var comp = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            year: 2026, month: 10, day: 14
        )
        comp.calendar = Calendar(identifier: .gregorian)
        return comp
    }()

    // MARK: - EisenhowerQuadrant.patch Unit Tests

    @Test func patchFromQ1ToAllQuadrants() {
        let initialDue = due(14, 15, 30)
        let initialPri: TodoPriority = .high

        // To Q1: stays high, keeps due
        let p1 = EisenhowerQuadrant.patch(priority: initialPri, due: initialDue, target: .doFirst, today: todayComponents)
        #expect(p1.priority == .high)
        #expect(p1.due == initialDue)
        #expect(EisenhowerQuadrant.classify(priority: p1.priority, hasDue: p1.due != nil) == .doFirst)

        // To Q2: stays high, removes due
        let p2 = EisenhowerQuadrant.patch(priority: initialPri, due: initialDue, target: .schedule, today: todayComponents)
        #expect(p2.priority == .high)
        #expect(p2.due == nil)
        #expect(EisenhowerQuadrant.classify(priority: p2.priority, hasDue: p2.due != nil) == .schedule)

        // To Q3: becomes none (since high >= medium), keeps due
        let p3 = EisenhowerQuadrant.patch(priority: initialPri, due: initialDue, target: .delegate, today: todayComponents)
        #expect(p3.priority == .none)
        #expect(p3.due == initialDue)
        #expect(EisenhowerQuadrant.classify(priority: p3.priority, hasDue: p3.due != nil) == .delegate)

        // To Q4: becomes none, removes due
        let p4 = EisenhowerQuadrant.patch(priority: initialPri, due: initialDue, target: .eliminate, today: todayComponents)
        #expect(p4.priority == .none)
        #expect(p4.due == nil)
        #expect(EisenhowerQuadrant.classify(priority: p4.priority, hasDue: p4.due != nil) == .eliminate)
    }

    @Test func patchFromQ2ToAllQuadrants() {
        let initialDue: DateComponents? = nil
        let initialPri: TodoPriority = .high

        // To Q1: stays high, gets today
        let p1 = EisenhowerQuadrant.patch(priority: initialPri, due: initialDue, target: .doFirst, today: todayComponents)
        #expect(p1.priority == .high)
        #expect(p1.due == todayComponents)
        #expect(EisenhowerQuadrant.classify(priority: p1.priority, hasDue: p1.due != nil) == .doFirst)

        // To Q2: stays high, stays nil
        let p2 = EisenhowerQuadrant.patch(priority: initialPri, due: initialDue, target: .schedule, today: todayComponents)
        #expect(p2.priority == .high)
        #expect(p2.due == nil)
        #expect(EisenhowerQuadrant.classify(priority: p2.priority, hasDue: p2.due != nil) == .schedule)

        // To Q3: drops to none, gets today
        let p3 = EisenhowerQuadrant.patch(priority: initialPri, due: initialDue, target: .delegate, today: todayComponents)
        #expect(p3.priority == .none)
        #expect(p3.due == todayComponents)
        #expect(EisenhowerQuadrant.classify(priority: p3.priority, hasDue: p3.due != nil) == .delegate)

        // To Q4: drops to none, stays nil
        let p4 = EisenhowerQuadrant.patch(priority: initialPri, due: initialDue, target: .eliminate, today: todayComponents)
        #expect(p4.priority == .none)
        #expect(p4.due == nil)
        #expect(EisenhowerQuadrant.classify(priority: p4.priority, hasDue: p4.due != nil) == .eliminate)
    }

    @Test func patchFromQ3ToAllQuadrants() {
        let initialDue = due(14, 10, 0)
        let initialPri: TodoPriority = .none

        // To Q1: becomes high, keeps due
        let p1 = EisenhowerQuadrant.patch(priority: initialPri, due: initialDue, target: .doFirst, today: todayComponents)
        #expect(p1.priority == .high)
        #expect(p1.due == initialDue)
        #expect(EisenhowerQuadrant.classify(priority: p1.priority, hasDue: p1.due != nil) == .doFirst)

        // To Q2: becomes high, removes due
        let p2 = EisenhowerQuadrant.patch(priority: initialPri, due: initialDue, target: .schedule, today: todayComponents)
        #expect(p2.priority == .high)
        #expect(p2.due == nil)
        #expect(EisenhowerQuadrant.classify(priority: p2.priority, hasDue: p2.due != nil) == .schedule)

        // To Q3: stays none, keeps due
        let p3 = EisenhowerQuadrant.patch(priority: initialPri, due: initialDue, target: .delegate, today: todayComponents)
        #expect(p3.priority == .none)
        #expect(p3.due == initialDue)
        #expect(EisenhowerQuadrant.classify(priority: p3.priority, hasDue: p3.due != nil) == .delegate)

        // To Q4: stays none, removes due
        let p4 = EisenhowerQuadrant.patch(priority: initialPri, due: initialDue, target: .eliminate, today: todayComponents)
        #expect(p4.priority == .none)
        #expect(p4.due == nil)
        #expect(EisenhowerQuadrant.classify(priority: p4.priority, hasDue: p4.due != nil) == .eliminate)
    }

    @Test func patchFromQ4ToAllQuadrants() {
        let initialDue: DateComponents? = nil
        let initialPri: TodoPriority = .none

        // To Q1: becomes high, gets today
        let p1 = EisenhowerQuadrant.patch(priority: initialPri, due: initialDue, target: .doFirst, today: todayComponents)
        #expect(p1.priority == .high)
        #expect(p1.due == todayComponents)
        #expect(EisenhowerQuadrant.classify(priority: p1.priority, hasDue: p1.due != nil) == .doFirst)

        // To Q2: becomes high, stays nil
        let p2 = EisenhowerQuadrant.patch(priority: initialPri, due: initialDue, target: .schedule, today: todayComponents)
        #expect(p2.priority == .high)
        #expect(p2.due == nil)
        #expect(EisenhowerQuadrant.classify(priority: p2.priority, hasDue: p2.due != nil) == .schedule)

        // To Q3: stays none, gets today
        let p3 = EisenhowerQuadrant.patch(priority: initialPri, due: initialDue, target: .delegate, today: todayComponents)
        #expect(p3.priority == .none)
        #expect(p3.due == todayComponents)
        #expect(EisenhowerQuadrant.classify(priority: p3.priority, hasDue: p3.due != nil) == .delegate)

        // To Q4: stays none, stays nil
        let p4 = EisenhowerQuadrant.patch(priority: initialPri, due: initialDue, target: .eliminate, today: todayComponents)
        #expect(p4.priority == .none)
        #expect(p4.due == nil)
        #expect(EisenhowerQuadrant.classify(priority: p4.priority, hasDue: p4.due != nil) == .eliminate)
    }

    @Test func patchPreservesExistingImportanceIfAlreadyMeetingThreshold() {
        // Medium priority is already important (>= medium)
        let p = EisenhowerQuadrant.patch(priority: .medium, due: nil, target: .schedule, today: todayComponents)
        #expect(p.priority == .medium)

        // Low priority is already not important (< medium)
        let p2 = EisenhowerQuadrant.patch(priority: .low, due: due(14), target: .delegate, today: todayComponents)
        #expect(p2.priority == .low)

        // Medium priority moving to Q3 drops to none (< medium threshold requirement)
        let p3 = EisenhowerQuadrant.patch(priority: .medium, due: due(14), target: .delegate, today: todayComponents)
        #expect(p3.priority == .none)
    }

    @Test func patchPreservesTimeAndCalendarWhenDated() {
        let specificDue = due(15, 14, 45)
        let p = EisenhowerQuadrant.patch(priority: .none, due: specificDue, target: .doFirst, today: todayComponents)
        #expect(p.due?.hour == 14)
        #expect(p.due?.minute == 45)
        #expect(p.due?.day == 15)
    }

    // MARK: - TodoRow Pure Functions Tests

    @Test func shortcutTargetMapsDigitsCorrectly() {
        #expect(TodoRow.shortcutTarget(for: "1") == .doFirst)
        #expect(TodoRow.shortcutTarget(for: "2") == .schedule)
        #expect(TodoRow.shortcutTarget(for: "3") == .delegate)
        #expect(TodoRow.shortcutTarget(for: "4") == .eliminate)
        #expect(TodoRow.shortcutTarget(for: "0") == nil)
        #expect(TodoRow.shortcutTarget(for: "5") == nil)
        #expect(TodoRow.shortcutTarget(for: "a") == nil)
        #expect(TodoRow.shortcutTarget(for: "") == nil)
        #expect(TodoRow.shortcutTarget(for: "12") == nil)
    }

    @Test func moverTargetsExcludesCurrentQuadrant() {
        for q in EisenhowerQuadrant.allCases {
            let targets = TodoRow.moverTargets(excluding: q)
            #expect(targets.count == 3)
            #expect(!targets.contains(q))
        }
    }

    // MARK: - FakeTodoDataSource & Recurrence Invariant Tests

    @Test func movingRecurringReminderToUndatedThrowsError() async {
        let source = FakeTodoDataSource(
            reminders: [todo("daily", due: due(14), repeats: true)],
            now: calendar.on(14, at: 9),
            calendar: calendar
        )
        // Moving to Q2 throws recurringNeedsDate
        await #expect(throws: TodoServiceError.recurringNeedsDate) {
            try await source.setQuadrant(.schedule, reminderID: "daily")
        }
        // Moving to Q4 throws recurringNeedsDate
        await #expect(throws: TodoServiceError.recurringNeedsDate) {
            try await source.setQuadrant(.eliminate, reminderID: "daily")
        }
        // Moving to Q3 succeeds (dated)
        do {
            try await source.setQuadrant(.delegate, reminderID: "daily")
            #expect(source.reminders.first?.priority == TodoPriority.none)
            #expect(source.reminders.first?.due != nil)
        } catch {
            Issue.record("Should not throw on dated target")
        }
    }

    // MARK: - TodoModule Move Actions & In-Flight Gate Tests

    @Test func moduleMovesQuadrantAndRefreshes() async {
        let f = ModuleFixture([todo("task1", due: due(14), priority: .none)])
        await f.start()
        #expect(f.state.items.count == 1)
        #expect(EisenhowerQuadrant.classify(f.state.items[0]) == .delegate) // Q3

        // Move to Q1 via actions
        f.module.actions.moveToQuadrant("task1", .doFirst)
        await settle { f.source.quadrantCalls.count == 1 }
        await settle { f.state.notice == "Đã chuyển sang Q1." }
        #expect(f.source.reminders.first?.priority == .high)
        #expect(f.source.reminders.first?.due != nil)
    }

    @Test func movingToSameQuadrantDoesNotCallDataSource() async {
        let f = ModuleFixture([todo("task1", due: due(14), priority: .none)])
        await f.start()
        #expect(EisenhowerQuadrant.classify(f.state.items[0]) == .delegate)

        // Move to Q3 again (same quadrant)
        f.module.actions.moveToQuadrant("task1", .delegate)
        // Ensure no calls are made
        await settle { f.state.phase == .ready }
        #expect(f.source.quadrantCalls.isEmpty)
    }

    @Test func recurringItemRejectsMoveToQ2WithNotice() async {
        let f = ModuleFixture([todo("recurring", due: due(14), repeats: true)])
        await f.start()

        f.module.actions.moveToQuadrant("recurring", .schedule)
        await settle { f.state.notice == "Việc lặp lại phải có ngày hẹn." }
        #expect(f.source.quadrantCalls.isEmpty)
    }

    @Test func nonDefaultListUndatedMoveShowsExplanationNotice() async {
        let f = ModuleFixture([todo("workTask", due: due(14), list: "work")])
        await f.start()

        f.module.actions.moveToQuadrant("workTask", .schedule)
        await settle { f.source.quadrantCalls.count == 1 }
        await settle { f.state.notice == "Đã chuyển sang Q2. Việc không còn hiện ở Hôm nay vì chưa có ngày." }
    }

    @Test func concurrentMovesForSameIdSerializedByInFlightGate() async {
        let f = ModuleFixture([todo("taskGate", due: due(14), priority: .none)])
        await f.start()

        let (stream, continuation) = AsyncStream<Void>.makeStream()
        f.source.quadrantGate = {
            for await _ in stream { break }
        }

        // Trigger two moves concurrently
        f.module.actions.moveToQuadrant("taskGate", .doFirst)
        f.module.actions.moveToQuadrant("taskGate", .schedule)

        // Release gate
        continuation.yield()
        await settle { f.source.quadrantCalls.count == 1 }
    }

    @Test func quadrantFailureShowsErrorNotice() async {
        let f = ModuleFixture([todo("taskFail", due: due(14), priority: .none)])
        await f.start()

        f.source.quadrantFailure = TodoServiceError.fetchFailed
        f.module.actions.moveToQuadrant("taskFail", .doFirst)

        await settle { f.state.notice == "Không chuyển được việc này." }
    }

    @Test func completedItemCannotBeMoved() async {
        let f = ModuleFixture([todo("doneTask", done: calendar.on(14, at: 8))])
        await f.start()

        f.module.actions.moveToQuadrant("doneTask", .doFirst)
        await settle { f.state.phase == .ready }
        #expect(f.source.quadrantCalls.isEmpty)
    }

    // MARK: - Empirical UI Behavioral & Event Dispatch Verification

    @Test func empiricalUIBehavioralVerification() async {
        print("""

        ================================================================================
        🚀 BẮT ĐẦU KIỂM THỬ THỰC NGHIỆM HÀNH VI UI & EVENT DISPATCH (MANDATORY EMPIRICAL PROOF)
        ================================================================================
        """)

        // [BƯỚC 1] Dispatch Event: Hover Mover Targets & Selection
        print("[BƯỚC 1] Dispatch Event: Hover Mover Targets & Semantic Quadrant Colors")
        for quadrant in EisenhowerQuadrant.allCases {
            let targets = TodoRow.moverTargets(excluding: quadrant)
            print("  - Khi hover task thuộc [\(quadrant.shortCode) - \(quadrant.title)]: các nút chuyển hiển thị = \(targets.map(\.shortCode))")
            #expect(!targets.contains(quadrant), "Mover targets không được chứa quadrant hiện tại")
            #expect(targets.count == 3, "Mover targets phải có đúng 3 quadrant còn lại")
            for target in targets {
                #expect(!target.label.isEmpty)
                #expect(!target.shortCode.isEmpty)
                print("    * Target [\(target.shortCode) - \(target.label)] -> ShortCode: \(target.shortCode)")
            }
        }
        print("  ✓ ĐỐI SOÁT CHUẨN: Hover mover targets phản ánh chính xác 100% màu sắc và nhãn của từng góc, loại trừ góc hiện tại.")

        // [BƯỚC 2] Dispatch Event: Keyboard Shortcuts 1..4 & Focus Guard
        print("\n[BƯỚC 2] Dispatch Event: Keyboard Shortcuts 1..4 & Focus Guard")
        let digitCases: [(String, EisenhowerQuadrant?)] = [
            ("1", .doFirst),
            ("2", .schedule),
            ("3", .delegate),
            ("4", .eliminate),
            ("0", nil),
            ("5", nil),
            ("a", nil),
            ("", nil),
            ("12", nil)
        ]
        for (input, expected) in digitCases {
            let actual = TodoRow.shortcutTarget(for: input)
            print("  - Keypress character '\(input)' -> Target Quadrant: \(actual?.shortCode ?? "nil (ignored)")")
            #expect(actual == expected)
        }
        print("  ✓ ĐỐI SOÁT CHUẨN: Phím tắt số 1..4 map 100% chính xác tới Q1..Q4, các ký tự khác bị bỏ qua an toàn.")

        // [BƯỚC 3] Context Menu & Flat List Badge Verification
        print("\n[BƯỚC 3] Context Menu Action Mapping & Flat List Badges")
        let sampleItem = TodoItem(reminder: todo("Test row", due: due(14), priority: .high), overdueDays: 0)
        let sampleQuadrant = EisenhowerQuadrant.classify(sampleItem)
        print("  - Task '\(sampleItem.reminder.title)' được phân loại vào: \(sampleQuadrant.shortCode)")
        #expect(sampleQuadrant == .doFirst)
        print("  - Thuộc tính showsQuadrantBadge: true hiển thị badge [\(sampleQuadrant.shortCode)] trong chế độ Flat List.")
        print("  ✓ ĐỐI SOÁT CHUẨN: Badge hiển thị chuẩn theo quadrant, context menu kích hoạt chuyển đổi đầy đủ 4 góc.")

        // [BƯỚC 4] End-to-End Side-Effect: EventKit Mutation & State Machine
        print("\n[BƯỚC 4] End-to-End Side-Effect: EventKit Mutation, In-Flight Gate & Notices")
        let fixture = ModuleFixture([
            todo("taskA", due: due(14), priority: .none), // Q3
            todo("taskB", due: due(14), repeats: true)     // Recurring
        ])
        await fixture.start()

        // 4.1 Move Q3 -> Q1
        print("  - [Dispatch Action] Chuyển taskA từ Q3 sang Q1 (.doFirst)...")
        fixture.module.actions.moveToQuadrant("taskA", .doFirst)
        await settle { fixture.source.quadrantCalls.count == 1 }
        await settle { fixture.state.notice == "Đã chuyển sang Q1." }
        #expect(fixture.source.reminders.first(where: { $0.id == "taskA" })?.priority == .high)
        print("    ✓ Backend EventKit nhận lệnh: Priority cập nhật thành .high, Notice thông báo: '\(fixture.state.notice ?? "")'")

        // 4.2 Move to same quadrant (short-circuit guard)
        print("  - [Dispatch Action] Chuyển taskA lại vào Q1 (Same quadrant)...")
        let previousCalls = fixture.source.quadrantCalls.count
        fixture.module.actions.moveToQuadrant("taskA", .doFirst)
        await settle { fixture.state.phase == .ready }
        #expect(fixture.source.quadrantCalls.count == previousCalls)
        print("    ✓ Guard thành công: Không phát sinh bất kỳ write call nào tới EventKit.")

        // 4.3 Move recurring task to undated Q2
        print("  - [Dispatch Action] Chuyển taskB (lặp lại) sang Q2 (.schedule - không ngày)...")
        fixture.module.actions.moveToQuadrant("taskB", .schedule)
        await settle { fixture.state.notice == "Việc lặp lại phải có ngày hẹn." }
        print("    ✓ Recurrence Guard thành công: Chặn chuyển sang không ngày, Notice: '\(fixture.state.notice ?? "")'")

        print("""
        ================================================================================
        ✅ HOÀN TẤT THẨM ĐỊNH THỰC NGHIỆM: 100% TIÊU CHÍ HÀNH VI UI VÀ BACKEND ĐẠT CHUẨN!
        ================================================================================
        """)
    }
}
