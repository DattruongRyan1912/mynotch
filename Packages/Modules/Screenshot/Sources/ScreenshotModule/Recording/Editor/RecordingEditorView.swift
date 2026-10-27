import AppKit
import SwiftUI

/// The editor of one recording: the preview, the timeline and what to do to the recording, and below them the export. The host
/// owns the window and builds the model once and keeps it, so the preview is not built again whenever SwiftUI recreates this view.
struct RecordingEditorView: View {
    let model: RecordingEditorModel
    let player: RecordingPlayer

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            preview
            Divider()
            transport
            RecordingTimelineView(model: model)
                .disabled(model.isExporting)
            if let index = model.selectedZoom, model.zoomSegments.indices.contains(index) {
                ZoomInspector(model: model, index: index, scale: model.zoomSegments[index].scale)
                    .id(index)
            }
            if let message = model.message { notice(message) }
            Divider()
            exportBar
        }
        .frame(minWidth: 820, minHeight: 640)
        .background(shortcuts)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { model.undo() } label: { Label("Hoàn tác", systemImage: "arrow.uturn.backward") }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!model.canUndo || model.isExporting)
            Button { model.redo() } label: { Label("Làm lại", systemImage: "arrow.uturn.forward") }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!model.canRedo || model.isExporting)
            Divider().frame(height: 18)
            Toggle("Vòng tròn khi bấm", isOn: Binding(get: { model.clickEffect }, set: { model.setClickEffect($0) }))
                .toggleStyle(.switch)
                .disabled(model.isExporting)
            Spacer()
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Preview

    private var preview: some View {
        ZStack {
            Color.black
            if let error = model.previewError {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.white)
            } else if model.preview == nil {
                ProgressView().controlSize(.small).colorScheme(.dark)
            } else {
                RecordingPreviewView(player: player.player)
                    .accessibilityLabel("Xem trước bản quay")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 280)
    }

    // MARK: Transport

    private var transport: some View {
        HStack(spacing: 12) {
            Button { model.togglePlayback() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").frame(width: 16)
            }
            .help(model.isPlaying ? "Tạm dừng" : "Phát")
            .accessibilityLabel(model.isPlaying ? "Tạm dừng" : "Phát")
            .disabled(model.preview == nil)
            Text("\(TimelineGeometry.label(for: player.editedTime)) / \(TimelineGeometry.label(for: model.cutMap.editedDuration))")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Vị trí và thời lượng sau khi cắt")
            Spacer()
            Menu {
                Section("Tự động gán zoom theo cú bấm") {
                    Button("Gán toàn bộ cú bấm (1,5 giây)") { model.generateZoomsFromClicks(holdDuration: 1.5) }
                    Button("Gán toàn bộ cú bấm (1,0 giây)") { model.generateZoomsFromClicks(holdDuration: 1.0) }
                    Button("Gán toàn bộ cú bấm (2,0 giây)") { model.generateZoomsFromClicks(holdDuration: 2.0) }
                }
                Section {
                    Button(role: .destructive) { model.clearAllZooms() } label: {
                        Label("Xoá toàn bộ zoom", systemImage: "trash")
                    }
                    .disabled(model.zoomSegments.isEmpty)
                }
            } label: {
                Label("Tự động tạo zoom", systemImage: "wand.and.stars")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(model.isExporting || model.activity.clicks.isEmpty)
            Button { model.addZoom(at: model.playhead) } label: { Label("Thêm zoom tại đây", systemImage: "plus.magnifyingglass") }
                .disabled(model.isExporting)
            if model.selectionIsCut {
                Button { model.restoreSelection() } label: { Label("Khôi phục", systemImage: "arrow.uturn.backward.circle") }
                    .help("Đưa đoạn đã cắt trở lại")
            } else {
                Button { model.cutSelection() } label: { Label("Cắt", systemImage: "scissors") }
                    .disabled(!model.canCutSelection)
                    .help("Bỏ đoạn đang chọn trên dải ảnh")
            }
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// Space plays and pauses; Delete removes the selected zoom.
    private var shortcuts: some View {
        ZStack {
            Button("Phát hoặc tạm dừng") { model.togglePlayback() }.keyboardShortcut(.space, modifiers: [])
            Button("Xoá zoom đang chọn") { model.removeSelectedZoom() }.keyboardShortcut(.delete, modifiers: [])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func notice(_ message: String) -> some View {
        HStack {
            Label(message, systemImage: "info.circle").font(.callout)
            Spacer()
            Button("Đóng") { model.dismissMessage() }.buttonStyle(.link)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: Export

    @ViewBuilder private var exportBar: some View {
        HStack(spacing: 12) {
            switch model.exportState {
            case .idle:
                Picker("Mức xuất", selection: Binding(get: { model.exportLevel }, set: { model.exportLevel = $0 })) {
                    ForEach(ExportLevel.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
                .accessibilityLabel("Mức xuất")
                Text(levelHint).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { model.startExport() } label: { Label("Xuất", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.preview == nil)
            case .running(let fraction):
                ProgressView(value: fraction)
                    .accessibilityLabel("Tiến độ xuất")
                Text(fraction.formatted(.percent.precision(.fractionLength(0)))).font(.callout.monospacedDigit()).frame(width: 44, alignment: .trailing)
                Button("Huỷ") { model.cancelExport() }
            case .finished(let result):
                Label("Đã xuất, file đã được chép vào clipboard", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                fileChip(result.url)
                Spacer()
                Button("Hiện trong Finder") { model.revealExport() }
                Button("Xong") { model.dismissExport() }.keyboardShortcut(.defaultAction)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Spacer()
                Button("Đóng") { model.dismissExport() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// What the chosen level makes, from the recording's own size.
    private var levelHint: String {
        let region = model.project.region
        let plan = model.exportLevel.plan(forVideoOfSize: CGSize(width: region.pixelWidth, height: region.pixelHeight), fps: model.project.fps)
        return "\(Int(plan.size.width))×\(Int(plan.size.height)), \(plan.frameRate) khung hình/giây"
    }

    /// The exported file, to drag into a chat, a mail or a folder.
    private func fileChip(_ url: URL) -> some View {
        Label(url.lastPathComponent, systemImage: "film")
            .font(.callout)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: .rect(cornerRadius: 6))
            .onDrag { NSItemProvider(object: url as NSURL) }
            .help("Kéo file ra ngoài để gửi")
            .accessibilityLabel("File đã xuất: \(url.lastPathComponent)")
            .accessibilityHint("Kéo ra để gửi")
    }
}

/// The scale of the selected zoom and a button to remove it. The slider shows a draft as it moves and tells the model when it
/// is let go, so a drag is one undo step.
private struct ZoomInspector: View {
    let model: RecordingEditorModel
    let index: Int
    let scale: Double
    @State private var draft: Double?

    var body: some View {
        HStack(spacing: 12) {
            Text("Mức phóng to").font(.callout)
            Slider(
                value: Binding(get: { draft ?? scale }, set: { draft = $0 }), in: RecordingEditorModel.zoomScaleRange, step: 0.05,
                onEditingChanged: { editing in
                    if !editing, let value = draft {
                        model.setZoomScale(value, at: index)
                        draft = nil
                    }
                }
            )
            .frame(maxWidth: 260)
            .accessibilityLabel("Mức phóng to của đoạn zoom")
            Text(RecordingTimelineView.scaleLabel(draft ?? scale)).font(.callout.monospacedDigit()).frame(width: 48, alignment: .leading)
            Spacer()
            Button(role: .destructive) { model.removeZoom(at: index) } label: { Label("Xoá zoom", systemImage: "trash") }
                .labelStyle(.titleAndIcon)
        }
        .disabled(model.isExporting)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}
