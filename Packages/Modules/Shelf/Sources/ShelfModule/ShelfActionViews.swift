import SwiftUI

/// The "Hành động" row under the cards: one button for each kind of action. The buttons work on the picked cards,
/// and a file dropped on one runs it at once.
struct ShelfActionsRow: View {
    let module: ShelfModule

    var body: some View {
        let picked = module.selectedItems.count
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                Text(picked == 0 ? "Hành động" : "Hành động · \(picked) file")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                ForEach(ShelfActionGroup.allCases, id: \.self) { group in
                    ShelfActionChip(group: group, module: module, isEnabled: picked > 0)
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

struct ShelfActionChip: View {
    let group: ShelfActionGroup
    let module: ShelfModule
    /// Whether any card is picked. A drop works either way.
    let isEnabled: Bool

    @State private var isTargeted = false

    var body: some View {
        control
            .controlSize(.small)
            .buttonStyle(.bordered)
            .disabled(!isEnabled)
            // Outside the disabled control: a file can be dropped on the button when nothing is picked.
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 2).opacity(isTargeted ? 1 : 0))
            .onDrop(of: ShelfModule.dropTypes, isTargeted: $isTargeted) { module.runAction(on: group, dropping: $0) }
            .help(isEnabled ? group.title : "Chọn file trên khay, hoặc thả file vào nút này")
    }

    @ViewBuilder private var control: some View {
        let choices = group.choices
        if choices.count == 1 {
            Button { run(choices[0].action) } label: { label }
        } else {
            Menu {
                ForEach(choices.indices, id: \.self) { index in
                    Button(choices[index].title) { run(choices[index].action) }
                }
            } label: { label }
            .menuIndicator(.hidden)
        }
    }

    private var label: some View {
        Label(group.title, systemImage: group.systemImage).font(.system(size: 11))
    }

    private func run(_ action: FileAction) {
        module.runAction(action, on: module.selectedItems)
    }
}

/// Takes the place of the cards while an action runs and after it, until the user closes the report.
struct ShelfActionStatusView: View {
    let state: ShelfState
    let module: ShelfModule

    var body: some View {
        switch state.actions.phase {
        case .idle:
            EmptyView()
        case .running(let progress):
            running(progress)
        case .finished(let report):
            ShelfActionReportView(report: report, module: module)
        }
    }

    private func running(_ progress: FileActionRunner.Progress) -> some View {
        HStack(spacing: 10) {
            if let total = progress.total {
                ProgressView(value: Double(progress.done), total: Double(total)).frame(width: 110)
            } else {
                ProgressView().controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(progress.action.title).font(.system(size: 12, weight: .medium))
                Text(progress.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button("Huỷ", action: module.cancelAction).controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// What an action did: how many files it made, the text it read, and which files it could not process and why.
struct ShelfActionReportView: View {
    let report: FileActionRunner.Report
    let module: ShelfModule

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: report.failures.isEmpty && !report.wasCancelled ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(report.failures.isEmpty && !report.wasCancelled ? Color.green : Color.orange)
                Text("\(report.action.title): \(report.summary)").font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer()
                if report.text != nil {
                    Button("Chép lại") { module.copyReportText() }.controlSize(.small)
                }
                Button("Đóng", action: module.dismissActionReport).controlSize(.small)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if let text = report.text {
                        Text(text)
                            .font(.system(size: 11))
                            .textSelection(.enabled)
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.08), in: .rect(cornerRadius: 6))
                    }
                    ForEach(report.failures.indices, id: \.self) { index in
                        Text("\(report.failures[index].name): \(report.failures[index].message)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
