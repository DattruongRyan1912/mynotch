import SwiftUI

/// Plain rows: the Settings page provides the Form and the section.
struct AIAgentsSettingsView: View {
    @Binding var claudeEnabled: Bool
    @Binding var codexEnabled: Bool
    @Binding var showWorkingActivity: Bool
    @Binding var finishedSeconds: Int
    @Binding var preciseStatus: Bool
    let hooks: HookSetupModel
    /// The file a pending "install" waits for the user to confirm.
    @State private var confirming: HookSetupModel.Target?

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
            Toggle(isOn: $preciseStatus) {
                Text("Trạng thái chính xác")
                Text("Biết lúc agent chờ duyệt quyền. Cần cài hook cho Claude Code và Codex.")
            }
            LabeledContent("Claude Code") {
                HStack {
                    Button("Cài cho Claude Code") { hooks.installClaudePlugin() }
                    Button("Cài vào settings.json") { confirming = .claude }
                    Button("Gỡ") { hooks.remove(.claude) }
                }
            }
            if !hooks.pluginCommands.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(hooks.pluginCommands.joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Button("Sao chép lệnh") { hooks.copyPluginCommands() }
                }
            }
            LabeledContent("Codex") {
                HStack {
                    Button("Cài vào hooks.json") { confirming = .codex }
                    Button("Gỡ") { hooks.remove(.codex) }
                }
            }
            Text(HookInstaller.codexTrustNote)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !hooks.message.isEmpty {
                Text(hooks.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .alert(
            "Thêm hook vào \(confirming.map { hooks.url(of: $0).lastPathComponent } ?? "")?",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), presenting: confirming
        ) { target in
            Button("Thêm") { hooks.merge(target) }
            Button("Huỷ", role: .cancel) {}
        } message: { target in
            Text(hooks.preview(of: target))
        }
    }
}
