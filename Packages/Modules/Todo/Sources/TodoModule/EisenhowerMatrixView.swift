import NotchUI
import SwiftUI

/// Variant D: Split HUD layout for Eisenhower Matrix in MyNotch Todo tab.
/// Left column: 2x2 Navigator Map (width 130pt) for selecting quadrants.
/// Right column: Active quadrant task pane with full TodoRow actions.
struct EisenhowerMatrixView: View {
    let state: TodoState
    let actions: TodoActions

    private var matrix: [EisenhowerQuadrant: [TodoItem]] {
        state.matrix
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            navigatorMap
                .frame(width: 130)
            taskPane
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Navigator Map (2x2 Grid)

    private var navigatorMap: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                navTile(for: .doFirst)
                navTile(for: .schedule)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 4) {
                navTile(for: .delegate)
                navTile(for: .eliminate)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func navTile(for quadrant: EisenhowerQuadrant) -> some View {
        let isSelected = state.selectedQuadrant == quadrant
        let count = matrix[quadrant]?.count ?? 0

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                state.selectedQuadrant = quadrant
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(quadrant.shortCode)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(quadrant.color)
                    Spacer(minLength: 0)
                    Text("\(count)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isSelected ? NotchTokens.primaryText : NotchTokens.secondaryText)
                }
                Spacer(minLength: 0)
                Text(quadrant.label)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(isSelected ? NotchTokens.primaryText : NotchTokens.secondaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? quadrant.color.opacity(0.15) : NotchTokens.fill(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? quadrant.color.opacity(0.45) : NotchTokens.fill(0.14), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right Task Pane

    private var taskPane: some View {
        let quadrant = state.selectedQuadrant
        let items = matrix[quadrant] ?? []

        return VStack(alignment: .leading, spacing: 4) {
            paneHeader(for: quadrant, count: items.count)

            if items.isEmpty {
                VStack(spacing: 4) {
                    Spacer(minLength: 0)
                    Text("Không có việc nào trong mục này")
                        .font(.system(size: 11))
                        .foregroundStyle(NotchTokens.secondaryText)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(items) { item in
                            TodoRow(
                                item: item,
                                isLingering: state.lingering.contains(item.id),
                                now: state.now,
                                calendar: state.calendar,
                                showsQuadrantBadge: false,
                                complete: { actions.complete(item.id) },
                                undo: { actions.undo(item.id) },
                                move: { actions.moveToQuadrant(item.id, $0) }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func paneHeader(for quadrant: EisenhowerQuadrant, count: Int) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(quadrant.color)
                .frame(width: 6, height: 6)
            Text("\(quadrant.shortCode) · \(quadrant.title)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchTokens.primaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text("\(count) việc")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(NotchTokens.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }
}
