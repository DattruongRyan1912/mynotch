import SwiftUI

/// The editor's single row of controls: tools, colours, thickness, undo/redo and the Huỷ / Copy / Lưu actions.
struct MarkupToolbar: View {
    @Bindable var model: MarkupEditorModel
    let onCancel: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 2) {
                ForEach(MarkupTool.allCases, id: \.self, content: toolButton)
            }
            .padding(2)
            .background(.quaternary, in: .rect(cornerRadius: 7))

            // Redaction has neither colour nor thickness.
            Group {
                HStack(spacing: 4) {
                    ForEach(RGBAColor.presets, id: \.name) { preset in colorButton(preset.name, preset.color) }
                }
                Picker(thicknessTitle, selection: $model.thickness) {
                    ForEach(StrokeThickness.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help(thicknessTitle)
            }
            .disabled(model.tool == .redact)

            Spacer(minLength: 0)

            // Disabled while typing, so ⌘Z edits the text instead.
            ControlGroup {
                Button("Hoàn tác", systemImage: "arrow.uturn.backward", action: model.undo)
                    .keyboardShortcut("z", modifiers: .command)
                    .help("Hoàn tác (⌘Z)")
                    .disabled(!model.canUndo || model.text != nil)
                Button("Làm lại", systemImage: "arrow.uturn.forward", action: model.redo)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .help("Làm lại (⇧⌘Z)")
                    .disabled(!model.canRedo || model.text != nil)
            }
            .labelStyle(.iconOnly)
            .fixedSize()

            HStack(spacing: 8) {
                Button("Huỷ", action: onCancel)
                Button("Copy", action: onCopy)
                    .help("Copy ảnh đã sửa")
                Button("Lưu", action: onSave)
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .help("Lưu (⌘S)")
            }
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var thicknessTitle: String { model.tool == .text ? "Cỡ chữ" : "Độ dày nét" }

    private func toolButton(_ tool: MarkupTool) -> some View {
        let isSelected = model.tool == tool
        return Button { model.select(tool) } label: {
            Image(systemName: tool.systemImage)
                .frame(width: 30, height: 22)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? Color.accentColor : Color.clear, in: .rect(cornerRadius: 5))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(tool.title)
        .accessibilityLabel(tool.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func colorButton(_ name: String, _ color: RGBAColor) -> some View {
        let isSelected = model.color == color
        return Button { model.color = color } label: {
            Circle()
                .fill(Color(color))
                .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                .frame(width: 16, height: 16)
                .padding(3)
                .overlay { Circle().strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2) }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension Color {
    init(_ color: RGBAColor) {
        self.init(.sRGB, red: color.r, green: color.g, blue: color.b, opacity: color.a)
    }
}
