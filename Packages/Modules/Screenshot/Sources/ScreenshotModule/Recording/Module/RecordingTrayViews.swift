import NotchUI
import SwiftUI

/// A small capsule button in the tab, drawn with the notch's own colours so it reads on glass and on the classic notch alike.
struct RecordingCapsuleStyle: ButtonStyle {
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(NotchTokens.primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint?.opacity(0.35) ?? NotchTokens.fill(0.12)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The right end of the tab's top row: "Quay" while idle, and what is going on once it is: the countdown, or the clock with Tạm dừng
/// and Dừng.
struct RecordingControlsView: View {
    let module: ScreenshotModule

    var body: some View {
        switch module.state.recordingPhase {
        case .idle:
            HStack(spacing: 4) {
                Button {
                    module.toggleMicrophone()
                } label: {
                    Image(systemName: module.state.isMicrophoneEnabled ? "mic.fill" : "mic.slash.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(module.state.isMicrophoneEnabled ? NotchTokens.primaryText : Color.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(module.state.isMicrophoneEnabled ? NotchTokens.fill(0.12) : Color.red.opacity(0.2)))
                }
                .buttonStyle(.plain)
                .help(module.state.isMicrophoneEnabled ? "Micro đang bật (Bấm để tắt)" : "Micro đang tắt (Bấm để bật)")
                .accessibilityLabel(module.state.isMicrophoneEnabled ? "Micro đang bật" : "Micro đang tắt")

                Menu {
                    Section {
                        Button("Cả màn hình", systemImage: "display") { module.beginRecording(.screen) }
                        Button("Một cửa sổ", systemImage: "macwindow") { module.beginRecording(.window) }
                        Button("Một vùng", systemImage: "rectangle.dashed") { module.beginRecording(.region) }
                    }
                    Section {
                        Button(module.state.isMicrophoneEnabled ? "Tắt micro" : "Bật micro",
                               systemImage: module.state.isMicrophoneEnabled ? "mic.slash" : "mic") {
                            module.toggleMicrophone()
                        }
                    }
                } label: {
                    Label {
                        Text("Quay")
                    } icon: {
                        Image(systemName: "record.circle").foregroundStyle(Color.red)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchTokens.primaryText)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(NotchTokens.fill(0.12)))
            }
        case .selecting, .starting:
            status("Đang chuẩn bị…")
        case .countdown(let seconds):
            HStack(spacing: 8) {
                status("Quay sau \(seconds)…")
                Button("Huỷ") { module.cancelRecordingCountdown() }.buttonStyle(RecordingCapsuleStyle())
            }
        case .recording, .paused:
            HStack(spacing: 8) {
                RecordingDot(isPaused: module.state.recordingPhase == .paused, size: 12)
                // The clock is read again every second; nothing publishes it.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(RecordingElapsed.text(module.recordingElapsed))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(NotchTokens.primaryText)
                }
                Image(systemName: module.state.isMicrophoneEnabled ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(module.state.isMicrophoneEnabled ? NotchTokens.secondaryText : Color.red)
                    .help(module.state.isMicrophoneEnabled ? "Đang thu tiếng micro" : "Không thu tiếng micro")
                Button(module.state.recordingPhase == .paused ? "Tiếp tục" : "Tạm dừng") { module.toggleRecordingPause() }
                    .buttonStyle(RecordingCapsuleStyle())
                Button("Dừng") { module.stopRecording() }.buttonStyle(RecordingCapsuleStyle(tint: .red))
            }
        case .stopping:
            status("Đang lưu…")
        }
    }

    private func status(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(NotchTokens.secondaryText)
    }
}

/// "Bản quay gần đây": one row for each, with its size, and Mở and Xoá. Xoá asks first, in the row itself.
struct RecordingListView: View {
    static let emptyMessage = "Chưa có bản quay nào.\nBấm Quay, hoặc dùng phím tắt (mặc định ⌃⌥R)."

    let module: ScreenshotModule
    /// The recording asked to be deleted and waiting for the answer; the tab keeps the notch open meanwhile.
    @Binding var pendingDelete: UUID?

    var body: some View {
        let recordings = module.state.recordings
        if recordings.isEmpty {
            Text(Self.emptyMessage)
                .font(.callout)
                .foregroundStyle(NotchTokens.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 4) {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(recordings) { recording in
                            RecordingRowView(module: module, recording: recording, pendingDelete: $pendingDelete)
                        }
                    }
                }
                .scrollIndicators(.never)
                Text(Self.total(of: recordings))
                    .font(.system(size: 10))
                    .foregroundStyle(NotchTokens.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    /// "3 bản quay, 1,2 GB".
    static func total(of recordings: [RecordingSummary]) -> String {
        let bytes = recordings.reduce(Int64(0)) { $0 + $1.bytes }
        return "\(recordings.count) bản quay, \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
    }
}

struct RecordingRowView: View {
    let module: ScreenshotModule
    let recording: RecordingSummary
    @Binding var pendingDelete: UUID?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "film")
                .font(.system(size: 14))
                .foregroundStyle(NotchTokens.secondaryText)
            if pendingDelete == recording.id {
                Text("Xoá bản quay này?")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchTokens.primaryText)
                Spacer(minLength: 0)
                Button("Huỷ") { pendingDelete = nil }.buttonStyle(RecordingCapsuleStyle())
                Button("Xoá") {
                    pendingDelete = nil
                    module.deleteRecording(recording)
                }
                .buttonStyle(RecordingCapsuleStyle(tint: .red))
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(recording.createdAt, format: .dateTime.day().month().hour().minute())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NotchTokens.primaryText)
                    Text(Self.detail(of: recording))
                        .font(.system(size: 10))
                        .foregroundStyle(NotchTokens.secondaryText)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                Button("Mở") { module.openRecording(recording) }.buttonStyle(RecordingCapsuleStyle())
                Button("Xoá") { pendingDelete = recording.id }.buttonStyle(RecordingCapsuleStyle())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8).fill(NotchTokens.fill(0.08)))
        .accessibilityElement(children: .contain)
    }

    /// "01:23 · 120 MB", with "quay dở" for a recording that ended before it was stopped.
    static func detail(of recording: RecordingSummary) -> String {
        var parts = [RecordingElapsed.text(recording.duration), ByteCountFormatter.string(fromByteCount: recording.bytes, countStyle: .file)]
        if recording.isIncomplete { parts.append("quay dở") }
        return parts.joined(separator: " · ")
    }
}
