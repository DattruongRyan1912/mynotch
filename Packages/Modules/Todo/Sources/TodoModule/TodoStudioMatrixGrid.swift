import AppKit
import Foundation
import MyNotchCore
import NotchUI
import SwiftUI

// MARK: - Drafts Model

public struct TodoStudioQuickAddDrafts: Equatable, Sendable {
    public var toolbarDraft: String
    public var quadrantDrafts: [Int: String]

    public init(
        toolbarDraft: String = "",
        quadrantDrafts: [Int: String] = [1: "", 2: "", 3: "", 4: ""]
    ) {
        self.toolbarDraft = toolbarDraft
        self.quadrantDrafts = quadrantDrafts
    }

    public func draft(forQuadrant quadrant: Int) -> String {
        guard (1...4).contains(quadrant) else { return "" }
        return quadrantDrafts[quadrant] ?? ""
    }

    public mutating func setDraft(_ text: String, forQuadrant quadrant: Int) {
        guard (1...4).contains(quadrant) else { return }
        quadrantDrafts[quadrant] = text
    }

    public mutating func consumeSubmission(forQuadrant quadrant: Int) -> (rawDraft: String, formattedCommand: String)? {
        guard (1...4).contains(quadrant) else { return nil }
        let raw = draft(forQuadrant: quadrant)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setDraft("", forQuadrant: quadrant)
            return nil
        }
        setDraft("", forQuadrant: quadrant)
        return (rawDraft: raw, formattedCommand: "!q\(quadrant) \(trimmed)")
    }

    public mutating func consumeToolbarSubmission() -> (rawDraft: String, formattedCommand: String)? {
        let raw = toolbarDraft
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            toolbarDraft = ""
            return nil
        }
        toolbarDraft = ""
        return (rawDraft: raw, formattedCommand: trimmed)
    }

    public mutating func restoreDraftIfEmpty(_ text: String, forQuadrant quadrant: Int) {
        guard (1...4).contains(quadrant) else { return }
        if draft(forQuadrant: quadrant).isEmpty && !text.isEmpty {
            setDraft(text, forQuadrant: quadrant)
        }
    }

    public mutating func restoreToolbarDraftIfEmpty(_ text: String) {
        if toolbarDraft.isEmpty && !text.isEmpty {
            toolbarDraft = text
        }
    }
}

// MARK: - Matrix Theme Bridge

public struct TodoStudioMatrixTheme: Sendable {
    public var cardBackground: Color
    public var cardBorder: Color
    public var insetBackground: Color
    public var insetBorder: Color
    public var separator: Color
    public var textPrimary: Color
    public var textSecondary: Color
    public var textMuted: Color
    public var infoAccent: Color
    public var statusCritical: Color
    public var statusNeutral: Color
    public var hardwareCoral: Color
    public var controlBorder: Color
    public var cornerRadius: CGFloat

    public init(
        cardBackground: Color,
        cardBorder: Color,
        insetBackground: Color,
        insetBorder: Color,
        separator: Color,
        textPrimary: Color,
        textSecondary: Color,
        textMuted: Color,
        infoAccent: Color,
        statusCritical: Color,
        statusNeutral: Color,
        hardwareCoral: Color,
        controlBorder: Color,
        cornerRadius: CGFloat = 10
    ) {
        self.cardBackground = cardBackground
        self.cardBorder = cardBorder
        self.insetBackground = insetBackground
        self.insetBorder = insetBorder
        self.separator = separator
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textMuted = textMuted
        self.infoAccent = infoAccent
        self.statusCritical = statusCritical
        self.statusNeutral = statusNeutral
        self.hardwareCoral = hardwareCoral
        self.controlBorder = controlBorder
        self.cornerRadius = cornerRadius
    }

    public static let softUIDefault = TodoStudioMatrixTheme(
        cardBackground: Color.white,
        cardBorder: Color.black.opacity(0.08),
        insetBackground: Color.black.opacity(0.03),
        insetBorder: Color.black.opacity(0.08),
        separator: Color.black.opacity(0.08),
        textPrimary: Color.black.opacity(0.9),
        textSecondary: Color.black.opacity(0.6),
        textMuted: Color.black.opacity(0.4),
        infoAccent: Color(red: 0.12, green: 0.44, blue: 0.95),
        statusCritical: Color(red: 0.92, green: 0.25, blue: 0.25),
        statusNeutral: Color(red: 0.45, green: 0.48, blue: 0.52),
        hardwareCoral: Color(red: 0.95, green: 0.45, blue: 0.25),
        controlBorder: Color.black.opacity(0.1),
        cornerRadius: 10
    )
}

// MARK: - Layout Metrics

public struct TodoMatrixLayoutMetrics: Equatable, Sendable {
    public var cardFrames: [Int: CGRect]
    public var quickAddFrames: [Int: CGRect]

    public init(cardFrames: [Int: CGRect] = [:], quickAddFrames: [Int: CGRect] = [:]) {
        self.cardFrames = cardFrames
        self.quickAddFrames = quickAddFrames
    }
}

// MARK: - Task Row View

public struct TodoStudioTaskRowView: View {
    public let task: TodoStudioItem
    public let theme: TodoStudioMatrixTheme
    public var showsQuadrantBadge: Bool
    public var onToggle: () -> Void
    public var onMove: (Int) -> Void

    public init(
        task: TodoStudioItem,
        theme: TodoStudioMatrixTheme = .softUIDefault,
        showsQuadrantBadge: Bool = false,
        onToggle: @escaping () -> Void,
        onMove: @escaping (Int) -> Void
    ) {
        self.task = task
        self.theme = theme
        self.showsQuadrantBadge = showsQuadrantBadge
        self.onToggle = onToggle
        self.onMove = onMove
    }

    public var body: some View {
        HStack(spacing: 10) {
            // Checkbox
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundColor(task.isCompleted ? theme.infoAccent : theme.textMuted)
            }
            .buttonStyle(.plain)

            // Title & Tags
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 12.5, weight: task.isCompleted ? .regular : .medium))
                    .strikethrough(task.isCompleted, color: theme.textMuted)
                    .foregroundColor(task.isCompleted ? theme.textMuted : theme.textPrimary)
                    .opacity(task.isCompleted ? 0.6 : 1.0)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if showsQuadrantBadge {
                        Text("Q\(task.quadrant)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(theme.infoAccent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(theme.infoAccent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }

                    ForEach(task.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(theme.textSecondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(theme.insetBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }

                    if let deadline = task.deadline {
                        HStack(spacing: 3) {
                            Image(systemName: "clock")
                                .font(.system(size: 9))
                            Text(deadline)
                                .font(.system(size: 10))
                        }
                        .foregroundColor(theme.hardwareCoral)
                    }
                }
            }

            Spacer(minLength: 4)

            // Quick Mover Pills (1..4)
            HStack(spacing: 3) {
                ForEach(1...4, id: \.self) { targetQ in
                    if targetQ != task.quadrant {
                        Button("Q\(targetQ)") {
                            onMove(targetQ)
                        }
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(theme.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(theme.insetBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(9)
        .background(
            task.isCompleted
                ? theme.insetBackground.opacity(0.5)
                : theme.cardBackground
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.cardBorder.opacity(0.8), lineWidth: 1)
        )
    }
}

// MARK: - Quadrant Card View

public struct TodoQuadrantCardView: View {
    public static let cardHeight: CGFloat = 304

    public let quadrant: Int
    public let title: String
    public let accentColor: Color
    public let icon: String
    public let tasks: [TodoStudioItem]
    public let theme: TodoStudioMatrixTheme
    @Binding public var draft: String
    public var onTaskToggle: (TodoStudioItem) -> Void
    public var onTaskMove: (String, Int) -> Void
    public var onSubmitDraft: () -> Void
    public var onCardGeometryChange: ((CGRect) -> Void)?
    public var onQuickAddGeometryChange: ((CGRect) -> Void)?

    public init(
        quadrant: Int,
        title: String,
        accentColor: Color,
        icon: String,
        tasks: [TodoStudioItem],
        theme: TodoStudioMatrixTheme = .softUIDefault,
        draft: Binding<String>,
        onTaskToggle: @escaping (TodoStudioItem) -> Void,
        onTaskMove: @escaping (String, Int) -> Void,
        onSubmitDraft: @escaping () -> Void,
        onCardGeometryChange: ((CGRect) -> Void)? = nil,
        onQuickAddGeometryChange: ((CGRect) -> Void)? = nil
    ) {
        self.quadrant = quadrant
        self.title = title
        self.accentColor = accentColor
        self.icon = icon
        self.tasks = tasks
        self.theme = theme
        self._draft = draft
        self.onTaskToggle = onTaskToggle
        self.onTaskMove = onTaskMove
        self.onSubmitDraft = onSubmitDraft
        self.onCardGeometryChange = onCardGeometryChange
        self.onQuickAddGeometryChange = onQuickAddGeometryChange
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .foregroundColor(accentColor)
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("\(tasks.count)")
                    .font(.system(size: 11.5, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(height: 22)

            Rectangle()
                .fill(theme.separator)
                .frame(height: 1)

            // Middle Content: ViewThatFits handles 0 tasks, 1-3 tasks, and >=4 tasks with internal scroll
            Group {
                if tasks.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 20))
                            .foregroundColor(theme.textMuted.opacity(0.6))
                        Text("Không có việc trong góc này")
                            .font(.system(size: 11.5))
                            .foregroundColor(theme.textMuted)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    ViewThatFits(in: .vertical) {
                        VStack(spacing: 8) {
                            ForEach(tasks) { task in
                                TodoStudioTaskRowView(
                                    task: task,
                                    theme: theme,
                                    onToggle: { onTaskToggle(task) },
                                    onMove: { onTaskMove(task.id, $0) }
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)

                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(spacing: 8) {
                                ForEach(tasks) { task in
                                    TodoStudioTaskRowView(
                                        task: task,
                                        theme: theme,
                                        onToggle: { onTaskToggle(task) },
                                        onMove: { onTaskMove(task.id, $0) }
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Pinned Quick Add input at bottom
            HStack(spacing: 6) {
                TextField(
                    "",
                    text: $draft,
                    prompt: Text("+ Thêm nhanh vào Q\(quadrant)...")
                        .foregroundColor(theme.textMuted)
                )
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .accessibilityIdentifier("todo.matrix.quickAdd.q\(quadrant)")
                .onSubmit {
                    onSubmitDraft()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(theme.insetBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(theme.insetBorder, lineWidth: 1)
                )
            }
            .frame(height: 30)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named("TodoStudioMatrixSpace"))
            } action: { newFrame in
                onQuickAddGeometryChange?(newFrame)
            }
        }
        .padding(14)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: Self.cardHeight, maxHeight: Self.cardHeight, alignment: .topLeading)
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous)
                .stroke(theme.cardBorder, lineWidth: 1)
        )
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named("TodoStudioMatrixSpace"))
        } action: { newFrame in
            onCardGeometryChange?(newFrame)
        }
    }
}

// MARK: - 4 Quadrants Grid

public struct TodoStudioMatrixGrid: View {
    public static let cardHeight: CGFloat = TodoQuadrantCardView.cardHeight

    public let tasks: [TodoStudioItem]
    public let theme: TodoStudioMatrixTheme
    @Binding public var drafts: TodoStudioQuickAddDrafts
    @Binding public var layoutMetrics: TodoMatrixLayoutMetrics
    public var onTaskToggle: (TodoStudioItem) -> Void
    public var onTaskMove: (String, Int) -> Void
    public var onSubmitQuadrantDraft: (Int) -> Void
    public var onCardGeometryChange: ((Int, CGRect) -> Void)?
    public var onQuickAddGeometryChange: ((Int, CGRect) -> Void)?

    public init(
        tasks: [TodoStudioItem],
        theme: TodoStudioMatrixTheme = .softUIDefault,
        drafts: Binding<TodoStudioQuickAddDrafts>,
        layoutMetrics: Binding<TodoMatrixLayoutMetrics> = .constant(TodoMatrixLayoutMetrics()),
        onTaskToggle: @escaping (TodoStudioItem) -> Void,
        onTaskMove: @escaping (String, Int) -> Void,
        onSubmitQuadrantDraft: @escaping (Int) -> Void,
        onCardGeometryChange: ((Int, CGRect) -> Void)? = nil,
        onQuickAddGeometryChange: ((Int, CGRect) -> Void)? = nil
    ) {
        self.tasks = tasks
        self.theme = theme
        self._drafts = drafts
        self._layoutMetrics = layoutMetrics
        self.onTaskToggle = onTaskToggle
        self.onTaskMove = onTaskMove
        self.onSubmitQuadrantDraft = onSubmitQuadrantDraft
        self.onCardGeometryChange = onCardGeometryChange
        self.onQuickAddGeometryChange = onQuickAddGeometryChange
    }

    public var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow(alignment: .top) {
                quadrantCardView(
                    quadrant: 1,
                    title: "Q1: Làm Ngay (Khẩn cấp & Quan trọng)",
                    accentColor: theme.statusCritical,
                    icon: "exclamationmark.triangle.fill"
                )

                quadrantCardView(
                    quadrant: 2,
                    title: "Q2: Lên Kế Hoạch (Chiến lược & Quan trọng)",
                    accentColor: theme.infoAccent,
                    icon: "calendar.badge.clock"
                )
            }

            GridRow(alignment: .top) {
                quadrantCardView(
                    quadrant: 3,
                    title: "Q3: Ủy Quyền (Khẩn cấp, Không quan trọng)",
                    accentColor: theme.hardwareCoral,
                    icon: "person.2.fill"
                )

                quadrantCardView(
                    quadrant: 4,
                    title: "Q4: Loại Bỏ (Không khẩn cấp, Không quan trọng)",
                    accentColor: theme.statusNeutral,
                    icon: "trash.circle"
                )
            }
        }
        .coordinateSpace(name: "TodoStudioMatrixSpace")
    }

    private func quadrantCardView(
        quadrant: Int,
        title: String,
        accentColor: Color,
        icon: String
    ) -> some View {
        let quadrantTasks = tasks.filter { $0.quadrant == quadrant }
        let draftBinding = Binding<String>(
            get: { drafts.draft(forQuadrant: quadrant) },
            set: { drafts.setDraft($0, forQuadrant: quadrant) }
        )

        return TodoQuadrantCardView(
            quadrant: quadrant,
            title: title,
            accentColor: accentColor,
            icon: icon,
            tasks: quadrantTasks,
            theme: theme,
            draft: draftBinding,
            onTaskToggle: onTaskToggle,
            onTaskMove: onTaskMove,
            onSubmitDraft: { onSubmitQuadrantDraft(quadrant) },
            onCardGeometryChange: { rect in
                layoutMetrics.cardFrames[quadrant] = rect
                onCardGeometryChange?(quadrant, rect)
            },
            onQuickAddGeometryChange: { rect in
                layoutMetrics.quickAddFrames[quadrant] = rect
                onQuickAddGeometryChange?(quadrant, rect)
            }
        )
    }
}
