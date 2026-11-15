import Foundation
import SwiftUI

/// The four quadrants of the Eisenhower Matrix for categorising tasks by urgency and importance.
nonisolated enum EisenhowerQuadrant: Int, CaseIterable, Sendable, Identifiable {
    /// Q1: Urgent and Important ("Thực hiện ngay" / "Làm ngay")
    case doFirst = 1
    /// Q2: Not Urgent but Important ("Lên lịch")
    case schedule = 2
    /// Q3: Urgent but Not Important ("Ủy thác")
    case delegate = 3
    /// Q4: Not Urgent and Not Important ("Xóa bỏ")
    case eliminate = 4

    var id: Int { rawValue }

    var shortCode: String { "Q\(rawValue)" }

    var tag: String { "q\(rawValue)" }

    var title: String {
        switch self {
        case .doFirst: "Thực hiện ngay"
        case .schedule: "Lên lịch"
        case .delegate: "Ủy thác"
        case .eliminate: "Xóa bỏ"
        }
    }

    var label: String {
        switch self {
        case .doFirst: "Làm ngay"
        case .schedule: "Lên lịch"
        case .delegate: "Ủy thác"
        case .eliminate: "Xóa bỏ"
        }
    }

    var subtitle: String {
        switch self {
        case .doFirst: "Khẩn cấp & Quan trọng"
        case .schedule: "Quan trọng, Không khẩn"
        case .delegate: "Khẩn cấp, Không quan trọng"
        case .eliminate: "Không khẩn, Không quan trọng"
        }
    }

    var color: Color {
        switch self {
        case .doFirst: Color(red: 0.937, green: 0.267, blue: 0.267) // #ef4444
        case .schedule: Color(red: 0.231, green: 0.510, blue: 0.965) // #3b82f6
        case .delegate: Color(red: 0.063, green: 0.725, blue: 0.506) // #10b981
        case .eliminate: Color(red: 0.961, green: 0.620, blue: 0.043) // #f59e0b
        }
    }

    /// Classify task based on priority (importance) and due date / overdue days (urgency).
    static func classify(
        priority: TodoPriority,
        hasDue: Bool,
        overdueDays: Int = 0,
        importantAtLeast: TodoPriority = .medium
    ) -> EisenhowerQuadrant {
        let isUrgent = hasDue || overdueDays > 0
        let isImportant = priority >= importantAtLeast
        switch (isUrgent, isImportant) {
        case (true, true): return .doFirst
        case (false, true): return .schedule
        case (true, false): return .delegate
        case (false, false): return .eliminate
        }
    }

    /// Classify a TodoItem.
    static func classify(_ item: TodoItem, importantAtLeast: TodoPriority = .medium) -> EisenhowerQuadrant {
        classify(
            priority: item.reminder.priority,
            hasDue: item.reminder.due != nil,
            overdueDays: item.overdueDays,
            importantAtLeast: importantAtLeast
        )
    }

    /// Partition rows into the 4 quadrants, preserving the existing order of items in each quadrant.
    static func partition(_ rows: [TodoItem], importantAtLeast: TodoPriority = .medium) -> [EisenhowerQuadrant: [TodoItem]] {
        var result: [EisenhowerQuadrant: [TodoItem]] = [
            .doFirst: [],
            .schedule: [],
            .delegate: [],
            .eliminate: []
        ]
        for item in rows {
            let quadrant = classify(item, importantAtLeast: importantAtLeast)
            result[quadrant]?.append(item)
        }
        return result
    }

    /// Canonical fields for quick-add when tagging with this quadrant.
    static func canonicalFields(for quadrant: EisenhowerQuadrant) -> (priority: TodoPriority, dated: Bool) {
        switch quadrant {
        case .doFirst: (.high, true)
        case .schedule: (.high, false)
        case .delegate: (.none, true)
        case .eliminate: (.none, false)
        }
    }

    /// Patch priority and due date to reclassify a reminder into the target quadrant.
    /// Preserves existing priority if it already meets the target's importance threshold.
    /// Preserves existing due date (including time components) if target is dated, or assigns `today` if previously undated.
    static func patch(
        priority: TodoPriority,
        due: DateComponents?,
        overdueDays: Int = 0,
        target: EisenhowerQuadrant,
        today: DateComponents
    ) -> (priority: TodoPriority, due: DateComponents?) {
        let newPriority: TodoPriority
        switch target {
        case .doFirst, .schedule:
            newPriority = priority >= .medium ? priority : .high
        case .delegate, .eliminate:
            newPriority = priority < .medium ? priority : .none
        }

        let newDue: DateComponents?
        switch target {
        case .doFirst, .delegate:
            newDue = due ?? today
        case .schedule, .eliminate:
            newDue = nil
        }

        return (newPriority, newDue)
    }
}
