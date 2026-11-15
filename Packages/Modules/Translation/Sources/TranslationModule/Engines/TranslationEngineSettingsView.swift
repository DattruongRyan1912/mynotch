import SwiftUI

/// "Bộ máy dịch": the picker, and for an engine that needs a key its settings, the key and the "Kiểm tra" button. Plain
/// rows, like the rest of the page. The key is typed into a secure field, goes straight to the Keychain and is never
/// shown again.
struct TranslationEngineSettingsView: View {
    @Binding var engine: String
    @Binding var microsoftRegion: String
    @Binding var openAIBaseURL: String
    @Binding var openAIModel: String
    let model: EngineSettingsModel

    @State private var keyInput = ""

    private var choice: EngineChoice { EngineChoice(rawValue: engine) ?? .apple }

    var body: some View {
        Group {
            Picker(selection: Binding(get: { choice.rawValue }, set: { engine = $0 })) {
                ForEach(EngineChoice.allCases, id: \.self) { option in
                    Text(option.title).tag(option.rawValue)
                }
            } label: {
                Text("Bộ máy dịch")
                Text(EngineChoice.privacyNote)
            }
            if choice != .apple { engineRows }
        }
        .task { await model.refresh() }
        .onChange(of: engine) { keyInput = "" }
    }

    @ViewBuilder private var engineRows: some View {
        switch choice {
        case .microsoft:
            TextField("Vùng (region)", text: $microsoftRegion, prompt: Text("southeastasia (để trống nếu global)"))
        case .openAI:
            TextField("Địa chỉ API", text: $openAIBaseURL, prompt: Text("https://api.openai.com/v1"))
            TextField("Model", text: $openAIModel, prompt: Text("gpt-4o-mini"))
        case .apple, .google:
            EmptyView()
        }
        keyRow
        checkRow
    }

    @ViewBuilder private var keyRow: some View {
        if !model.hasLoaded {
            LabeledContent("Key") { ProgressView().controlSize(.small) }
        } else if model.hasKey(choice) {
            LabeledContent("Key") {
                HStack {
                    Text("Đã lưu trong Keychain").foregroundStyle(.secondary)
                    Button("Xoá key") { Task { await model.remove(choice) } }
                }
            }
        } else {
            LabeledContent("Key") {
                HStack {
                    SecureField("Key", text: $keyInput, prompt: Text("Dán key vào đây"))
                        .labelsHidden()
                        .onSubmit(save)
                    Button("Lưu key", action: save)
                        .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        if let error = model.keyError {
            Text(error).foregroundStyle(.orange)
        }
    }

    /// The result of the last check on the left, where a label would be, and the button on the right.
    private var checkRow: some View {
        LabeledContent {
            Button("Kiểm tra") { Task { await model.test(choice) } }
                .disabled(!model.hasKey(choice) || model.checks[choice] == .running)
        } label: {
            switch model.checks[choice] {
            case nil:
                Text("Gửi thử một từ để xem key và cài đặt có dùng được không.").foregroundStyle(.secondary)
            case .running:
                ProgressView().controlSize(.small)
            case .ok:
                Label("OK", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
        }
    }

    private func save() {
        let key = keyInput
        let target = choice
        // The field is emptied at once, so the key is not left on screen or in the view while the Keychain answers.
        keyInput = ""
        Task { await model.save(key, for: target) }
    }
}
