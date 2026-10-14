import SwiftUI

/// The Settings rows for YouTube captions from Chrome: the switch, the status of the bridge and its two buttons.
/// Plain rows, like the others; the Settings page provides the Form and the section.
struct YouTubeBridgeRows: View {
    static let title = "Phụ đề YouTube làm lời"
    /// The rest of the sentence the title begins: "Phụ đề YouTube làm lời: khi bạn bật ...".
    static let explanation = "khi bạn bật phụ đề (CC) trên YouTube trong Chrome, extension MyNotch chuyển phụ đề đó sang notch. Không có gì được gửi lên mạng."
    static let installTitle = "Cài cầu nối cho Chrome"
    static let removeTitle = "Gỡ cầu nối"

    @Binding var isOn: Bool
    let model: YouTubeBridgeModel

    var body: some View {
        Group {
            Toggle(isOn: $isOn) {
                Text(Self.title)
                Text(Self.explanation)
            }
            LabeledContent("Cầu nối Chrome") {
                // The status turns back to "waiting" 30 s after the last message, with nothing else to redraw it.
                TimelineView(.periodic(from: .now, by: 2)) { timeline in
                    let status = model.status(at: timeline.date)
                    Text(status.text).foregroundStyle(status == .connected ? .green : .secondary)
                }
            }
            if model.listenFailed {
                Text(YouTubeBridgeModel.listenFailureMessage).font(.caption).foregroundStyle(.red)
            }
            if model.accessWithheld {
                Text(YouTubeBridgeModel.accessWithheldMessage).font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Button(Self.installTitle) { model.install() }
                Button(Self.removeTitle, role: .destructive) { model.remove() }
            }
            if !model.message.isEmpty {
                Text(model.message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        // Files may have been removed by hand since the page was last shown.
        .onAppear { model.refresh() }
    }
}
