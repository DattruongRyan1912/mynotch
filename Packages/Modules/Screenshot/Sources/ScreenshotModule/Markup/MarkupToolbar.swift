import SwiftUI

/// The editor's row of controls: tools, colours, thickness, undo/redo and the Huỷ / Chép / Lưu actions, with a row under
/// it for the tool that has options (the lens's zoom, the crop's ratio).
struct MarkupToolbar: View {
    @Bindable var model: MarkupEditorModel
    let onCancel: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            controls
            if model.tool == .magnifier { magnificationRow }
            if model.isCropping { cropRow }
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            HStack(spacing: 2) {
                ForEach(MarkupTool.allCases, id: \.self, content: toolButton)
            }
            .padding(2)
            .background(.quaternary, in: .rect(cornerRadius: 7))

            // Redaction and smart erase have neither colour nor thickness.
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
            .disabled(!model.tool.usesStyle)

            Spacer(minLength: 0)

            // Disabled while typing, so ⌘Z edits the text instead.
            ControlGroup {
                Button("Hoàn tác", systemImage: "arrow.uturn.backward", action: model.undo)
                    .keyboardShortcut("z", modifiers: .command)
                    .help("Hoàn tác (⌘Z)")
                    .disabled(!model.canUndo || model.text != nil || model.isCropping)
                Button("Làm lại", systemImage: "arrow.uturn.forward", action: model.redo)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .help("Làm lại (⇧⌘Z)")
                    .disabled(!model.canRedo || model.text != nil || model.isCropping)
            }
            .labelStyle(.iconOnly)
            .fixedSize()

            // Copying or saving while a frame is up would leave out the crop that is not applied yet.
            HStack(spacing: 8) {
                Button("Huỷ", action: onCancel)
                Button("Chép", action: onCopy)
                    .help("Chép ảnh đã sửa")
                    .disabled(model.isCropping)
                Button("Lưu", action: onSave)
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .help(saveHelp)
                    .disabled(model.isCropping)
            }
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// The crop's ratio and its two buttons, shown only while the crop tool is selected: Return applies the frame and Esc
    /// drops it, as the buttons' shortcuts.
    private var cropRow: some View {
        HStack(spacing: 8) {
            Text("Tỉ lệ")
            Picker("Tỉ lệ", selection: Binding(get: { model.cropAspect }, set: { model.setCropAspect($0) })) {
                ForEach(CropAspect.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if let frame = model.cropFrame {
                Text("\(Int(frame.width.rounded())) × \(Int(frame.height.rounded()))")
                    .monospacedDigit()
            } else {
                Text("Kéo trên ảnh để chọn vùng cần giữ")
            }
            Spacer(minLength: 0)
            Button("Huỷ", action: model.cancelCrop)
                .keyboardShortcut(.cancelAction)
                .help("Huỷ khung cắt (Esc)")
            Button("Xong", action: model.applyCrop)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(model.cropFrame == nil)
                .help("Cắt ảnh theo khung (Return)")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var saveHelp: String { "Lưu (⌘S)" }

    private var thicknessTitle: String {
        switch model.tool {
        case .text: "Cỡ chữ"
        case .step: "Cỡ số"
        default: "Độ dày nét"
        }
    }

    /// The lens's zoom, shown only while the lens tool is selected.
    private var magnificationRow: some View {
        HStack(spacing: 8) {
            Text("Độ phóng đại")
            Slider(value: $model.magnification, in: DrawingOptions.magnificationRange, step: 0.5)
                .frame(width: 160)
            Text("\(model.magnification, format: .number.precision(.fractionLength(0...1)))×")
                .monospacedDigit()
                .frame(minWidth: 32, alignment: .leading)
            Spacer(minLength: 0)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .help("Độ phóng đại của kính lúp: 1,5× đến 4×")
    }

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
        .help(tool.hint)
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
