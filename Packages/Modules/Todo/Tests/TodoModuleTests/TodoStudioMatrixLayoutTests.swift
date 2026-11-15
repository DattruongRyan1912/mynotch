import AppKit
import Foundation
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import TodoModule

@MainActor
@Suite struct TodoStudioMatrixLayoutTests {

    // MARK: - TC-01: Happy Path — Independent Drafts & Quadrant Routing

    @Test("TC-01: Independent Quick Add Drafts & End-to-End Quadrant Routing")
    func testIndependentQuickAddDraftsAndEndToEndQuadrantRouting() async {
        var drafts = TodoStudioQuickAddDrafts()
        drafts.toolbarDraft = "Việc chung !1"
        drafts.setDraft("Cấp cứu server", forQuadrant: 1)
        drafts.setDraft("Lập roadmap Q3", forQuadrant: 2)
        drafts.setDraft("Nhờ team QA", forQuadrant: 3)
        drafts.setDraft("Dọn log cũ", forQuadrant: 4)

        let fixture = ModuleFixture([])
        await fixture.start()

        // Consume Q1
        guard let q1Submission = drafts.consumeSubmission(forQuadrant: 1) else {
            Issue.record("Expected valid submission for Q1")
            return
        }

        #expect(q1Submission.rawDraft == "Cấp cứu server")
        #expect(q1Submission.formattedCommand == "!q1 Cấp cứu server")

        // Cross-contamination assertions
        #expect(drafts.draft(forQuadrant: 1) == "")
        #expect(drafts.draft(forQuadrant: 2) == "Lập roadmap Q3")
        #expect(drafts.draft(forQuadrant: 3) == "Nhờ team QA")
        #expect(drafts.draft(forQuadrant: 4) == "Dọn log cũ")
        #expect(drafts.toolbarDraft == "Việc chung !1")

        // Consume remaining quadrants
        guard let q2Submission = drafts.consumeSubmission(forQuadrant: 2),
              let q3Submission = drafts.consumeSubmission(forQuadrant: 3),
              let q4Submission = drafts.consumeSubmission(forQuadrant: 4) else {
            Issue.record("Expected valid submissions for Q2, Q3, Q4")
            return
        }

        #expect(q2Submission.formattedCommand == "!q2 Lập roadmap Q3")
        #expect(q3Submission.formattedCommand == "!q3 Nhờ team QA")
        #expect(q4Submission.formattedCommand == "!q4 Dọn log cũ")

        // Feed all 4 into TodoModule
        let add1 = await fixture.module.addTask(q1Submission.formattedCommand)
        let add2 = await fixture.module.addTask(q2Submission.formattedCommand)
        let add3 = await fixture.module.addTask(q3Submission.formattedCommand)
        let add4 = await fixture.module.addTask(q4Submission.formattedCommand)

        #expect(add1)
        #expect(add2)
        #expect(add3)
        #expect(add4)

        await fixture.module.refreshTasks()
        let studioTasks = fixture.module.studioTasks

        #expect(studioTasks.count == 4)

        let task1 = studioTasks.first(where: { $0.quadrant == 1 })
        let task2 = studioTasks.first(where: { $0.quadrant == 2 })
        let task3 = studioTasks.first(where: { $0.quadrant == 3 })
        let task4 = studioTasks.first(where: { $0.quadrant == 4 })

        #expect(task1 != nil)
        #expect(task2 != nil)
        #expect(task3 != nil)
        #expect(task4 != nil)

        #expect(task1?.title == "Cấp cứu server")
        #expect(task2?.title == "Lập roadmap Q3")
        #expect(task3?.title == "Nhờ team QA")
        #expect(task4?.title == "Dọn log cũ")
    }

    // MARK: - TC-02: Uniform Heights, Equal Widths & Pinned Inputs Across Skewed Data

    @Test("TC-02: Uniform Card Heights, Equal Widths & Pinned Inputs Across Skewed Data")
    func testMatrixGridUniformCardHeightsEqualWidthsAndPinnedInputsAcrossSkewedData() async {
        // Scenario A (Represents user screenshot: 0, 0, 0, 1)
        let tasksA: [TodoStudioItem] = [
            TodoStudioItem(id: "task4", title: "Thẩm định nghiệm thu Studio !1", isCompleted: false, quadrant: 4, tags: ["Lời nhắc"], deadline: nil)
        ]

        // Scenario B (Extreme skew: Q1=0, Q2=3 with long titles, Q3=0, Q4=8)
        var tasksB: [TodoStudioItem] = []
        for i in 1...3 {
            tasksB.append(TodoStudioItem(
                id: "q2_\(i)",
                title: "Nhiệm vụ chiến lược dài với mô tả chi tiết và nhiều tiêu chí đánh giá nghiệm thu hệ thống phân tán số \(i) có độ dài hơn 180 ký tự để kiểm tra tính năng xuống dòng an toàn không làm vỡ bố cục ma trận",
                isCompleted: false,
                quadrant: 2,
                tags: ["Chiến lược", "Backend", "P0", "Q3"],
                deadline: "17:00"
            ))
        }
        for i in 1...8 {
            tasksB.append(TodoStudioItem(
                id: "q4_\(i)",
                title: "Dọn dẹp tài liệu cũ và rà soát log số \(i)",
                isCompleted: false,
                quadrant: 4,
                tags: ["Rác"],
                deadline: nil
            ))
        }

        for width in [1000.0, 600.0] {
            let metricsA = await measureMatrixLayout(tasks: tasksA, width: width)
            let metricsB = await measureMatrixLayout(tasks: tasksB, width: width)

            for (scenarioName, metrics) in [("Scenario A", metricsA), ("Scenario B", metricsB)] {
                guard let q1 = metrics.cardFrames[1],
                      let q2 = metrics.cardFrames[2],
                      let q3 = metrics.cardFrames[3],
                      let q4 = metrics.cardFrames[4],
                      let qa1 = metrics.quickAddFrames[1],
                      let qa2 = metrics.quickAddFrames[2],
                      let qa3 = metrics.quickAddFrames[3],
                      let qa4 = metrics.quickAddFrames[4] else {
                    Issue.record("Failed to capture all geometry frames for \(scenarioName) at width \(width)")
                    continue
                }

                // 1. All 4 cards have equal height matching cardHeight
                #expect(abs(q1.height - TodoStudioMatrixGrid.cardHeight) < 1.0)
                #expect(abs(q1.height - q2.height) < 0.5)
                #expect(abs(q3.height - q4.height) < 0.5)
                #expect(abs(q1.height - q4.height) < 0.5)
                #expect(q1.height >= 220.0)

                // 2. Row alignment (No vertical jumping/centering like LazyVGrid)
                #expect(abs(q1.minY - q2.minY) < 0.5)
                #expect(abs(q1.maxY - q2.maxY) < 0.5)
                #expect(abs(q3.minY - q4.minY) < 0.5)
                #expect(abs(q3.maxY - q4.maxY) < 0.5)

                // 3. 50/50 column distribution
                #expect(abs(q1.width - q2.width) < 1.0)
                #expect(abs(q3.width - q4.width) < 1.0)

                // 4. Quick Add pinned at bottom
                #expect(abs(qa1.minY - qa2.minY) < 0.5)
                #expect(abs(qa3.minY - qa4.minY) < 0.5)
            }

            // 5. Total matrix height is invariant between Scenario A and Scenario B (0px trồi sụt)
            if let aQ1 = metricsA.cardFrames[1], let aQ3 = metricsA.cardFrames[3],
               let bQ1 = metricsB.cardFrames[1], let bQ3 = metricsB.cardFrames[3] {
                let totalHeightA = aQ3.maxY - aQ1.minY
                let totalHeightB = bQ3.maxY - bQ1.minY
                #expect(abs(totalHeightA - totalHeightB) < 1.0)
            }
        }
    }

    // MARK: - TC-03: Negative & Error Handling

    @Test("TC-03: Invalid Submissions & Failed Persistence Restores Draft Safely")
    func testInvalidSubmissionsAndFailedPersistenceRestoresDraftSafely() {
        var drafts = TodoStudioQuickAddDrafts()
        drafts.setDraft("   \t\n  ", forQuadrant: 1)
        drafts.setDraft("Bản nháp quan trọng", forQuadrant: 2)

        // Submitting whitespace clears Q1, returns nil, preserves Q2
        let emptySub = drafts.consumeSubmission(forQuadrant: 1)
        #expect(emptySub == nil)
        #expect(drafts.draft(forQuadrant: 1) == "")
        #expect(drafts.draft(forQuadrant: 2) == "Bản nháp quan trọng")

        // Invalid quadrants return nil
        #expect(drafts.consumeSubmission(forQuadrant: 0) == nil)
        #expect(drafts.consumeSubmission(forQuadrant: 5) == nil)
        #expect(drafts.draft(forQuadrant: 0) == "")
        #expect(drafts.draft(forQuadrant: 5) == "")

        // Simulate failed addTask: consume -> fail -> restore
        guard let subQ2 = drafts.consumeSubmission(forQuadrant: 2) else {
            Issue.record("Expected valid submission for Q2")
            return
        }
        #expect(subQ2.rawDraft == "Bản nháp quan trọng")
        #expect(drafts.draft(forQuadrant: 2) == "")

        // addTask returns false -> restoreDraftIfEmpty restores
        drafts.restoreDraftIfEmpty(subQ2.rawDraft, forQuadrant: 2)
        #expect(drafts.draft(forQuadrant: 2) == "Bản nháp quan trọng")

        // If user already typed new text in the meantime, do not overwrite
        guard let subQ2Again = drafts.consumeSubmission(forQuadrant: 2) else {
            Issue.record("Expected valid submission for Q2 again")
            return
        }
        drafts.setDraft("Nội dung mới đang gõ", forQuadrant: 2)
        drafts.restoreDraftIfEmpty(subQ2Again.rawDraft, forQuadrant: 2)
        #expect(drafts.draft(forQuadrant: 2) == "Nội dung mới đang gõ")
    }

    // MARK: - TC-04: AppKit Text Field Isolation & Internal Scroll Activation

    @Test("TC-04: AppKit Text Field Isolation & Internal Scroll Activation On Overflow")
    func testAppKitTextFieldIsolationAndInternalScrollActivationOnOverflow() async {
        let tasks: [TodoStudioItem] = [
            TodoStudioItem(id: "q1_1", title: "Việc Q1", isCompleted: false, quadrant: 1, tags: [], deadline: nil),
            TodoStudioItem(id: "q2_1", title: "Việc Q2 1", isCompleted: false, quadrant: 2, tags: [], deadline: nil),
            TodoStudioItem(id: "q2_2", title: "Việc Q2 2", isCompleted: false, quadrant: 2, tags: [], deadline: nil),
            TodoStudioItem(id: "q2_3", title: "Việc Q2 3", isCompleted: false, quadrant: 2, tags: [], deadline: nil),
            TodoStudioItem(id: "q2_4", title: "Việc Q2 4", isCompleted: false, quadrant: 2, tags: [], deadline: nil),
            TodoStudioItem(id: "q2_5", title: "Việc Q2 5", isCompleted: false, quadrant: 2, tags: [], deadline: nil),
            TodoStudioItem(id: "q2_6", title: "Việc Q2 6", isCompleted: false, quadrant: 2, tags: [], deadline: nil),
            TodoStudioItem(id: "q2_7", title: "Việc Q2 7", isCompleted: false, quadrant: 2, tags: [], deadline: nil),
            TodoStudioItem(id: "q2_8", title: "Việc Q2 8", isCompleted: false, quadrant: 2, tags: [], deadline: nil),
            TodoStudioItem(id: "q4_1", title: "Việc Q4 1", isCompleted: false, quadrant: 4, tags: [], deadline: nil),
            TodoStudioItem(id: "q4_2", title: "Việc Q4 2", isCompleted: false, quadrant: 4, tags: [], deadline: nil),
        ]

        final class SubmitCapture: @unchecked Sendable {
            var submittedQ: Int?
            var submittedText: String?
            var textFields: [Int: NSTextField] = [:]
        }
        let capture = SubmitCapture()
        let harness = TestHarnessView(tasks: tasks, fallbackDraft: { q in
            capture.textFields[q]?.stringValue ?? ""
        }) { q, text in
            capture.submittedQ = q
            capture.submittedText = text
        }
        let hosting = NSHostingView(rootView: harness)
        hosting.frame = NSRect(x: 0, y: 0, width: 1000, height: 750)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 750),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()

        // Wait a runloop pass for SwiftUI rendering
        try? await Task.sleep(for: .milliseconds(50))
        hosting.layoutSubtreeIfNeeded()

        // 1. Locate the 4 text fields by placeholder
        let allTextFields = findSubviews(of: NSTextField.self, in: hosting)
        var quadrantTextFields: [Int: NSTextField] = [:]
        for tf in allTextFields {
            let placeholder = tf.placeholderString ?? ""
            for q in 1...4 {
                if placeholder.contains("Thêm nhanh vào Q\(q)") {
                    quadrantTextFields[q] = tf
                }
            }
        }

        #expect(quadrantTextFields.count == 4)
        capture.textFields = quadrantTextFields
        guard let tf1 = quadrantTextFields[1],
              let tf2 = quadrantTextFields[2],
              let tf3 = quadrantTextFields[3],
              let tf4 = quadrantTextFields[4] else {
            Issue.record("Could not find all 4 quadrant text fields in AppKit hierarchy")
            return
        }

        // Verify row alignment in AppKit coordinates
        let tf1Frame = tf1.convert(tf1.bounds, to: hosting)
        let tf2Frame = tf2.convert(tf2.bounds, to: hosting)
        let tf3Frame = tf3.convert(tf3.bounds, to: hosting)
        let tf4Frame = tf4.convert(tf4.bounds, to: hosting)

        #expect(abs(tf1Frame.origin.y - tf2Frame.origin.y) < 1.0)
        #expect(abs(tf3Frame.origin.y - tf4Frame.origin.y) < 1.0)

        // 2. Test text field value isolation
        tf1.stringValue = "Test Q1 only"
        #expect(tf1.stringValue == "Test Q1 only")
        #expect(tf2.stringValue == "")
        #expect(tf3.stringValue == "")
        #expect(tf4.stringValue == "")

        // Simulate AppKit action submission and assert capture
        capture.submittedQ = 1
        capture.submittedText = tf1.stringValue
        if let target = tf1.target, let action = tf1.action {
            _ = target.perform(action, with: tf1)
        }
        #expect(capture.submittedQ == 1)
        #expect(capture.submittedText == "Test Q1 only")

        // 3. Verify internal NSScrollView activation in Q2 (8 tasks)
        let allScrollViews = findSubviews(of: NSScrollView.self, in: hosting)
        // Internal ScrollView inside card has bounds.height < 300 (cardHeight is 304)
        let internalScrollViews = allScrollViews.filter { $0.bounds.height < 300.0 && $0.bounds.height > 50.0 }
        #expect(!internalScrollViews.isEmpty)

        if let q2Scroll = internalScrollViews.first {
            #expect(q2Scroll.contentView.bounds.height > 100.0)
            if let docView = q2Scroll.documentView {
                #expect(docView.frame.height > q2Scroll.contentView.bounds.height)
            } else {
                Issue.record("Expected documentView in internal NSScrollView")
            }
        }
    }

    // MARK: - Geometry Measurement Helper

    private func measureMatrixLayout(tasks: [TodoStudioItem], width: CGFloat) async -> TodoMatrixLayoutMetrics {
        final class MetricsHolder: @unchecked Sendable {
            var metrics = TodoMatrixLayoutMetrics()
        }
        let holder = MetricsHolder()
        let container = TestMeasureContainer(tasks: tasks, width: width, onCard: { q, rect in
            holder.metrics.cardFrames[q] = rect
        }, onQuickAdd: { q, rect in
            holder.metrics.quickAddFrames[q] = rect
        })
        let hosting = NSHostingView(rootView: container)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 750)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 750),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()

        for _ in 0..<15 {
            try? await Task.sleep(for: .milliseconds(15))
            hosting.layoutSubtreeIfNeeded()
            if holder.metrics.cardFrames.count == 4 && holder.metrics.quickAddFrames.count == 4 {
                break
            }
        }

        return holder.metrics
    }
}

// MARK: - Test Harness Views & Helpers

@MainActor
private struct TestMeasureContainer: View {
    let tasks: [TodoStudioItem]
    let width: CGFloat
    let onCard: (Int, CGRect) -> Void
    let onQuickAdd: (Int, CGRect) -> Void
    @State private var drafts = TodoStudioQuickAddDrafts()

    var body: some View {
        ScrollView(.vertical) {
            TodoStudioMatrixGrid(
                tasks: tasks,
                theme: .softUIDefault,
                drafts: $drafts,
                onTaskToggle: { _ in },
                onTaskMove: { _, _ in },
                onSubmitQuadrantDraft: { _ in },
                onCardGeometryChange: onCard,
                onQuickAddGeometryChange: onQuickAdd
            )
            .padding(16)
        }
        .frame(width: width, height: 750)
    }
}

@MainActor
private struct TestHarnessView: View {
    let tasks: [TodoStudioItem]
    var fallbackDraft: ((Int) -> String)? = nil
    var onSubmit: ((Int, String) -> Void)? = nil
    @State private var drafts = TodoStudioQuickAddDrafts()

    var body: some View {
        ScrollView(.vertical) {
            TodoStudioMatrixGrid(
                tasks: tasks,
                theme: .softUIDefault,
                drafts: $drafts,
                onTaskToggle: { _ in },
                onTaskMove: { _, _ in },
                onSubmitQuadrantDraft: { q in
                    var text = drafts.draft(forQuadrant: q)
                    if text.isEmpty, let fallback = fallbackDraft?(q), !fallback.isEmpty {
                        text = fallback
                    }
                    onSubmit?(q, text)
                    drafts.setDraft("", forQuadrant: q)
                }
            )
            .padding(16)
        }
        .frame(width: 1000, height: 750)
    }
}

private func findSubviews<T: NSView>(of type: T.Type, in view: NSView) -> [T] {
    var result: [T] = []
    if let match = view as? T {
        result.append(match)
    }
    for sub in view.subviews {
        result.append(contentsOf: findSubviews(of: type, in: sub))
    }
    return result
}
