import SwiftUI

/// Plain rows: the Settings page provides the Form and the section.
struct AIAgentsSettingsView: View {
    @Binding var claudeEnabled: Bool
    @Binding var codexEnabled: Bool
    @Binding var showWorkingActivity: Bool
    @Binding var finishedSeconds: Int

    var body: some View {
        Group {
            Toggle("Theo dõi Claude Code", isOn: $claudeEnabled)
            Toggle("Theo dõi Codex", isOn: $codexEnabled)
            Toggle(isOn: $showWorkingActivity) {
                Text("Hiện bên cạnh notch khi agent đang làm việc")
                Text("Vẫn báo khi agent chờ bạn hoặc vừa xong.")
            }
            Stepper(value: $finishedSeconds, in: AIAgentsSettingsKeys.finishedSecondsRange) {
                Text("Hiện dấu ✓ khi xong trong \(finishedSeconds) giây")
            }
            // Placeholder: the hooks that tell when an agent waits for a permission come with a later version.
            LabeledContent {
                Toggle("Trạng thái chính xác (sắp có)", isOn: .constant(false))
                    .labelsHidden()
                    .disabled(true)
            } label: {
                Text("Trạng thái chính xác (sắp có)")
                Text("Biết lúc agent chờ duyệt quyền. Cần cài hook cho Claude Code và Codex.")
            }
        }
    }
}
